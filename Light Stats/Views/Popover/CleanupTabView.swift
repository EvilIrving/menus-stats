//
//  CleanupTabView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct CleanupTabView: View {
    @StateObject private var appManager = AppMemoryManager.shared
    @State private var showForceTerminateAlert = false
    @State private var appToTerminate: RunningApp?
    @State private var terminatingApps: Set<Int32> = []

    var body: some View {
        VStack(spacing: 12) {
            // Memory Summary Card
            BentoCard(title: "cleanup.memoryUsage".localized, icon: "memorychip.fill") {
                VStack(spacing: 12) {
                    HStack {
                        Text("\(ByteFormatter.format(appManager.totalMemoryUsed)) / \(ByteFormatter.format(appManager.totalMemory))")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Text(String(format: "%.0f%%", memoryUsagePercent))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.05))

                            Capsule()
                                .fill(memoryBarColor)
                                .frame(width: geometry.size.width * CGFloat(min(memoryUsagePercent / 100.0, 1.0)))
                        }
                    }
                    .frame(height: 8)
                    
                    // Swap Warning (only show when swap is used)
                    if swapUsed > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text("Swap")
                                .font(.system(size: 11, weight: .medium))
                            Text(ByteFormatter.format(swapUsed))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Spacer()
                        }
                        .foregroundColor(swapUsed < 1024 * 1024 * 1024 ? .orange : .red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Simplified Metrics Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                // Available
                BentoCard(title: "cleanup.availableMemory".localized, icon: "checkmark.circle.fill") {
                    Text(ByteFormatter.format(appManager.totalMemory - appManager.totalMemoryUsed))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                
                // App Used
                BentoCard(title: "cleanup.appUsed".localized, icon: "app.dashed") {
                    Text(ByteFormatter.format(appManager.totalMemoryUsed))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)

            // App List Header
            HStack {
                Text("cleanup.runningApps".localized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "cleanup.appCount".localized, appManager.runningApps.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // App List
            if appManager.runningApps.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(appManager.runningApps) { app in
                            AppCardView(
                                app: app,
                                isTerminating: terminatingApps.contains(app.id)
                            ) {
                                terminateApp(app)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            appManager.startMonitoring()
            
            // DEBUG: 打印所有进程信息
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("\n========== DEBUG: 所有运行中的应用 ==========")
                for app in appManager.runningApps {
                    print("[应用] \(app.name)")
                    print("  - bundleId: \(app.bundleIdentifier ?? "nil")")
                    print("  - execPath: \(app.execPath ?? "nil")")
                    print("  - bundlePath: \(app.bundlePath ?? "nil")")
                    print("  - memory: \(app.memoryFormatted)")
                    print("  - isSystemApp: \(app.isSystemApp)")
                    print("  - isAppleApp: \(app.isAppleApp)")
                    print("")
                }
                print("========== END DEBUG ==========")
            }
        }
        .alert("cleanup.appNotResponding".localized, isPresented: $showForceTerminateAlert) {
            Button("cleanup.forceQuit".localized, role: .destructive) {
                if let app = appToTerminate {
                    _ = appManager.forceTerminateApp(app)
                }
            }
            Button("cleanup.cancel".localized, role: .cancel) {}
        } message: {
            Text("cleanup.forceQuitMessage".localized)
        }
    }

    // MARK: - Helpers

    private var memoryUsagePercent: Double {
        guard appManager.totalMemory > 0 else { return 0 }
        return Double(appManager.totalMemoryUsed) / Double(appManager.totalMemory) * 100
    }

    private var memoryBarColor: Color {
        switch appManager.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
    
    private var swapUsed: UInt64 {
        appManager.detailedMemory?.swapUsed ?? 0
    }

    // MARK: - Actions

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("cleanup.noApps".localized)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func terminateApp(_ app: RunningApp) {
        guard !terminatingApps.contains(app.id) else { return }
        
        terminatingApps.insert(app.id)
        
        Task {
            let success = await appManager.terminateAppAsync(app)
            
            await MainActor.run {
                terminatingApps.remove(app.id)
                
                if !success && appManager.isProcessAlive(app.id) {
                    appToTerminate = app
                    showForceTerminateAlert = true
                }
            }
        }
    }
}
