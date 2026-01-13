//
//  SMCInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import IOKit

/// SMC access for temperature and fan speed
/// Based on AppleSMC.kext interface - struct size must be exactly 80 bytes
enum SMCInfo {

    // SMC connection
    private static var conn: io_connect_t = 0

    // Temperature cache for stability
    private static var cachedTemperature: Double? = nil
    private static let maxCacheAge: TimeInterval = 10  // 10 seconds

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
        let path = "/tmp/light-stats-smc-debug.log"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func getCPUTemperature() -> Double? {
        var debugLog = "[Temperature Debug] Starting...\n"

        guard open() else {
            debugLog += "[Temperature Debug] Failed to open SMC connection\n"
            writeDebugLog(debugLog)
            return cachedTemperature
        }
        defer { close() }

        debugLog += "[Temperature Debug] SMC connection opened\n"

        let cpuTempKeys = [
            // Apple Silicon SOC 温度
            "Te05",
            // Apple Silicon CPU Package
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0Y", "Tp0b", "Tp0e",
            // 风扇区域温度
            "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0E",
        ]

        var temperatures: [Double] = []
        for key in cpuTempKeys {
            let result = readTemperatureDebug(key: key)
            debugLog += result.log

            if let temp = result.temp {
                // 放宽范围先收集数据: 5-115°C
                if temp > 5 && temp < 115 {
                    temperatures.append(temp)
                    debugLog += "  -> ACCEPTED\n"
                } else {
                    debugLog += "  -> REJECTED (out of range 5-115)\n"
                }
            }
        }

        debugLog += "[Temperature Debug] Valid temperatures: \(temperatures)\n"
        debugLog += "[Temperature Debug] Count: \(temperatures.count)\n"

        guard !temperatures.isEmpty else {
            debugLog += "[Temperature Debug] No valid temperatures, returning cache: \(String(describing: cachedTemperature))\n"
            writeDebugLog(debugLog)
            return cachedTemperature
        }

        let avgTemp = temperatures.reduce(0, +) / Double(temperatures.count)
        debugLog += "[Temperature Debug] Average: \(avgTemp)\n"

        let smoothedTemp: Double
        if let cached = cachedTemperature {
            smoothedTemp = avgTemp * 0.7 + cached * 0.3
        } else {
            smoothedTemp = avgTemp
        }

        cachedTemperature = smoothedTemp
        debugLog += "[Temperature Debug] Final: \(smoothedTemp)\n"
        writeDebugLog(debugLog)

        return smoothedTemp
    }

