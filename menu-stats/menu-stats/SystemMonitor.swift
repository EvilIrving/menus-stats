//
//  SystemMonitor.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import Foundation
import Combine

/// Main class for monitoring system statistics
@MainActor
final class SystemMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var cpuUsage: Double = 0
    @Published var cpuUserUsage: Double = 0
    @Published var cpuSystemUsage: Double = 0
    @Published var coreUsages: [Double] = []
    
    @Published var gpuUsage: Double? = nil
    
    @Published var memoryUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    
    @Published var diskUsed: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var diskAvailable: UInt64 = 0
    
    @Published var networkUpload: Double = 0  // bytes per second
    @Published var networkDownload: Double = 0  // bytes per second
    
    @Published var cpuTemperature: Double? = nil
    @Published var fanSpeed: Int? = nil
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var cpuInfo = CPUInfo()
    private var networkInfo = NetworkInfo()
    
    // MARK: - Singleton
    
    static let shared = SystemMonitor()
    
    private init() {}
    
    // MARK: - Public Methods
    
    func startMonitoring(interval: TimeInterval = 2.0) {
        stopMonitoring()
        
        // Initial update
        Task {
            await updateAllStats()
        }
        
        // Periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateAllStats()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Private Methods
    
    private func updateAllStats() async {
        updateCPU()
        updateMemory()
        updateDisk()
        updateNetwork()
        updateGPU()
        updateTemperatureAndFan()
    }
    
    private func updateCPU() {
        let usage = cpuInfo.getCPUUsage()
        cpuUsage = usage.total
        cpuUserUsage = usage.user
        cpuSystemUsage = usage.system
        coreUsages = cpuInfo.getPerCoreUsage()
    }
    
    private func updateMemory() {
        let info = MemoryInfo.getMemoryInfo()
        memoryTotal = info.total
        memoryUsed = info.used
        memoryUsage = info.usagePercent
    }
    
    private func updateDisk() {
        let info = DiskInfo.getDiskInfo()
        diskTotal = info.total
        diskUsed = info.used
        diskAvailable = info.available
    }
    
    private func updateNetwork() {
        let stats = networkInfo.getNetworkStats()
        networkUpload = stats.uploadSpeed
        networkDownload = stats.downloadSpeed
    }
    
    private func updateGPU() {
        gpuUsage = GPUInfo.getGPUUsage()
    }
    
    private func updateTemperatureAndFan() {
        cpuTemperature = SMCInfo.getCPUTemperature()
        fanSpeed = SMCInfo.getFanSpeed()
    }
}

// MARK: - CPU Info

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

// MARK: - Memory Info

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

// MARK: - Disk Info

enum DiskInfo {
    
    struct Info {
        let total: UInt64
        let used: UInt64
        let available: UInt64
    }
    
    static func getDiskInfo() -> Info {
        let fileURL = URL(fileURLWithPath: "/")
        
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let used = total > available ? total - available : 0
            
            return Info(total: total, used: used, available: available)
        } catch {
            return Info(total: 0, used: 0, available: 0)
        }
    }
}

// MARK: - Network Info

final class NetworkInfo: @unchecked Sendable {
    
    private var previousBytes: (sent: UInt64, received: UInt64) = (0, 0)
    private var previousTime: Date = Date()
    
    struct Stats {
        let uploadSpeed: Double
        let downloadSpeed: Double
    }
    
    func getNetworkStats() -> Stats {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return Stats(uploadSpeed: 0, downloadSpeed: 0)
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0
        
        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            
            if isUp && !isLoopback {
                if ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = ptr.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalSent += UInt64(networkData.ifi_obytes)
                        totalReceived += UInt64(networkData.ifi_ibytes)
                    }
                }
            }
            
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)
        
        var uploadSpeed: Double = 0
        var downloadSpeed: Double = 0
        
        if elapsed > 0 && previousBytes.sent > 0 {
            uploadSpeed = Double(totalSent - previousBytes.sent) / elapsed
            downloadSpeed = Double(totalReceived - previousBytes.received) / elapsed
        }
        
        previousBytes = (totalSent, totalReceived)
        previousTime = now
        
        return Stats(uploadSpeed: max(0, uploadSpeed), downloadSpeed: max(0, downloadSpeed))
    }
}

