//
//  MemoryStatRow.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

/// Memory stat item with label, value and tooltip for sorting
struct MemoryStatItem: Identifiable {
    let id = UUID()
    let label: String
    let value: UInt64
    let tooltip: String
}

struct MemoryStatRow: View {
    let label: String
    let value: UInt64
    var tooltip: String = ""

    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(ByteFormatter.format(value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}
