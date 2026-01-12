//
//  CoreUsageRow.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

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
