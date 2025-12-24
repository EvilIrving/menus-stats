//
//  AppDelegate.swift
//  menu-stats
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        startMonitoring()
    }
    
    // MARK: - Status Item Setup
    
    private func setupStatusItem() {
        // Calculate initial width based on enabled items
        let settings = SettingsManager.shared
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
                .environmentObject(SystemMonitor.shared)
        )
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        // Debug SMC access
        SMCInfo.debugSMC()
        
        let monitor = SystemMonitor.shared
        let settings = SettingsManager.shared
        monitor.startMonitoring(interval: settings.refreshRate.interval)
        
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
        let settings = SettingsManager.shared
        
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

// MARK: - Popover Content View

struct PopoverContentView: View {
    @State private var selectedTab: Int = 0
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                TabButton(title: "概览", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "清理释放", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                
                Spacer()
                
                // Settings Button
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            Divider()
                .padding(.top, 8)
            
            // Content Area
            Group {
                if selectedTab == 0 {
                    OverviewTabView()
                } else {
                    CleanupTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 360, height: 480)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview Tab (Placeholder)

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

// MARK: - Ring View

struct RingView: View {
    let value: Double
    let label: String
    let color: Color
    var isAvailable: Bool = true
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: isAvailable ? min(value / 100, 1.0) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)
                
                // Center text
                Text(isAvailable ? String(format: "%.0f%%", value) : "N/A")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(isAvailable ? .primary : .secondary)
            }
            .frame(width: 80, height: 80)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    var isAvailable: Bool = true
    
    var body: some View {
        HStack {
            Text(icon)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(isAvailable ? .primary : .secondary)
        }
    }
}

// MARK: - Core Usage Row

struct CoreUsageRow: View {
    let coreIndex: Int
    let usage: Double
    
    var color: Color {
        if usage < 50 {
            return .green
        } else if usage < 80 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Core \(coreIndex)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geometry.size.width * min(usage / 100, 1.0))
                        .animation(.easeInOut(duration: 0.3), value: usage)
                }
            }
            .frame(height: 12)
            
            Text(String(format: "%3.0f%%", usage))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Cleanup Tab

struct CleanupTabView: View {
    @StateObject private var appManager = AppMemoryManager.shared
    @State private var showForceTerminateAlert = false
    @State private var appToTerminate: RunningApp?
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            memorySummaryHeader
            
