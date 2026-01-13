import SwiftUI

struct BentoCard<Content: View>: View {
    let title: String?
    let icon: String?
    let content: Content
    let padding: CGFloat
    
    init(title: String? = nil, icon: String? = nil, padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || icon != nil {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    if let title = title {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}
