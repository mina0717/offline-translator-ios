import SwiftUI

/// App 進入點容器。負責：
/// 1. 放上漸層背景
/// 2. 包 NavigationStack
/// 3. **掛載 Apple Translation bridge modifier**（Mac 借機日驗證）
///
/// bridge modifier 只有在 MTService 是 `AppleMTService`（`.makeDefault()`）
/// 時才會實際生效；Mock 模式下是 no-op。
struct RootView: View {
    @EnvironmentObject private var deps: AppDependencies

    var body: some View {
        ZStack {
            GradientBackground()
            NavigationStack {
                HomeView()
            }
        }
        // 把 AppleMTService 的 bridge 掛到 View tree 上，
        // .translationTask modifier 才能在需要時執行翻譯與語言包下載。
        .appleTranslationBridge(deps.mtService as? AppleMTService)
    }
}

#Preview {
    RootView()
        .environmentObject(AppDependencies.makeMock())
}