            Divider()
            
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
                Text("内存使用中")
                    .font(.system(size: 13))
                Spacer()
                Text("\(ByteFormatter.format(appManager.totalMemoryUsed)) / \(ByteFormatter.format(appManager.totalMemory))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(String(format: "(%.0f%%)", memoryUsagePercent))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
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
            
            HStack {
                Text("🚀")
                Text("运行中 App: \(appManager.appCount) 个")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
    }
    
    private var memoryUsagePercent: Double {
        guard appManager.totalMemory > 0 else { return 0 }
        return Double(appManager.totalMemoryUsed) / Double(appManager.totalMemory) * 100
    }
    
    private var memoryBarColor: Color {
        if memoryUsagePercent < 60 {
            return .green
        } else if memoryUsagePercent < 85 {
            return .yellow
        } else {
            return .red
        }
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

// MARK: - App Row View

struct AppRowView: View {
    let app: RunningApp
    let onClose: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            // App Name (shows process count if multiple)
            Text(app.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
            
            Spacer()
            
            // Memory Usage
            Text(app.memoryFormatted)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Close Button (shown on hover)
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭应用前请确认已保存数据")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    PopoverContentView()
}

// MARK: - Status Bar View

final class StatusBarView: NSView {
    
    // MARK: - Constants
    
    private enum Layout {
        static let logoWidth: CGFloat = 16
        static let percentItemWidth: CGFloat = 26  // CPU, GPU, MEM (e.g., "99%")
        static let diskItemWidth: CGFloat = 46     // DISK (e.g., "999 GB")
        static let networkItemWidth: CGFloat = 56  // NET (e.g., "↑0.0 KB/s" / "↓0.0 KB/s")
        static let fanItemWidth: CGFloat = 50      // FAN (e.g., "9999 RPM")
        static let separatorWidth: CGFloat = 2
        static let itemHeight: CGFloat = 22
        static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        static let logoFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)  // 网络上传下载专用
    }
    
    // MARK: - Data
    
    private var displayItems: [DisplayItem] = []
    
    private struct DisplayItem {
        let value: String
        let label: String
        let width: CGFloat
        let isLogo: Bool
        let isNetwork: Bool
        
        init(value: String, label: String = "", width: CGFloat, isLogo: Bool, isNetwork: Bool = false) {
            self.value = value
            self.label = label
            self.width = width
            self.isLogo = isLogo
            self.isNetwork = isNetwork
        }
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Public Methods
    
    func updateValues(
        cpu: Double,
        gpu: Double?,
        memory: Double,
        disk: UInt64,
        upload: Double,
        download: Double,
        fan: Int?,
        settings: SettingsManager
    ) {
        displayItems.removeAll()
        
        // Logo
        if settings.showLogo {
            displayItems.append(DisplayItem(
                value: "◉",
                label: "",
                width: Layout.logoWidth,
                isLogo: true
            ))
        }
        
        // CPU
        if settings.showCPU {
            displayItems.append(DisplayItem(
                value: String(format: "%.0f%%", cpu),
                label: "CPU",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }
        
        // GPU
        if settings.showGPU {
            let gpuText = gpu.map { String(format: "%.0f%%", $0) } ?? "N/A"
            displayItems.append(DisplayItem(
                value: gpuText,
                label: "GPU",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }
        
        // Memory
        if settings.showMemory {
            displayItems.append(DisplayItem(
                value: String(format: "%.0f%%", memory),
                label: "MEM",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }
        
        // Disk
        if settings.showDisk {
            displayItems.append(DisplayItem(
                value: ByteFormatter.formatDisk(disk),
                label: "DISK",
                width: Layout.diskItemWidth,
                isLogo: false
            ))
        }
        
        // Network (上传在上，下载在下，字体相同间距紧凑)
        if settings.showNetwork {
            displayItems.append(DisplayItem(
                value: "↑\(ByteFormatter.formatSpeed(upload))",
                label: "↓\(ByteFormatter.formatSpeed(download))",
                width: Layout.networkItemWidth,
                isLogo: false,
                isNetwork: true
            ))
        }
        
        // Fan
        if settings.showFan {
            let fanText = fan.map { "\($0) RPM" } ?? "-- RPM"
            displayItems.append(DisplayItem(
                value: fanText,
                label: "FAN",
                width: Layout.fanItemWidth,
                isLogo: false
            ))
        }
        
        needsDisplay = true
    }
    
    static func calculateWidth(settings: SettingsManager) -> CGFloat {
        var width: CGFloat = 0
        var itemCount = 0
        
        if settings.showLogo {
            width += Layout.logoWidth
            itemCount += 1
        }
        if settings.showCPU {
            width += Layout.percentItemWidth
            itemCount += 1
        }
        if settings.showGPU {
            width += Layout.percentItemWidth
            itemCount += 1
        }
        if settings.showMemory {
            width += Layout.percentItemWidth
            itemCount += 1
        }
        if settings.showDisk {
            width += Layout.diskItemWidth
            itemCount += 1
        }
        if settings.showNetwork {
            width += Layout.networkItemWidth
            itemCount += 1
        }
        if settings.showFan {
            width += Layout.fanItemWidth
            itemCount += 1
        }
        
        // Add separator space between items
        if itemCount > 1 {
            width += CGFloat(itemCount - 1) * Layout.separatorWidth
        }
        
        return max(width, 20)  // Minimum width
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Get appearance-aware colors
        let textColor = NSColor.labelColor
        _ = NSColor.secondaryLabelColor
        
        var xOffset: CGFloat = 0
        
        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)
            
            if item.isLogo {
                // Draw logo icon from Assets
                if let image = NSImage(named: "StatusIcon") {
                    image.isTemplate = true  // Adapt to light/dark mode
                    let iconSize: CGFloat = 16
                    let iconRect = NSRect(
                        x: itemRect.midX - iconSize / 2,
                        y: itemRect.midY - iconSize / 2,
                        width: iconSize,
                        height: iconSize
                    )
                    image.draw(in: iconRect)
                }
            } else if item.isNetwork {
                // 网络项特殊绘制：上传下载字体相同，间距紧凑
                let netAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.networkFont,
                    .foregroundColor: textColor
                ]
                let lineSpacing: CGFloat = 1  // 紧凑间距
                
                // 上传 (上行)
                let uploadSize = item.value.size(withAttributes: netAttrs)
                let uploadPoint = NSPoint(
                    x: itemRect.midX - uploadSize.width / 2,
                    y: itemRect.midY + lineSpacing / 2
                )
                item.value.draw(at: uploadPoint, withAttributes: netAttrs)
                
                // 下载 (下行)
                let downloadSize = item.label.size(withAttributes: netAttrs)
                let downloadPoint = NSPoint(
                    x: itemRect.midX - downloadSize.width / 2,
                    y: itemRect.midY - downloadSize.height - lineSpacing / 2
                )
                item.label.draw(at: downloadPoint, withAttributes: netAttrs)
            } else {
                // Draw value (top) - larger font, positioned closer to center
                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.valueFont,
                    .foregroundColor: textColor
                ]
                let valueSize = item.value.size(withAttributes: valueAttrs)
                let valuePoint = NSPoint(
                    x: itemRect.midX - valueSize.width / 2,
                    y: itemRect.height / 2 - 2
                )
                item.value.draw(at: valuePoint, withAttributes: valueAttrs)
                
                // Draw label (bottom) - clearer font, tighter spacing
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.labelFont,
                    .foregroundColor: textColor.withAlphaComponent(0.7)
                ]
                let labelSize = item.label.size(withAttributes: labelAttrs)
                let labelPoint = NSPoint(
                    x: itemRect.midX - labelSize.width / 2,
                    y: itemRect.height / 2 - labelSize.height - 2
                )
                item.label.draw(at: labelPoint, withAttributes: labelAttrs)
            }
            
            xOffset += item.width
            
            // Draw separator (except for the last item)
            if index < displayItems.count - 1 {
                xOffset += Layout.separatorWidth
            }
        }
    }
}
