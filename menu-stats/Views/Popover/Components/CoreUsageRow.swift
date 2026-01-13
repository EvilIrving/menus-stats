//
//  CoreUsageRow.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

/// Core type for Apple Silicon
enum CoreType {
    case performance  // P-core
    case efficiency   // E-core
    case unknown
    
    var label: String {
        switch self {
        case .performance: return "P"
        case .efficiency: return "E"
        case .unknown: return ""
        }
    }
    
    var color: Color {
        switch self {
        case .performance: return .orange
        case .efficiency: return .blue
        case .unknown: return .gray
        }
    }
}

struct CoreUsageRow: View {
    let coreIndex: Int
    let usage: Double
    var coreType: CoreType = .unknown

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
            // Core label with type badge
            HStack(spacing: 2) {
                if coreType != .unknown {
                    Text(coreType.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(coreType.color)
                }
                Text("\(coreIndex)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 28, alignment: .leading)

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
