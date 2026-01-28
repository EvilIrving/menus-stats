//
//  OverviewTabView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct OverviewTabView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // Main Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    // CPU Card
                    BentoCard(title: "CPU", icon: "cpu") {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", monitor.cpuUsage))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(colorForUsage(monitor.cpuUsage))
                    }
                    
                    // GPU Card
                    BentoCard(title: "GPU", icon: "square.grid.2x2") {
                        if let gpu = monitor.gpuUsage {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(String(format: "%.0f", gpu))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(colorForUsage(gpu))
                        } else {
                            Text("N/A")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // MEM Card
                    BentoCard(title: "MEM", icon: "memorychip") {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", Double(AppMemoryManager.shared.totalMemoryUsed) / 1024 / 1024 / 1024))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text("/")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.0fGB", Double(AppMemoryManager.shared.totalMemory) / 1024 / 1024 / 1024))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.purple)
                    }
                    
                    // Load Card
                    BentoCard(title: "overview.load".localized, icon: "chart.bar.fill") {
                        Text(monitor.loadAverage.displayString)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                
                // Status Strip
                BentoCard(padding: 10) {
                    HStack {
                        // Temp
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                            Text(monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "N/A")
                        }
                        
                        Spacer()
                        
                        // Fan
                        HStack(spacing: 4) {
                            Image(systemName: "fanblades.fill")
                            Text(monitor.fanSpeed.map { "\($0) RPM" } ?? "N/A")
                        }
                        
                        Spacer()
                        
                        // Disk
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive.fill")
                            Text(ByteFormatter.formatDisk(monitor.diskAvailable))
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                }
                
                // Network Card
                BentoCard(title: "overview.network".localized, icon: "network") {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text(ByteFormatter.formatSpeed(monitor.networkUpload))
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                            Text(ByteFormatter.formatSpeed(monitor.networkDownload))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
                }
                
                // Top Processes Section
                BentoCard(title: "overview.processes".localized, icon: "list.bullet") {
                    if monitor.topCPUProcesses.isEmpty {
                        Text("overview.loading".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(monitor.topCPUProcesses.prefix(3))) { process in
                                ProcessRow(process: process)
                            }
                        }
                    }
                }

                // Core Usage Section
                BentoCard(title: "overview.coreUsage".localized, icon: "cpu.fill") {
                    let sortedCores = getSortedCores()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sortedCores, id: \.index) { core in
                                VStack(spacing: 4) {
                                    Text("\(core.type == .performance ? "P" : "E")\(core.displayIndex)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(width: 12, height: 30)
                                        
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(colorForUsage(core.usage))
                                            .frame(width: 12, height: CGFloat(30.0 * (core.usage / 100.0)))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(16)
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
