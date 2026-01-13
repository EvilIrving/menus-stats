//
//  AppMemoryManager.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import Foundation
import AppKit
import Combine

// MARK: - Responsibility Framework

/// Import the responsibility framework for process grouping
/// responsibility_get_pid_responsible_for_pid returns the PID of the "responsible" process
@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

// MARK: - App Memory Manager

/// Manages user application information and memory usage
@MainActor
final class AppMemoryManager: ObservableObject {
    
    @Published var runningApps: [AppGroup] = []
    @Published var totalMemoryUsed: UInt64 = 0
    @Published var totalMemory: UInt64 = 0
    @Published var appCount: Int = 0
    
    // Detailed memory info
    @Published var detailedMemory: MemoryInfo.DetailedInfo?
    @Published var memoryPressure: MemoryPressureLevel = .normal
    
    private var timer: Timer?
    
    static let shared = AppMemoryManager()
    
    /// Cache of known user app bundle identifiers for WebKit process attribution
    private var knownAppBundleIds: Set<String> = []
    
    private init() {
        totalMemory = ProcessInfo.processInfo.physicalMemory
    }
    
    func startMonitoring(interval: TimeInterval = 3.0) {
        stopMonitoring()
        
        // Initial update
        Task {
            await updateRunningApps()
        }
        
        // Periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateRunningApps()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func updateRunningApps() async {
        // Step 1: Get top N memory-consuming processes using top command
        let topProcesses = await getTopMemoryProcesses(count: 100)
        
        // Step 2: Get running GUI apps for icons and bundle identifiers
        let workspace = NSWorkspace.shared
        let guiApps = workspace.runningApplications
        
        // Build lookup maps for GUI apps
        var guiAppByPid: [pid_t: NSRunningApplication] = [:]
        var guiAppByBundleId: [String: NSRunningApplication] = [:]
        knownAppBundleIds.removeAll()
        
        for app in guiApps {
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            guiAppByPid[app.processIdentifier] = app
            if let bundleId = app.bundleIdentifier {
                knownAppBundleIds.insert(bundleId)
                if guiAppByBundleId[bundleId] == nil {
                    guiAppByBundleId[bundleId] = app
                }
            }
        }
        
        // Step 3: Group processes by responsible PID
        var groupedByResponsible: [pid_t: [TopProcessInfo]] = [:]
        var pidToBundleInfo: [pid_t: ProcessBundleInfo] = [:]
        
        for process in topProcesses {
            let responsiblePid = responsibility_get_pid_responsible_for_pid(process.pid)
            // Use the responsible PID, fallback to self if 0
            let groupPid = responsiblePid > 0 ? responsiblePid : process.pid
            groupedByResponsible[groupPid, default: []].append(process)
            
            // Cache bundle info for each process
            if pidToBundleInfo[process.pid] == nil {
                pidToBundleInfo[process.pid] = getBundleInfo(for: process.pid)
            }
        }
        
        // Step 4: Build initial app groups (keyed by responsible PID)
        var initialGroups: [pid_t: (processes: [TopProcessInfo], bundleInfo: ProcessBundleInfo)] = [:]
        
        for (responsiblePid, processes) in groupedByResponsible {
            let bundleInfo = getBundleInfo(for: responsiblePid)
            initialGroups[responsiblePid] = (processes: processes, bundleInfo: bundleInfo)
        }
        
        // Step 5: Merge groups by BundleID (for multi-process apps like Electron)
        var mergedByBundleId: [String: (mainPid: pid_t, processes: [TopProcessInfo], bundleInfo: ProcessBundleInfo)] = [:]
        var ungroupedGroups: [(pid: pid_t, processes: [TopProcessInfo], bundleInfo: ProcessBundleInfo)] = []
        
        for (responsiblePid, data) in initialGroups {
            // Try to get bundleId from the group's processes
            var effectiveBundleId: String? = data.bundleInfo.bundleId
            
            // If responsible process has no bundleId, check its processes
            if effectiveBundleId == nil {
                for process in data.processes {
                    if let info = pidToBundleInfo[process.pid], let bid = info.bundleId {
                        effectiveBundleId = bid
                        break
                    }
                }
            }
            
            if let bundleId = effectiveBundleId, !bundleId.isEmpty {
                if var existing = mergedByBundleId[bundleId] {
                    // Merge into existing group
                    existing.processes.append(contentsOf: data.processes)
                    // Keep the main PID with higher memory usage
                    let existingMemory = existing.processes.filter { $0.pid == existing.mainPid }.first?.memoryBytes ?? 0
                    let newMemory = data.processes.reduce(0) { $0 + $1.memoryBytes }
                    if newMemory > existingMemory {
                        existing.mainPid = responsiblePid
                        existing.bundleInfo = data.bundleInfo
                    }
                    mergedByBundleId[bundleId] = existing
                } else {
                    mergedByBundleId[bundleId] = (mainPid: responsiblePid, processes: data.processes, bundleInfo: data.bundleInfo)
                }
            } else {
                ungroupedGroups.append((pid: responsiblePid, processes: data.processes, bundleInfo: data.bundleInfo))
            }
        }
        
        // Step 6: Build final app groups
        var appGroups: [AppGroup] = []
        
        // Process merged groups (by BundleID)
        for (bundleId, data) in mergedByBundleId {
            let bundleInfo = data.bundleInfo
            
            // 过滤规则
            if !shouldShowProcess(bundleInfo) {
                continue
            }
            
            let totalMemory = data.processes.reduce(0) { $0 + $1.memoryBytes }
            let allPids = data.processes.map { $0.pid }
            
            let guiApp = guiAppByBundleId[bundleId] ?? guiAppByPid[data.mainPid]
            let name: String
            let icon: NSImage
            let bundlePath: String?
            let execPath: String?
            
            if let app = guiApp {
                name = app.localizedName ?? data.processes.first?.command ?? "Unknown"
                icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
                bundlePath = app.bundleURL?.path ?? bundleInfo.bundlePath
                execPath = app.executableURL?.path ?? bundleInfo.execPath
            } else {
                name = getProcessName(for: data.mainPid) ?? data.processes.first?.command ?? "Unknown"
                icon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
                bundlePath = bundleInfo.bundlePath
                execPath = bundleInfo.execPath
            }
            
            let group = AppGroup(
                id: data.mainPid,
                name: name,
                icon: icon,
                totalMemoryBytes: totalMemory,
                processCount: data.processes.count,
                allPids: allPids,
                bundleIdentifier: bundleId,
                bundlePath: bundlePath,
                execPath: execPath
            )
            appGroups.append(group)
        }
        
        // Process ungrouped groups (no BundleID)
        for data in ungroupedGroups {
            let bundleInfo = data.bundleInfo
            
            if !shouldShowProcess(bundleInfo) {
                continue
            }
            
            let totalMemory = data.processes.reduce(0) { $0 + $1.memoryBytes }
            let allPids = data.processes.map { $0.pid }
            
            let guiApp = guiAppByPid[data.pid]
            let name: String
            let icon: NSImage
            let bundleId: String?
            let bundlePath: String?
            let execPath: String?
            
            if let app = guiApp {
                name = app.localizedName ?? data.processes.first?.command ?? "Unknown"
                icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
                bundleId = app.bundleIdentifier ?? bundleInfo.bundleId
                bundlePath = app.bundleURL?.path ?? bundleInfo.bundlePath
                execPath = app.executableURL?.path ?? bundleInfo.execPath
            } else {
                name = getProcessName(for: data.pid) ?? data.processes.first?.command ?? "Unknown"
                icon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
                bundleId = bundleInfo.bundleId
                bundlePath = bundleInfo.bundlePath
                execPath = bundleInfo.execPath
            }
            
            let group = AppGroup(
                id: data.pid,
                name: name,
                icon: icon,
                totalMemoryBytes: totalMemory,
                processCount: data.processes.count,
                allPids: allPids,
                bundleIdentifier: bundleId,
                bundlePath: bundlePath,
                execPath: execPath
            )
            appGroups.append(group)
        }
        
        // Step 7: Sort by total memory usage (descending)
        let sortedGroups = appGroups.sorted { $0.totalMemoryBytes > $1.totalMemoryBytes }
        
        runningApps = sortedGroups
        appCount = sortedGroups.count
        
        // Update detailed memory info
        let detailedInfo = MemoryInfo.getDetailedMemoryInfo()
        detailedMemory = detailedInfo
        totalMemoryUsed = detailedInfo.used
        memoryPressure = detailedInfo.pressureLevel
    }
    