    static func getFanSpeed() -> Int? {
        guard open() else { return nil }
        defer { close() }

        // Try to read fan count first
        var fanCount = 1
        if let countData = readKey("FNum"), !countData.isEmpty {
            fanCount = max(Int(countData[0]), 1)
        }

        // Read all fans and return the maximum speed
        var maxSpeed: Int? = nil

        for i in 0..<min(fanCount, 4) {
            if let speed = readFanSpeed(index: i) {
                if maxSpeed == nil || speed > maxSpeed! {
                    maxSpeed = speed
                }
            }
        }

        // If we found valid fan data (even if 0 RPM), return it
        if let speed = maxSpeed {
            return speed
        }

        // Fallback: try indices 0-3 directly
        for index in 0..<4 {
            if let speed = readFanSpeed(index: index) {
                return speed
            }
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

    /// 带调试信息的温度读取
    private static func readTemperatureDebug(key: String) -> (temp: Double?, log: String) {
        var log = "[Key: \(key)] "

        guard key.count == 4 else {
            log += "Invalid key length\n"
            return (nil, log)
        }

        let keyCode = fourCharCode(key)

        // Step 1: Get key info
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = keyCode
        inputStruct.data8 = kSMCGetKeyInfo

        var outputSize = MemoryLayout<SMCParamStruct>.size

        var result = IOConnectCallStructMethod(
            conn,
            2,
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            log += "GetKeyInfo failed (IOConnect error: \(result))\n"
            return (nil, log)
        }

        guard outputStruct.result == 0 else {
            log += "GetKeyInfo failed (SMC result: \(outputStruct.result))\n"
            return (nil, log)
        }

        let dataSize = Int(outputStruct.keyInfo.dataSize)
        let dataType = outputStruct.keyInfo.dataType

        // 转换 dataType 为可读字符串
        let typeStr = String(format: "%c%c%c%c",
                             (dataType >> 24) & 0xFF,
                             (dataType >> 16) & 0xFF,
                             (dataType >> 8) & 0xFF,
                             dataType & 0xFF)

        log += "type='\(typeStr)' size=\(dataSize) "

        guard dataSize > 0 && dataSize <= 32 else {
            log += "Invalid dataSize\n"
            return (nil, log)
        }

        // Step 2: Read actual data
        inputStruct = SMCParamStruct()
        inputStruct.key = keyCode
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = kSMCReadKey

        outputStruct = SMCParamStruct()
        outputSize = MemoryLayout<SMCParamStruct>.size

        result = IOConnectCallStructMethod(
            conn,
            2,
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            log += "ReadKey failed\n"
            return (nil, log)
        }

        // Extract bytes
        var bytes = [UInt8]()
        withUnsafeBytes(of: outputStruct.bytes) { ptr in
            for i in 0..<dataSize {
                bytes.append(ptr[i])
            }
        }

        let hexStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        log += "bytes=[\(hexStr)] "

        // Parse temperature
        if let temp = parseTemperatureValue(bytes: bytes, typeStr: typeStr) {
            if temp > 25 && temp < 115 {
                log += "  -> ACCEPTED\n"
                return (temp, log)
            } else {
                log += "  -> REJECTED (out of range 25-115)\n"
                return (nil, log)
            }
        }

        log += "parsed=nil\n"

        return (nil, log)
    }

    /// 根据类型字符串解析温度
    private static func parseTemperatureValue(bytes: [UInt8], typeStr: String) -> Double? {
        guard bytes.count >= 2 else { return nil }

        let trimmedType = typeStr.trimmingCharacters(in: .whitespaces)

        switch trimmedType {
        case "sp78":
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 256.0

        case "sp87":
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 128.0

        case "sp96":
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 64.0

        case "flt":
            guard bytes.count >= 4 else { return nil }
            var floatValue: Float = 0
            withUnsafeMutableBytes(of: &floatValue) { dest in
                bytes.prefix(4).enumerated().forEach { dest[$0.offset] = $0.element }
            }
            return Double(floatValue)

        case "ui8":
            return Double(bytes[0])

        case "ui16":
            let value = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(value)

        default:
            // 默认尝试 sp78
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 256.0
        }
    }

    private static func readFanSpeed(index: Int) -> Int? {
        let key = String(format: "F%dAc", index)
        guard let data = readKey(key), data.count >= 2 else { return nil }

        // M2/M3/M4 chips use flt (Float) format: 4 bytes little-endian
        if data.count >= 4 {
            let floatValue = data.withUnsafeBytes { ptr -> Float in
                ptr.load(as: Float.self)
            }
            // Allow 0 RPM (fan stopped) - valid range 0-10000
            if floatValue >= 0 && floatValue < 10000 {
                return Int(floatValue)
            }
        }

        let byte0 = Int(data[0])
        let byte1 = Int(data[1])

        // Intel/M1 use FPE2 format: unsigned fixed-point with 2 fractional bits
        // Variant 1: (byte0 << 6) | (byte1 >> 2)
        let fpe2Variant1 = (byte0 << 6) | (byte1 >> 2)
        if fpe2Variant1 >= 0 && fpe2Variant1 < 10000 {
            return fpe2Variant1
        }

        // Variant 2: (rawValue >> 2)
        let rawValue = (byte0 << 8) | byte1
        let fpe2Variant2 = rawValue >> 2
        if fpe2Variant2 >= 0 && fpe2Variant2 < 10000 {
            return fpe2Variant2
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
