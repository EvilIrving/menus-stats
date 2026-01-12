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