    // MARK: - Bundle Info Extraction
    
    /// 从进程 PID 获取 Bundle 信息
    /// - Parameter pid: 进程 PID
    /// - Returns: ProcessBundleInfo 包含可执行文件路径、Bundle 路径和 Bundle ID
    private func getBundleInfo(for pid: pid_t) -> ProcessBundleInfo {
        // Step 1: 获取可执行文件完整路径
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        
        guard pathLength > 0 else {
            return ProcessBundleInfo(execPath: nil, bundlePath: nil, bundleId: nil)
        }
        
        let execPath = String(cString: pathBuffer)
        
        // Step 2: 检查是否在 .app bundle 内
        // 路径格式如: /Applications/Safari.app/Contents/MacOS/Safari
        guard let appRange = execPath.range(of: ".app/") else {
            // 不在 .app bundle 内（纯命令行工具或守护进程）
            return ProcessBundleInfo(execPath: execPath, bundlePath: nil, bundleId: nil)
        }
        
        // Step 3: 提取 .app bundle 路径（去掉末尾的 "/"）
        let bundlePath = String(execPath[..<appRange.upperBound].dropLast(1))
        
        // Step 4: 从 bundle 读取 Info.plist 获取 Bundle ID
        let bundle = Bundle(path: bundlePath)
        let bundleId = bundle?.bundleIdentifier
        
        return ProcessBundleInfo(execPath: execPath, bundlePath: bundlePath, bundleId: bundleId)
    }
    
