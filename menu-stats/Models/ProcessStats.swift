//
//  ProcessStats.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import Foundation

// MARK: - Top Process Info

/// Represents a process with CPU/memory usage
struct TopProcess: Identifiable {
    let id = UUID()
    let name: String
    let cpuPercent: Double
    let memPercent: Double
    
    /// Format CPU percentage for display
    var cpuDisplayString: String {
        String(format: "%.1f%%", cpuPercent)
    }
}

// MARK: - Process Stats

/// Collects top CPU-consuming processes using ps command
enum ProcessStats {
    
    /// Get top N processes sorted by CPU usage
    /// Uses: ps -Aceo pcpu,pmem,comm -r
    static func getTopCPUProcesses(count: Int = 5) async -> [TopProcess] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/ps")
                // -A: all processes
                // -c: show only command name (not full path)
                // -e: show environment (needed for some systems)
                // -o: output format
                // -r: sort by CPU (descending)
                task.arguments = ["-Aceo", "pcpu,pmem,comm", "-r"]
                
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    let processes = parseProcessOutput(output, maxCount: count)
                    continuation.resume(returning: processes)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Parse ps command output
    /// Format: %CPU %MEM COMMAND
    private static func parseProcessOutput(_ output: String, maxCount: Int) -> [TopProcess] {
        var processes: [TopProcess] = []
        let lines = output.components(separatedBy: "\n")
        
        var lineIndex = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Skip header line (contains "CPU" or "%")
            if lineIndex == 0 {
                lineIndex += 1
                if trimmed.lowercased().contains("cpu") || trimmed.contains("%") {
                    continue
                }
            }
            
            // Parse data line
            let fields = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard fields.count >= 3 else { continue }
            
            guard let cpuPercent = Double(fields[0]),
                  let memPercent = Double(fields[1]) else { continue }
            
            // Command name is the last field (may contain spaces, take all remaining)
            var name = fields[2..<fields.count].joined(separator: " ")
            
            // Strip path if present (take last component after /)
            if let lastSlash = name.lastIndex(of: "/") {
                name = String(name[name.index(after: lastSlash)...])
            }
            
            // Skip very low CPU processes
            if cpuPercent < 0.1 { continue }
            
            processes.append(TopProcess(
                name: name,
                cpuPercent: cpuPercent,
                memPercent: memPercent
            ))
            
            // Limit results
            if processes.count >= maxCount {
                break
            }
            
            lineIndex += 1
        }
        
        return processes
    }
}
