//
//  ProcessService.swift
//  Light Stats
//
//  进程相关服务：top 命令解析、进程信息查询、进程控制
//

import Foundation
import AppKit

// MARK: - Responsibility Framework

/// Import the responsibility framework for process grouping
/// responsibility_get_pid_responsible_for_pid returns the PID of the "responsible" process
@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

// MARK: - Process Service

/// 进程服务：提供进程信息查询、top 命令解析、进程控制功能
protocol ProcessServiceProtocol {
    func getBundleInfo(for pid: pid_t) -> ProcessBundleInfo
    func getProcessName(for pid: pid_t) -> String?
    func getTopMemoryProcesses(count: Int) async -> [TopProcessInfo]
    func triggerMemoryCleanup() async
    func terminateApp(_ app: AppGroup) -> Bool
    func forceTerminateApp(_ app: AppGroup) -> Bool
    func terminateAppAsync(_ app: AppGroup) async -> Bool
    func isProcessAlive(_ pid: pid_t) -> Bool
}

final class ProcessService: ProcessServiceProtocol {
    
    static let shared = ProcessService()
    
    /// Bundle ID 缓存（避免重复读取 Info.plist）
    private var bundleIdCache: [String: String?] = [:]
    
    private init() {}
    
    // MARK: - Bundle Info Extraction
    
    /// 从进程 PID 获取 Bundle 信息
    /// - Parameter pid: 进程 PID
    /// - Returns: ProcessBundleInfo 包含可执行文件路径、Bundle 路径和 Bundle ID
    func getBundleInfo(for pid: pid_t) -> ProcessBundleInfo {
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
        
        // Step 4: 从缓存或 bundle 读取 Bundle ID
        let bundleId: String?
        if let cached = bundleIdCache[bundlePath] {
            bundleId = cached
        } else {
            let bundle = Bundle(path: bundlePath)
            bundleId = bundle?.bundleIdentifier
            bundleIdCache[bundlePath] = bundleId
        }
        
        return ProcessBundleInfo(execPath: execPath, bundlePath: bundlePath, bundleId: bundleId)
    }
    
    /// Get process name for a given PID
    func getProcessName(for pid: pid_t) -> String? {
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
    
    // MARK: - Top Command Execution
    
    /// Get top N memory-consuming processes using top command
    /// Command: /usr/bin/top -l 1 -o mem -n N -stats pid,command,mem
    func getTopMemoryProcesses(count: Int) async -> [TopProcessInfo] {
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
    
    // MARK: - Process Control
    
    /// Check if a process is still alive
    func isProcessAlive(_ pid: pid_t) -> Bool {
        return kill(pid, 0) == 0
    }
    
    /// Kill a process using system kill command (more reliable than NSRunningApplication)
    /// - Parameters:
    ///   - pid: Process ID to kill
    ///   - force: If true, sends SIGKILL (-9), otherwise SIGTERM (-15)
    /// - Returns: True if kill command executed successfully
    private func killProcessWithCommand(pid: pid_t, force: Bool = false) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [force ? "-9" : "-15", String(pid)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Gracefully terminate a process with fallback to force kill
    /// Strategy: SIGTERM → wait 500ms → SIGKILL (borrowed from port-killer)
    /// - Parameter pid: Process ID to terminate
    /// - Returns: True if process was terminated
    private func killProcessGracefully(pid: pid_t) async -> Bool {
        guard isProcessAlive(pid) else {
            return true
        }
        
        let graceful = killProcessWithCommand(pid: pid, force: false)
        if graceful {
            try? await Task.sleep(for: .milliseconds(500))
        }
        
        guard isProcessAlive(pid) else {
            return true
        }
        
        return killProcessWithCommand(pid: pid, force: true)
    }
    
    /// Async version of terminate that provides reliable process termination
    /// Uses two-stage strategy: graceful first, then force kill
    func terminateAppAsync(_ app: AppGroup) async -> Bool {
        if let mainApp = NSRunningApplication(processIdentifier: app.id) {
            let terminated = mainApp.terminate()
            if terminated {
                try? await Task.sleep(for: .milliseconds(300))
                
                if !isProcessAlive(app.id) {
                    await terminateSurvivingChildrenAsync(app.allPids)
                    return true
                }
            }
        }
        
        var success = await killProcessGracefully(pid: app.id)
        
        for pid in app.allPids where pid != app.id {
            if isProcessAlive(pid) {
                let childSuccess = await killProcessGracefully(pid: pid)
                success = success && childSuccess
            }
        }
        
        return success
    }
    
    /// Async version of child process cleanup
    private func terminateSurvivingChildrenAsync(_ pids: [pid_t]) async {
        for pid in pids {
            if isProcessAlive(pid) {
                _ = await killProcessGracefully(pid: pid)
            }
        }
    }
    
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
}

// Import for proc_pidinfo and other system calls
import Darwin
