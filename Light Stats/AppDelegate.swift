//
//  AppDelegate.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private var statusBarView: StatusBarView?
    
    private let settings: SettingsManager
    private let monitor: SystemMonitor
    
    override init() {
        self.settings = SettingsManager.shared
        self.monitor = SystemMonitor.shared
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        startMonitoring()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        // Calculate initial width based on enabled items
        let initialWidth = StatusBarView.calculateWidth(settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

        if let button = statusItem?.button {
            // Create custom status bar view
            let view = StatusBarView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 22))
            statusBarView = view
            button.addSubview(view)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]

            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 480)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(monitor)
        )
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Debug SMC access
        SMCInfo.debugSMC()

        monitor.startMonitoring(interval: settings.refreshRate.interval)

        // 监听刷新频率变化，重新启动监控
        settings.$refreshRate
            .dropFirst()  // 跳过初始值
            .receive(on: DispatchQueue.main)
            .sink { [weak monitor = self.monitor] newRate in
                monitor?.startMonitoring(interval: newRate.interval)
            }
            .store(in: &cancellables)

        // Update status bar text when values change
        Publishers.CombineLatest4(
            monitor.$cpuUsage,
            monitor.$gpuUsage,
            monitor.$memoryUsage,
            monitor.$diskAvailable
        )
        .combineLatest(
            Publishers.CombineLatest3(
                monitor.$networkUpload,
                monitor.$networkDownload,
                monitor.$fanSpeed
            )
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] values in
            let (main, network) = values
            let (cpu, gpu, memory, disk) = main
            let (upload, download, fan) = network
            self?.updateStatusBarText(
                cpu: cpu,
                gpu: gpu,
                memory: memory,
                disk: disk,
                upload: upload,
                download: download,
                fan: fan
            )
        }
        .store(in: &cancellables)
    }

    private func updateStatusBarText(
        cpu: Double,
        gpu: Double?,
        memory: Double,
        disk: UInt64,
        upload: Double,
        download: Double,
        fan: Int?
    ) {
        // Update status bar view
        statusBarView?.updateValues(
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            disk: disk,
            upload: upload,
            download: download,
            fan: fan,
            settings: settings
        )

        // Update status item width
        let newWidth = StatusBarView.calculateWidth(settings: settings)
        statusItem?.length = newWidth
        statusBarView?.frame.size.width = newWidth
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Activate app to ensure popover receives focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
