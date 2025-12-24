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

enum MemoryInfo {
    
    struct Info {
        let total: UInt64
        let used: UInt64
        let usagePercent: Double
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

enum SMCInfo {
    
    // SMC connection
    private static var conn: io_connect_t = 0
    
    // MARK: - Public API
    
    static func getCPUTemperature() -> Double? {
        guard open() else {
            print("[SMC] Failed to open SMC connection")
            return nil
        }
        defer { close() }
        
        // Try multiple temperature keys for different Mac models
        let tempKeys = [
            "TC0P",  // CPU Proximity (Intel)
            "TC0C",  // CPU Core (Intel)
            "Tp09",  // CPU efficiency core 1 (Apple Silicon)
            "Tp0T",  // CPU performance core 1 (Apple Silicon)
            "TC0p",  // Alternative
            "TC0c",  // Alternative
        ]
        
        for key in tempKeys {
            if let temp = readSMCTemperature(key: key), temp > 0 && temp < 150 {
                print("[SMC] Got temperature \(temp) from key \(key)")
                return temp
            }
        }
        
        print("[SMC] No valid temperature found")
        return nil
    }
    
    static func getFanSpeed() -> Int? {
        guard open() else { return nil }
        defer { close() }
        
        // Try to read fan count
        guard let count = readSMCInt(key: "FNum"), count > 0 else {
            // Apple Silicon Macs may not have traditional fan reporting
            // Try direct fan key
            if let speed = readSMCFanSpeed(key: "F0Ac"), speed > 0 {
                return speed
            }
            return nil
        }
        
        // Read max speed from all fans
        var maxSpeed = 0
        for i in 0..<count {
            let key = String(format: "F%dAc", i)
            if let speed = readSMCFanSpeed(key: key), speed > maxSpeed {
                maxSpeed = speed
            }
        }
        
        return maxSpeed > 0 ? maxSpeed : nil
    }
    
    // MARK: - SMC Connection
    
    private static func open() -> Bool {
        if conn != 0 { return true }
        
        var service: io_service_t = 0
        var result: kern_return_t = 0
        
        service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        
        if service == 0 {
            print("[SMC] AppleSMC service not found")
            return false
        }
        
        result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        
        if result != kIOReturnSuccess {
            print("[SMC] Failed to open service: \(result)")
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
    
    // MARK: - SMC Read
    
    private static func readSMCTemperature(key: String) -> Double? {
        guard let data = readSMCBytes(key: key, size: 2) else { return nil }
        
        // SP78 format: signed fixed-point 7.8 (7 integer bits, 8 fractional bits)
        let value = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
        return Double(value) / 256.0
    }
    
    private static func readSMCFanSpeed(key: String) -> Int? {
        guard let data = readSMCBytes(key: key, size: 2) else { return nil }
        
        // FPE2 format: unsigned fixed-point with 2 fractional bits (divide by 4)
        let value = UInt16(data[0]) << 8 | UInt16(data[1])
        return Int(value) >> 2
    }
    
    private static func readSMCInt(key: String) -> Int? {
        guard let data = readSMCBytes(key: key, size: 1) else { return nil }
        return Int(data[0])
    }
    
    private static func readSMCBytes(key: String, size: Int) -> [UInt8]? {
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()
        
        // Convert 4-char key to UInt32
        guard key.count == 4 else { return nil }
        inputStruct.key = fourCharCode(key)
        inputStruct.keyInfo.dataSize = UInt32(size)
        inputStruct.data8 = 5  // SMC_CMD_READ_BYTES
        
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        
        let result = IOConnectCallStructMethod(
            conn,
            2,  // kSMCUserClientOpen/kSMCReadKey
            &inputStruct,
            inputSize,
            &outputStruct,
            &outputSize
        )
        
        guard result == kIOReturnSuccess else {
            return nil
        }
        
        // Extract bytes from output
        var bytes = [UInt8]()
        withUnsafeBytes(of: outputStruct.bytes) { ptr in
            for i in 0..<min(size, 32) {
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
    
    // MARK: - SMC Structures
    
    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)
        var plimitData: (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0, 0, 0, 0, 0)
        var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
        var padding: UInt16 = 0
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
