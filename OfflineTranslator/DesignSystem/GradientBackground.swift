import SwiftUI

/// 全 App 共用的淺粉紫漸層背景。放在每個 Feature 的最底層。
struct GradientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Theme.Colors.gradientStart,
                Theme.Colors.gradientMid,
                Theme.Colors.gradientEnd
            ],
            startPoint: .topLeading,
            endPoint:   .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    GradientBackground()
}
