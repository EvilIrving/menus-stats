//
//  ByteFormatter.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

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
            return String(format: "%.0f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}
