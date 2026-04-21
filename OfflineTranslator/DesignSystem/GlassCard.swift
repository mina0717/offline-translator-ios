import SwiftUI

/// 半透明玻璃卡片容器。所有主要 UI 區塊應該包進這個元件，
/// 確保視覺風格一致（圓角 + ultraThinMaterial + 細邊）。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.lg
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.glassStroke, lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

/// 把任意 View 包成玻璃卡片的便捷 modifier。
extension View {
    func glassCard(
        cornerRadius: CGFloat = Theme.Radius.lg,
        padding: CGFloat = Theme.Spacing.md
    ) -> some View {
        GlassCard(cornerRadius: cornerRadius, padding: padding) { self }
    }
}

#Preview {
    ZStack {
        GradientBackground()
        VStack(spacing: 16) {
            Text("Hello, World!")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

            Text("這是玻璃卡片預覽")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        }
        .padding()
    }
}
