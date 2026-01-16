//
//  CPUInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

// MARK: - Core Topology (Apple Silicon P/E cores)

/// Represents P-core and E-core counts on Apple Silicon
struct CoreTopology {
    let performanceCores: Int  // P-cores
    let efficiencyCores: Int   // E-cores
    let totalCores: Int
    
    /// Display label like "4P+6E"
    var displayLabel: String {
        if performanceCores > 0 && efficiencyCores > 0 {
            return "\(performanceCores)P+\(efficiencyCores)E"
        } else if performanceCores > 0 {
            return "\(performanceCores)P"
        } else {
            return "\(totalCores)\("core.suffix".localized)"
        }
    }
    
    static let unknown = CoreTopology(performanceCores: 0, efficiencyCores: 0, totalCores: 0)
}

// MARK: - Load Average

/// System load average (1, 5, 15 minutes)
struct LoadAverage {
    let load1: Double
    let load5: Double
    let load15: Double
    
    /// Display string like "3.2 / 2.8 / 2.5"
    var displayString: String {
        String(format: "%.1f / %.1f / %.1f", load1, load5, load15)
    }
    
    static let zero = LoadAverage(load1: 0, load5: 0, load15: 0)
}

// MARK: - CPU Info

final class CPUInfo: @unchecked Sendable {

    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)
    private var previousCoreTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
    private var isWarmedUp = false
    
    // Cache for core topology (rarely changes)
    private var cachedTopology: CoreTopology?
    private var topologyCacheTime: Date?
    private let topologyCacheTTL: TimeInterval = 600  // 10 minutes

    struct CPUUsage {
        let total: Double
        let user: Double
        let system: Double
    }
    
    // MARK: - Warmup
    
    /// Perform warmup sampling to avoid initial data distortion
    func warmup() {
        guard !isWarmedUp else { return }
        
        // First sample to initialize previous ticks
        _ = getCPUUsage()
        _ = getPerCoreUsage()
        
        isWarmedUp = true
    }

    // MARK: - CPU Usage
    
    func getCPUUsage() -> CPUUsage {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return CPUUsage(total: 0, user: 0, system: 0)
        }

        let user = UInt64(cpuLoad.cpu_ticks.0)
        let system = UInt64(cpuLoad.cpu_ticks.1)
        let idle = UInt64(cpuLoad.cpu_ticks.2)
        let nice = UInt64(cpuLoad.cpu_ticks.3)

        let userDiff = user - previousTicks.user
        let systemDiff = system - previousTicks.system
        let idleDiff = idle - previousTicks.idle
        let niceDiff = nice - previousTicks.nice

        previousTicks = (user, system, idle, nice)

        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        guard totalTicks > 0 else {
            return CPUUsage(total: 0, user: 0, system: 0)
        }

        let userPercent = Double(userDiff + niceDiff) / Double(totalTicks) * 100
        let systemPercent = Double(systemDiff) / Double(totalTicks) * 100
        let totalPercent = userPercent + systemPercent

        return CPUUsage(total: totalPercent, user: userPercent, system: systemPercent)
    }

    // MARK: - Per-Core Usage
    
    func getPerCoreUsage() -> [Double] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return []
        }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.size))
        }

        // Initialize previous ticks if needed
        if previousCoreTicks.isEmpty {
            previousCoreTicks = Array(repeating: (0, 0, 0, 0), count: Int(numCPUs))
        }

        var usages: [Double] = []

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[offset + Int(CPU_STATE_USER)])
            let system = UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[offset + Int(CPU_STATE_NICE)])

            let prev = previousCoreTicks[i]
            let userDiff = user - prev.user
            let systemDiff = system - prev.system
            let idleDiff = idle - prev.idle
            let niceDiff = nice - prev.nice

            previousCoreTicks[i] = (user, system, idle, nice)

            let total = userDiff + systemDiff + idleDiff + niceDiff
            let usage = total > 0 ? Double(userDiff + systemDiff + niceDiff) / Double(total) * 100 : 0
            usages.append(usage)
        }

        return usages
    }
    
    // MARK: - Core Topology (Apple Silicon)
    
    /// Get P-core and E-core counts using sysctl
    func getCoreTopology() -> CoreTopology {
        // Check cache
        if let cached = cachedTopology,
           let cacheTime = topologyCacheTime,
           Date().timeIntervalSince(cacheTime) < topologyCacheTTL {
            return cached
        }
        
        var pCores = 0
        var eCores = 0
        
        // Try to get perflevel0 (usually Performance cores on Apple Silicon)
        var level0Count: Int32 = 0
        var level0Size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &level0Count, &level0Size, nil, 0) == 0 {
            // Get the name to determine if it's P or E
            var nameBuffer = [CChar](repeating: 0, count: 64)
            var nameSize = nameBuffer.count
            if sysctlbyname("hw.perflevel0.name", &nameBuffer, &nameSize, nil, 0) == 0 {
                let name = String(cString: nameBuffer).lowercased()
                if name.contains("performance") {
                    pCores = Int(level0Count)
                } else if name.contains("efficiency") {
                    eCores = Int(level0Count)
                }
            }
        }
        
        // Try to get perflevel1 (usually Efficiency cores on Apple Silicon)
        var level1Count: Int32 = 0
        var level1Size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel1.logicalcpu", &level1Count, &level1Size, nil, 0) == 0 {
            var nameBuffer = [CChar](repeating: 0, count: 64)
            var nameSize = nameBuffer.count
            if sysctlbyname("hw.perflevel1.name", &nameBuffer, &nameSize, nil, 0) == 0 {
                let name = String(cString: nameBuffer).lowercased()
                if name.contains("performance") {
                    pCores = Int(level1Count)
                } else if name.contains("efficiency") {
                    eCores = Int(level1Count)
                }
            }
        }
        
        // Get total logical CPUs as fallback
        let totalCores = ProcessInfo.processInfo.processorCount
        
        let topology = CoreTopology(
            performanceCores: pCores,
            efficiencyCores: eCores,
            totalCores: totalCores
        )
        
        // Cache the result
        cachedTopology = topology
        topologyCacheTime = Date()
        
        return topology
    }
    
    // MARK: - Load Average
    
    /// Get system load average (1, 5, 15 minutes)
    static func getLoadAverage() -> LoadAverage {
        var loadavg = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loadavg, 3)
        
        guard count == 3 else {
            return .zero
        }
        
        return LoadAverage(
            load1: loadavg[0],
            load5: loadavg[1],
            load15: loadavg[2]
        )
    }
}