// MARK: - GPU Info

import IOKit

enum GPUInfo {
    
    static func getGPUUsage() -> Double? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        
        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry) }
            
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                
                // Try different keys for GPU utilization
                if let utilization = perfStats["Device Utilization %"] as? Double {
                    return utilization
                }
                if let utilization = perfStats["GPU Activity(%)"] as? Double {
                    return utilization
                }
                if let utilization = perfStats["GPU Core Utilization"] as? Double {
                    return utilization
                }
            }
            
            entry = IOIteratorNext(iterator)
        }
        
        return nil
    }
}

// MARK: - SMC Info (Temperature & Fan)

import IOKit.ps

/// SMC access for temperature and fan speed
/// Based on AppleSMC.kext interface - struct size must be exactly 80 bytes
enum SMCInfo {
    
    // SMC connection
    private static var conn: io_connect_t = 0
    
    // MARK: - SMC Selectors
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCGetKeyInfo: UInt8 = 9
    
    // MARK: - Public API
    
    /// Debug function to test SMC access
    static func debugSMC() {
        var log = "[SMC Debug] Testing SMC access...\n"
        log += "[SMC Debug] SMCParamStruct size: \(MemoryLayout<SMCParamStruct>.size) bytes\n"
        log += "[SMC Debug] SMCParamStruct stride: \(MemoryLayout<SMCParamStruct>.stride) bytes\n"
        
        guard open() else {
            log += "[SMC Debug] Failed to open SMC connection\n"
            writeDebugLog(log)
            return
        }
        defer { close() }
        log += "[SMC Debug] SMC connection opened successfully\n"
        
        // Test reading some keys
        let testKeys = ["Tc0a", "Tc0b", "Tp01", "Tp09", "TC0P", "FNum", "F0Ac"]
        for key in testKeys {
            if let data = readKey(key) {
                let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                log += "[SMC Debug] Key '\(key)': \(hexStr)\n"
            } else {
                log += "[SMC Debug] Key '\(key)': not found\n"
            }
        }
        
        writeDebugLog(log)
    }
    
