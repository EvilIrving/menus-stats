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
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .selectedControlColor))
                        .matchedGeometryEffect(id: "ACTIVE_TAB", in: namespace)
                        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
                }
            }
        )
    }
}