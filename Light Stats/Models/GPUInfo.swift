//
//  GPUInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
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
