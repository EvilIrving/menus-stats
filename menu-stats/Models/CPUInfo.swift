//
//  CPUInfo.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import Foundation

final class CPUInfo: @unchecked Sendable {

    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)
    private var previousCoreTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []

    struct CPUUsage {
        let total: Double
        let user: Double
        let system: Double
    }

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
}