    // MARK: - Debug Methods
    
    /// 调试方法：打印所有进程的 Bundle 信息
    func debugPrintAllProcessBundleInfo() async {
        let topProcesses = await getTopMemoryProcesses(count: 100)
        
        print("========== 进程 Bundle 信息 ==========")
        for process in topProcesses {
            let info = getBundleInfo(for: process.pid)
            
            let category: String
            if let bundleId = info.bundleId {
                if info.isSystemApp {
                    category = "🍎 系统应用"
                } else if bundleId.hasPrefix("com.apple.") {
                    category = "🍏 Apple应用"
                } else {
                    category = "📦 第三方应用"
                }
            } else if info.isSystemPath {
                category = "⚙️ 系统服务"
            } else if info.isInAppBundle {
                category = "📱 App内进程"
            } else {
                category = "❓ 其他进程"
            }
            
            print("""
            [\(category)] \(process.command)
              PID: \(process.pid)
              Memory: \(ByteFormatter.format(process.memoryBytes))
              ExecPath: \(info.execPath ?? "N/A")
              BundlePath: \(info.bundlePath ?? "N/A")
              BundleID: \(info.bundleId ?? "N/A")
              isSystemApp: \(info.isSystemApp)
            """)
        }
        print("=====================================")
    }
    
    // MARK: - Top Command Execution
    
    /// Get top N memory-consuming processes using top command
    /// Command: /usr/bin/top -l 1 -o mem -n N -stats pid,command,mem
    private func getTopMemoryProcesses(count: Int) async -> [TopProcessInfo] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/top")
                task.arguments = ["-l", "1", "-o", "mem", "-n", "\(count)", "-stats", "pid,command,mem"]
                
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    let processes = self.parseTopOutput(output)
                    continuation.resume(returning: processes)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Parse top command output
    /// Format: PID COMMAND MEM
    /// MEM can be in bytes, K, M, G, or with +/- suffix
    private func parseTopOutput(_ output: String) -> [TopProcessInfo] {
        var processes: [TopProcessInfo] = []
        let lines = output.components(separatedBy: "\n")
        
        // Find the line that starts with "PID" to skip header
        var dataStarted = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            guard !trimmed.isEmpty else { continue }
            
            // Check for header line
            if trimmed.hasPrefix("PID") {
                dataStarted = true
                continue
            }
            
            // Skip lines before data section
            guard dataStarted else { continue }
            
            // Parse data line: PID COMMAND MEM
            // Use regex to handle varying whitespace
            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            // Need at least 3 components: pid, command, mem
            guard components.count >= 3 else { continue }
            
            guard let pid = pid_t(components[0]) else { continue }
            
            // Memory is the last column
            let memString = components.last ?? "0"
            let memBytes = parseMemoryString(memString)
            
            // Command is everything between pid and mem
            let command = components[1..<(components.count - 1)].joined(separator: " ")
            
            let processInfo = TopProcessInfo(
                pid: pid,
                command: command,
                memoryBytes: memBytes
            )
            processes.append(processInfo)
        }
        
