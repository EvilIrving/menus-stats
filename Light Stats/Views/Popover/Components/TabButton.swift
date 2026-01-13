//
//  TabButton.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

// Proposed TabButton change
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .foregroundColor(isSelected ? .primary : .secondary)
            .animation(nil, value: isSelected)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "ACTIVE_TAB", in: namespace)
                    }
                }
            )
            .contentShape(Capsule())
            .onTapGesture {
                action()
            }
    }
}