//
//  AppRowView.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

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
