//
//  MemoryInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

/// Memory pressure level from kern.memorystatus_vm_pressure_level
enum MemoryPressureLevel: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    var displayName: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "警告"
        case .critical: return "危急"
        }
    }
}

enum MemoryInfo {

    struct Info {
        let total: UInt64
        let used: UInt64
        let usagePercent: Double
    }

    /// Detailed memory statistics from vm_statistics64
    struct DetailedInfo {
        let total: UInt64
        let used: UInt64
        let usagePercent: Double

        // Detailed breakdown
        let active: UInt64       // 活跃内存
        let inactive: UInt64     // 非活跃内存
        let wired: UInt64        // 联动内存 (不可换出)
        let compressed: UInt64   // 压缩内存
        let speculative: UInt64  // 推测内存
        let purgeable: UInt64    // 可清除内存
        let external: UInt64     // 外部内存 (文件缓存)

        // Memory pressure
        let pressureLevel: MemoryPressureLevel

        // Swap usage
        let swapTotal: UInt64
        let swapUsed: UInt64
        let swapFree: UInt64
    }

    static func getMemoryInfo() -> Info {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return Info(total: 0, used: 0, usagePercent: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory

        // Used = Active + Wired + Compressed
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        let usagePercent = Double(used) / Double(total) * 100

        return Info(total: total, used: used, usagePercent: usagePercent)
    }

    /// Get detailed memory statistics including all components and pressure level
    static func getDetailedMemoryInfo() -> DetailedInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory

        guard result == KERN_SUCCESS else {
            return DetailedInfo(
                total: total, used: 0, usagePercent: 0,
                active: 0, inactive: 0, wired: 0, compressed: 0,
                speculative: 0, purgeable: 0, external: 0,
                pressureLevel: .normal,
                swapTotal: 0, swapUsed: 0, swapFree: 0
            )
        }

        // Calculate all memory components
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize

        // Used memory calculation
        let used = active + wired + compressed
        let usagePercent = Double(used) / Double(total) * 100

        // Get memory pressure level
        let pressureLevel = getMemoryPressureLevel()

        // Get swap usage
        let swap = getSwapUsage()

        return DetailedInfo(
            total: total, used: used, usagePercent: usagePercent,
            active: active, inactive: inactive, wired: wired, compressed: compressed,
            speculative: speculative, purgeable: purgeable, external: external,
            pressureLevel: pressureLevel,
            swapTotal: swap.total, swapUsed: swap.used, swapFree: swap.free
        )
    }

    /// Get memory pressure level using sysctl
    static func getMemoryPressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size

        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)

        guard result == 0 else {
            return .normal
        }

        return MemoryPressureLevel(rawValue: Int(level)) ?? .normal
    }

    /// Get swap/virtual memory usage using sysctl
    static func getSwapUsage() -> (total: UInt64, used: UInt64, free: UInt64) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)

        guard result == 0 else {
            return (0, 0, 0)
        }

        return (
            total: swapUsage.xsu_total,
            used: swapUsage.xsu_used,
            free: swapUsage.xsu_avail
        )
    }
}
