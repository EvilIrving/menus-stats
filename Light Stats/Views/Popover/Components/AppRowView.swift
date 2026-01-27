//
//  AppRowView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct AppCardView: View {
    let app: RunningApp
    var isTerminating: Bool = false
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .opacity(isTerminating ? 0.5 : 1.0)

            // App Name
            Text(app.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .opacity(isTerminating ? 0.5 : 1.0)

            Spacer()

            // Memory Usage
            Text(app.memoryFormatted)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .opacity(isTerminating ? 0.5 : 1.0)

            // Close Button or Loading Indicator
            if isTerminating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isHovered ? .red.opacity(0.8) : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("关闭应用")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.8 : 0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .allowsHitTesting(!isTerminating)
    }
}