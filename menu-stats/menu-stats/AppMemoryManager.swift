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

// MARK: - Top Process Info

/// Process info parsed from top command output
struct TopProcessInfo {
    let pid: pid_t
    let command: String
    let memoryBytes: UInt64
}



// MARK: - App Group (Public)

/// Represents a merged application group (main process + child processes)
struct AppGroup: Identifiable {
    let id: pid_t  // Main process PID
    let name: String
    let icon: NSImage
    let totalMemoryBytes: UInt64
    let processCount: Int
    let allPids: [pid_t]  // All process PIDs (for termination)
    let bundleIdentifier: String?
    
    /// Display name: shows process count if multiple processes
    var displayName: String {
        processCount > 1 ? "\(name) (\(processCount))" : name
    }
    
    var memoryFormatted: String {
        ByteFormatter.format(totalMemoryBytes)
    }
}

// MARK: - Legacy Alias (for compatibility)

typealias RunningApp = AppGroup

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
        let topProcesses = await getTopMemoryProcesses(count: 50)
        
        // Step 2: Get running GUI apps for icons and bundle identifiers
        let workspace = NSWorkspace.shared
        let guiApps = workspace.runningApplications
        
        // Build lookup maps for GUI apps
        var guiAppByPid: [pid_t: NSRunningApplication] = [:]
        knownAppBundleIds.removeAll()
        
        for app in guiApps {
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            guiAppByPid[app.processIdentifier] = app
            if let bundleId = app.bundleIdentifier {
                knownAppBundleIds.insert(bundleId)
            }
        }
        
        // Step 3: Group processes by responsible PID
        var groupedByResponsible: [pid_t: [TopProcessInfo]] = [:]
        
        for process in topProcesses {
            let responsiblePid = responsibility_get_pid_responsible_for_pid(process.pid)
            // Use the responsible PID, fallback to self if 0
            let groupPid = responsiblePid > 0 ? responsiblePid : process.pid
            groupedByResponsible[groupPid, default: []].append(process)
        }
        
        // Step 4: Build app groups
        var appGroups: [AppGroup] = []
        
        for (responsiblePid, processes) in groupedByResponsible {
            // Calculate total memory for the group
            let totalMemory = processes.reduce(0) { $0 + $1.memoryBytes }
            let allPids = processes.map { $0.pid }
            
            // Try to get app info from GUI apps
            let guiApp = guiAppByPid[responsiblePid]
            let name: String
            let icon: NSImage
            let bundleId: String?
            
            if let app = guiApp {
                name = app.localizedName ?? processes.first?.command ?? "Unknown"
                icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
                bundleId = app.bundleIdentifier
            } else {
                // Not a GUI app, use command name from top
                name = getProcessName(for: responsiblePid) ?? processes.first?.command ?? "Unknown"
                icon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
                bundleId = nil
            }
            
            let group = AppGroup(
                id: responsiblePid,
                name: name,
                icon: icon,
                totalMemoryBytes: totalMemory,
                processCount: processes.count,
                allPids: allPids,
                bundleIdentifier: bundleId
            )
            appGroups.append(group)
        }
        
        // Step 5: Sort by total memory usage (descending)
        let sortedGroups = appGroups.sorted { $0.totalMemoryBytes > $1.totalMemoryBytes }
        
        runningApps = sortedGroups
        appCount = sortedGroups.count
        
        // Update detailed memory info
        let detailedInfo = MemoryInfo.getDetailedMemoryInfo()
        detailedMemory = detailedInfo
        totalMemoryUsed = detailedInfo.used
        memoryPressure = detailedInfo.pressureLevel
    }
    
    // MARK: - Hybrid Process Grouping
    
    /// Determine group key using two strategies:
    /// 1. responsibility_get_pid_responsible_for_pid - for XPC services
    /// 2. Path analysis - check if process is inside .app bundle
    private func determineGroupKey(
        for process: TopProcessInfo,
        guiAppByPid: [pid_t: NSRunningApplication],
        guiAppByName: [String: NSRunningApplication]
    ) -> (key: String, app: NSRunningApplication?) {
        
        // Strategy 1: Use responsibility framework
        let responsiblePid = responsibility_get_pid_responsible_for_pid(process.pid)
        
        if responsiblePid > 0 && responsiblePid != process.pid {
            // Found a different responsible process
            if let app = guiAppByPid[responsiblePid] {
                let appName = app.localizedName ?? "Unknown"
                return (key: appName, app: app)
            }
            // Responsible process is not a GUI app, use its name
            let name = getProcessName(for: responsiblePid) ?? "pid:\(responsiblePid)"
            return (key: name, app: nil)
        }
        
        // Strategy 2: Path analysis - check if inside .app bundle
        if let appName = getAppNameFromPath(for: process.pid) {
            if let app = guiAppByName[appName] {
                return (key: appName, app: app)
            }
            // Not a running GUI app, but still group by app name
            return (key: appName, app: nil)
        }
        
        // Fallback: check if this PID is a GUI app itself
        if let app = guiAppByPid[process.pid] {
            let appName = app.localizedName ?? "Unknown"
            return (key: appName, app: app)
        }
        
        // Final fallback: use process name
        let name = process.command.isEmpty ? "pid:\(process.pid)" : process.command
        return (key: name, app: nil)
    }
    
    /// Extract app name from process path if it's inside an .app bundle
    /// Example: /Applications/vivo办公套件.app/Contents/MacOS/vivo_remote_watch -> "vivo办公套件"
    private func getAppNameFromPath(for pid: pid_t) -> String? {
        guard let path = getProcessPath(for: pid) else { return nil }
        
        // Look for .app in the path
        let components = path.components(separatedBy: "/")
        for component in components {
            if component.hasSuffix(".app") {
                return String(component.dropLast(4))  // Remove ".app"
            }
        }
        
        return nil
    }
    
    /// Get full executable path for a process
    private func getProcessPath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        
        if pathLength > 0 {
            return String(cString: pathBuffer)
        }
        return nil
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
