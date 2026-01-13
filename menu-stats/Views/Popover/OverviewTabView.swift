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
                
                // Top CPU Processes
                topProcessesSection

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
            // Load Average (above temperature)
            StatusRow(
                icon: "⚡️",
                label: "负载",
                value: monitor.loadAverage.displayString
            )
            
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
    
    // MARK: - Top Processes Section
    
    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✲ Processes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            if monitor.topCPUProcesses.isEmpty {
                Text("加载中...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 6) {
                    ForEach(monitor.topCPUProcesses) { process in
                        ProcessRow(process: process)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Core Usage Section

    private var coreUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("核心使用率")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                // Show P/E core count label
                if monitor.coreTopology.performanceCores > 0 || monitor.coreTopology.efficiencyCores > 0 {
                    Text("(\(monitor.coreTopology.displayLabel))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal)

            VStack(spacing: 6) {
                // Group and sort cores: P-cores first, then E-cores
                let sortedCores = getSortedCores()
                ForEach(sortedCores, id: \.index) { core in
                    CoreUsageRow(
                        coreIndex: core.displayIndex,
                        usage: core.usage,
                        coreType: core.type
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper: Sorted Cores
    
    private struct CoreInfo {
        let index: Int
        let displayIndex: Int
        let usage: Double
        let type: CoreType
    }
    
    /// Get cores sorted by type: P-cores first (numbered 0..N), then E-cores (numbered 0..M)
    private func getSortedCores() -> [CoreInfo] {
        let topology = monitor.coreTopology
        let usages = monitor.coreUsages
        
        guard !usages.isEmpty else { return [] }
        
        // If we have P/E core info, group them
        if topology.performanceCores > 0 && topology.efficiencyCores > 0 {
            var result: [CoreInfo] = []
            let pCount = topology.performanceCores
            let eCount = topology.efficiencyCores
            
            // P-cores first (assume they are the first N cores)
            for i in 0..<min(pCount, usages.count) {
                result.append(CoreInfo(
                    index: i,
                    displayIndex: i,
                    usage: usages[i],
                    type: .performance
                ))
            }
            
            // E-cores after (assume they follow P-cores)
            for i in 0..<min(eCount, usages.count - pCount) {
                let actualIndex = pCount + i
                if actualIndex < usages.count {
                    result.append(CoreInfo(
                        index: actualIndex,
                        displayIndex: i,
                        usage: usages[actualIndex],
                        type: .efficiency
                    ))
                }
            }
            
            return result
        } else {
            // No P/E info, show all cores with unknown type
            return usages.enumerated().map { index, usage in
                CoreInfo(
                    index: index,
                    displayIndex: index,
                    usage: usage,
                    type: .unknown
                )
            }
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

// MARK: - Process Row

private struct ProcessRow: View {
    let process: TopProcess
    
    var color: Color {
        if process.cpuPercent < 30 {
            return .green
        } else if process.cpuPercent < 70 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Process name
            Text(process.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Mini progress bar (5 blocks)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let threshold = Double(i + 1) * 20
                    Rectangle()
                        .fill(process.cpuPercent >= threshold - 10 ? color : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 10)
                        .cornerRadius(2)
                }
            }
            
            // CPU percentage
            Text(process.cpuDisplayString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
