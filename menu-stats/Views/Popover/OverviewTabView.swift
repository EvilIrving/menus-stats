//
//  OverviewTabView.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct OverviewTabView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Main Rings
                mainRingsSection

                Divider()
                    .padding(.horizontal)

                // System Status
                systemStatusSection

                Divider()
                    .padding(.horizontal)

                // Core Usage
                coreUsageSection
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Main Rings Section

    private var mainRingsSection: some View {
        HStack(spacing: 24) {
            RingView(
                value: monitor.cpuUsage,
                label: "CPU",
                color: colorForUsage(monitor.cpuUsage)
            )
            .help("System: \(String(format: "%.0f%%", monitor.cpuSystemUsage))\nUser: \(String(format: "%.0f%%", monitor.cpuUserUsage))")

            RingView(
                value: monitor.gpuUsage ?? 0,
                label: "GPU",
                color: colorForUsage(monitor.gpuUsage ?? 0),
                isAvailable: monitor.gpuUsage != nil
            )

            RingView(
                value: monitor.memoryUsage,
                label: "MEM",
                color: colorForUsage(monitor.memoryUsage)
            )
        }
        .padding(.horizontal)
    }

    // MARK: - System Status Section

    private var systemStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Temperature
            if let temp = monitor.cpuTemperature {
                StatusRow(icon: "🌡️", label: "温度", value: String(format: "%.0f℃", temp))
            } else {
                StatusRow(icon: "🌡️", label: "温度", value: "N/A", isAvailable: false)
            }

            // Fan
            if let fan = monitor.fanSpeed {
                StatusRow(icon: "🌀", label: "风扇", value: "\(fan) RPM")
            } else {
                StatusRow(icon: "🌀", label: "风扇", value: "N/A", isAvailable: false)
            }

            // Disk
            StatusRow(
                icon: "💾",
                label: "磁盘",
                value: "可用 \(ByteFormatter.format(monitor.diskAvailable)) / 共 \(ByteFormatter.format(monitor.diskTotal))"
            )

            // Network
            StatusRow(
                icon: "🌐",
                label: "网络",
                value: "⬆ \(ByteFormatter.formatSpeed(monitor.networkUpload))   ⬇ \(ByteFormatter.formatSpeed(monitor.networkDownload))"
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Core Usage Section

    private var coreUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("核心使用率")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 6) {
                ForEach(Array(monitor.coreUsages.enumerated()), id: \.offset) { index, usage in
                    CoreUsageRow(coreIndex: index, usage: usage)
                }
            }
            .padding(.horizontal)
        }
    }

    private func colorForUsage(_ usage: Double) -> Color {
        if usage < 50 {
            return .green
        } else if usage < 80 {
            return .yellow
        } else {
            return .red
        }
    }
}
