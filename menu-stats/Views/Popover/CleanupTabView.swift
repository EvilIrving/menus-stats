//
//  CleanupTabView.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct CleanupTabView: View {
    @StateObject private var appManager = AppMemoryManager.shared
    @State private var showForceTerminateAlert = false
    @State private var appToTerminate: RunningApp?

    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            memorySummaryHeader

            Divider()

            // Cache Section with Ring and Clear Button
            // cacheSectionView

            Divider()

            // Detailed Memory Info Section (without cache indicators)
            if appManager.detailedMemory != nil {
                detailedMemorySection

                Divider()
            }

            // App Count Header (above list)
            appCountHeader

            // App List
            if appManager.runningApps.isEmpty {
                emptyStateView
            } else {
                appListView
            }
        }
        .onAppear {
            appManager.startMonitoring()
        }
        .alert("应用未响应", isPresented: $showForceTerminateAlert) {
            Button("强制关闭", role: .destructive) {
                if let app = appToTerminate {
                    _ = appManager.forceTerminateApp(app)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用未响应，是否强制关闭？\n可能导致未保存的数据丢失。")
        }
    }

    // MARK: - Memory Summary Header

    private var memorySummaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("💾")
                Text("内存占用")
                    .font(.system(size: 13))
                Spacer()
                Text("\(ByteFormatter.format(appManager.totalMemoryUsed)) / \(ByteFormatter.format(appManager.totalMemory))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(String(format: "(%.0f%%)", memoryUsagePercent))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Progress bar with pressure-based color
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(memoryBarColor)
                        .frame(width: geometry.size.width * min(memoryUsagePercent / 100, 1.0))
                        .animation(.easeInOut(duration: 0.3), value: memoryUsagePercent)
                }
            }
            .frame(height: 8)
        }
        .padding()
    }

    private var memoryUsagePercent: Double {
        guard appManager.totalMemory > 0 else { return 0 }
        return Double(appManager.totalMemoryUsed) / Double(appManager.totalMemory) * 100
    }

    /// Memory bar color based on memory pressure level
    private var memoryBarColor: Color {
        switch appManager.memoryPressure {
        case .normal:
            return .green
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }

    // MARK: - Cache Section (Ring + Clear Button)

    private var purgeableMemory: UInt64 {
        appManager.detailedMemory?.purgeable ?? 0
    }

    private var purgeablePercent: Double {
        guard appManager.totalMemory > 0 else { return 0 }
        return Double(purgeableMemory) / Double(appManager.totalMemory) * 100
    }

    private var cacheSectionView: some View {
        HStack(spacing: 16) {
            // Purgeable Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: min(purgeablePercent / 100, 1.0))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: purgeablePercent)

                VStack(spacing: 2) {
                    Text(ByteFormatter.format(purgeableMemory))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("可清理内存")
                    .font(.system(size: 12, weight: .medium))
                Text("系统可释放的缓存数据")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Clear Cache Button
            Button(action: clearCache) {
                VStack(spacing: 4) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text("清理")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("清除可释放的系统缓存")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func clearCache() {
        // Trigger system memory cleanup by running purge command
        // Note: This requires admin privileges, so we'll use a safer approach
        Task {
            await appManager.triggerMemoryCleanup()
        }
    }

    // MARK: - Detailed Memory Section

    /// Get sorted memory stats (by value descending)
    private func getSortedMemoryStats(from mem: MemoryInfo.DetailedInfo) -> [MemoryStatItem] {
        let stats: [MemoryStatItem] = [
            MemoryStatItem(label: "活跃", value: mem.active,
                          tooltip: "正在被应用程序使用的内存，最近被访问过"),
            MemoryStatItem(label: "非活跃", value: mem.inactive,
                          tooltip: "最近未被访问的内存，可能被重新分配"),
            MemoryStatItem(label: "联动", value: mem.wired,
                          tooltip: "系统核心使用的内存，不可被换出或释放"),
            MemoryStatItem(label: "压缩", value: mem.compressed,
                          tooltip: "被压缩以节省空间的内存数据"),
            MemoryStatItem(label: "推测", value: mem.speculative,
                          tooltip: "系统预读的数据，可被快速释放"),
            MemoryStatItem(label: "文件缓存", value: mem.external,
                          tooltip: "文件系统缓存，由系统自动管理"),
            MemoryStatItem(label: "交换区", value: mem.swapUsed,
                          tooltip: "已使用的磁盘交换空间，内存不足时启用"),
            MemoryStatItem(label: "可清理", value: mem.purgeable,
                          tooltip: "应用标记可丢弃的内存，系统可随时释放")
        ]
        return stats.sorted { $0.value > $1.value }
    }

    private var detailedMemorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let mem = appManager.detailedMemory {
                let sortedStats = getSortedMemoryStats(from: mem)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 4) {
                    ForEach(sortedStats) { stat in
                        MemoryStatRow(label: stat.label, value: stat.value, tooltip: stat.tooltip)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - App Count Header

    private var appCountHeader: some View {
        HStack {
            Text("🚀")
            Text("运行中 App: \(appManager.runningApps.count) 个")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.05))
    }

    // MARK: - App List

    private var appListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appManager.runningApps) { app in
                    AppRowView(app: app) {
                        terminateApp(app)
                    }
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("没有运行中的应用")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func terminateApp(_ app: RunningApp) {
        let success = appManager.terminateApp(app)
        if !success {
            appToTerminate = app
            showForceTerminateAlert = true
        }
    }
}
