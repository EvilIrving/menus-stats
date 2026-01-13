//
//  StatusRow.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

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