    private static func writeDebugLog(_ content: String) {
        let path = "/tmp/menu-stats-smc-debug.log"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    static func getCPUTemperature() -> Double? {
        guard open() else {
            return nil
        }
        defer { close() }
        
        // Apple Silicon M-series temperature keys (M1/M2/M3/M4)
        // Based on https://github.com/narugit/smctemp
        let applesSiliconKeys = [
            // CPU temperature sensors (from smctemp)
            "Tc0a", "Tc0b", "Tc0x", "Tc0z",  // CPU cluster temps
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T",
            "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp0n", "Tp0r",  // P-cores
            "Tp1h", "Tp1t", "Tp1p", "Tp1l",  // More P-cores (Pro/Max/Ultra)
        ]
        
        // Intel Mac temperature keys
        let intelKeys = [
            "TC0P", "TC0C", "TC0D", "TC0E", "TC0F",
        ]
        
        // Try Apple Silicon keys first (since user has M2 Pro / M4)
        for key in applesSiliconKeys {
            if let temp = readTemperature(key: key), temp > 0 && temp < 150 {
                return temp
            }
        }
        
        // Fallback to Intel keys
        for key in intelKeys {
            if let temp = readTemperature(key: key), temp > 0 && temp < 150 {
                return temp
            }
        }
        
        return nil
    }
    
    static func getFanSpeed() -> Int? {
        guard open() else { return nil }
        defer { close() }
        
        // Try to read fan count first
        if let countData = readKey("FNum"), !countData.isEmpty {
            let count = Int(countData[0])
            if count > 0 {
                // Read speed from first fan
                if let speed = readFanSpeed(index: 0), speed > 0 {
                    return speed
                }
            }
        }
        
        // Apple Silicon or fallback: try direct fan key
        if let speed = readFanSpeed(index: 0), speed > 0 {
            return speed
        }
        
        return nil
    }
    
    // MARK: - SMC Connection
    
    private static func open() -> Bool {
        if conn != 0 { return true }
        
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        
        guard service != 0 else {
            return false
        }
        
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        
        guard result == kIOReturnSuccess else {
            conn = 0
            return false
        }
        
        return true
    }
    
    private static func close() {
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }
    
    // MARK: - Read Helpers
    
    private static func readTemperature(key: String) -> Double? {
        guard let data = readKey(key), data.count >= 2 else { return nil }
        
        // SP78 format: signed fixed-point 7.8 (7 integer bits, 8 fractional bits)
        let value = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
        return Double(value) / 256.0
    }
    
    private static func readFanSpeed(index: Int) -> Int? {
        let key = String(format: "F%dAc", index)
        guard let data = readKey(key), data.count >= 2 else { return nil }
        
        // M4 and newer chips use flt (Float) format: 4 bytes little-endian
        if data.count >= 4 {
            // Try float format first (used by M4)
            let floatValue = data.withUnsafeBytes { ptr -> Float in
                ptr.load(as: Float.self)
            }
            if floatValue > 0 && floatValue < 10000 {
                return Int(floatValue)
            }
        }
        
        // Fallback to FPE2 format: unsigned fixed-point with 2 fractional bits
        let value = UInt16(data[0]) << 8 | UInt16(data[1])
        let fpe2Value = Int(value) >> 2
        if fpe2Value > 0 && fpe2Value < 10000 {
            return fpe2Value
        }
        
        return nil
    }
    
    // MARK: - Core SMC Read
    
    private static func readKey(_ key: String) -> [UInt8]? {
        guard key.count == 4 else { return nil }
        
        let keyCode = fourCharCode(key)
        
        // Step 1: Get key info to know the data size
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()
        
        inputStruct.key = keyCode
        inputStruct.data8 = kSMCGetKeyInfo
        
        var outputSize = MemoryLayout<SMCParamStruct>.size
        
        var result = IOConnectCallStructMethod(
            conn,
            2,  // kSMCHandleYPCEvent
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )
        
        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            return nil
        }
        
        let dataSize = Int(outputStruct.keyInfo.dataSize)
        guard dataSize > 0 && dataSize <= 32 else { return nil }
        
        // Step 2: Read the actual data
        inputStruct = SMCParamStruct()
        inputStruct.key = keyCode
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = kSMCReadKey
        
        outputStruct = SMCParamStruct()
        outputSize = MemoryLayout<SMCParamStruct>.size
        
        result = IOConnectCallStructMethod(
            conn,
            2,  // kSMCHandleYPCEvent
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )
        
        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            return nil
        }
        
        // Extract bytes from output
        var bytes = [UInt8]()
        withUnsafeBytes(of: outputStruct.bytes) { ptr in
            for i in 0..<dataSize {
                bytes.append(ptr[i])
            }
        }
        
        return bytes
    }
    
    private static func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
    
    // MARK: - SMC Structures (must match AppleSMC.kext exactly)
    // Based on smctemp.h from https://github.com/narugit/smctemp
    
    private struct SMCVersion {
        var major: CChar = 0
        var minor: CChar = 0
        var build: CChar = 0
        var reserved: CChar = 0
        var release: UInt16 = 0
    }
    
    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0  // Required for correct struct size (80 bytes)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
}

// MARK: - Formatting Helpers

enum ByteFormatter {
    
    static func format(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    /// 磁盘空间格式化，向上取整不显示小数
    static func formatDisk(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            return "\(Int(ceil(gb))) GB"
        } else {
            let mb = Double(bytes) / 1_000_000
            return "\(Int(ceil(mb))) MB"
        }
    }
    
    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}
