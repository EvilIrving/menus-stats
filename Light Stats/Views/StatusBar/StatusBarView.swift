//
//  StatusBarView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit

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
        static let arrowWidth: CGFloat = 8         // 箭头固定宽度
        static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        static let logoFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
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
        settings: SettingsManaging
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
                value: ByteFormatter.formatSpeed(upload),
                label: ByteFormatter.formatSpeed(download),
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

    static func calculateWidth(settings: SettingsManaging) -> CGFloat {
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
                // 网络项特殊绘制：箭头固定，数值等宽
                let netAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.networkFont,
                    .foregroundColor: textColor
                ]
                let lineSpacing: CGFloat = 0 
                let arrowXOffset: CGFloat = 2 
                let globalYOffset: CGFloat = -1 // 整体下移 1 单位

                // 绘制上传 (上行)
                let upArrow = "↑"
                let upValue = item.value
                
                let upArrowPoint = NSPoint(x: itemRect.origin.x + arrowXOffset, y: itemRect.midY + lineSpacing + globalYOffset)
                upArrow.draw(at: upArrowPoint, withAttributes: netAttrs)
                
                let upValuePoint = NSPoint(x: itemRect.origin.x + arrowXOffset + Layout.arrowWidth, y: itemRect.midY + lineSpacing + globalYOffset)
                upValue.draw(at: upValuePoint, withAttributes: netAttrs)

                // 绘制下载 (下行)
                let downArrow = "↓"
                let downValue = item.label
                
                let textHeight = item.label.size(withAttributes: netAttrs).height
                let downY = itemRect.midY - textHeight + 1 + globalYOffset
                
                let downArrowPoint = NSPoint(x: itemRect.origin.x + arrowXOffset, y: downY)
                downArrow.draw(at: downArrowPoint, withAttributes: netAttrs)
                
                let downValuePoint = NSPoint(x: itemRect.origin.x + arrowXOffset + Layout.arrowWidth, y: downY)
                downValue.draw(at: downValuePoint, withAttributes: netAttrs)
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