        return processes
    }
    
    /// Parse memory string with unit suffix (K, M, G, B)
    /// Examples: "100M", "1.5G", "512K", "1024B", "100M+", "50M-"
    private func parseMemoryString(_ memString: String) -> UInt64 {
        var str = memString.uppercased()
        
        // Remove +/- suffix if present
        if str.hasSuffix("+") || str.hasSuffix("-") {
            str = String(str.dropLast())
        }
        
        // Check for unit suffix
        let multiplier: UInt64
        var numericPart = str
        
        if str.hasSuffix("G") {
            multiplier = 1024 * 1024 * 1024
            numericPart = String(str.dropLast())
        } else if str.hasSuffix("M") {
            multiplier = 1024 * 1024
            numericPart = String(str.dropLast())
        } else if str.hasSuffix("K") {
            multiplier = 1024
            numericPart = String(str.dropLast())
        } else if str.hasSuffix("B") {
            multiplier = 1
            numericPart = String(str.dropLast())
        } else {
            // Assume bytes if no suffix
            multiplier = 1
        }
        
        // Parse numeric value (handle decimal)
        if let value = Double(numericPart) {
            return UInt64(value * Double(multiplier))
        }
        
        return 0
    }
    
    
    // MARK: - App Control
    
    /// Trigger system memory cleanup
    /// Uses memory pressure simulation to encourage system to release purgeable memory
    func triggerMemoryCleanup() async {
        // Method 1: Allocate and release memory to trigger system cleanup
        // This is a safer approach than running 'purge' command which requires sudo
        let chunkSize = 100 * 1024 * 1024  // 100 MB chunks
        var chunks: [UnsafeMutableRawPointer] = []
        
        // Allocate memory to create pressure
        for _ in 0..<5 {
            if let chunk = malloc(chunkSize) {
                memset(chunk, 0, chunkSize)  // Touch the memory
                chunks.append(chunk)
            }
        }
        
        // Small delay
        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second
        
        // Free the allocated memory
        for chunk in chunks {
            free(chunk)
        }
        
        // Refresh memory stats
        await updateRunningApps()
    }
    
    /// Terminate an app group (handles single and multi-process apps)
    func terminateApp(_ app: AppGroup) -> Bool {
        // Single process: direct terminate
        if app.processCount == 1 {
            guard let nsApp = NSRunningApplication(processIdentifier: app.id) else {
                return false
            }
            return nsApp.terminate()
        }
        
        // Multi-process: terminate main process first
        guard let mainApp = NSRunningApplication(processIdentifier: app.id) else {
            return false
        }
        
        let mainTerminated = mainApp.terminate()
        
        if mainTerminated {
            // Wait briefly then check for surviving child processes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.terminateSurvivingChildren(app.allPids)
            }
        }
        
        return mainTerminated
    }
    
    /// Terminate any surviving child processes
    private func terminateSurvivingChildren(_ pids: [pid_t]) {
        for pid in pids {
            // Check if process still exists
            if kill(pid, 0) == 0 {
                // Process still alive, try to terminate via NSRunningApplication
                if let app = NSRunningApplication(processIdentifier: pid) {
                    _ = app.terminate()
                } else {
                    // Not an NSRunningApplication, use SIGTERM
                    kill(pid, SIGTERM)
                }
            }
        }
    }
    
    /// Force terminate an app group (all processes)
    func forceTerminateApp(_ app: AppGroup) -> Bool {
        var allSucceeded = true
        
        // Force terminate main process first
        if let mainApp = NSRunningApplication(processIdentifier: app.id) {
            if !mainApp.forceTerminate() {
                allSucceeded = false
            }
        } else {
            // Use SIGKILL directly
            if kill(app.id, SIGKILL) != 0 {
                allSucceeded = false
            }
        }
        
        // Force terminate all child processes
        for pid in app.allPids where pid != app.id {
            if let childApp = NSRunningApplication(processIdentifier: pid) {
                if !childApp.forceTerminate() {
                    allSucceeded = false
                }
            } else {
                // Use SIGKILL for non-app processes
                if kill(pid, SIGKILL) != 0 {
                    allSucceeded = false
                }
            }
        }
        
        return allSucceeded
    }
    
    // MARK: - Private - Process Name
    
    /// Get process name for a given PID
    private func getProcessName(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        
        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            return (path as NSString).lastPathComponent
        }
        
        // Fallback: try to get name from kinfo_proc
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        
        if sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 && size > 0 {
            let name = withUnsafePointer(to: &info.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }
            if !name.isEmpty {
                return name
            }
        }
        
        return nil
    }
}

// Import for proc_pidinfo and other system calls
import Darwin
