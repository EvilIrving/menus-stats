//
//  DiskInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

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
