//
//  RingView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

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
