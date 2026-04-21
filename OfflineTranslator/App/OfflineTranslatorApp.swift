import SwiftUI
import SwiftData

@main
struct OfflineTranslatorApp: App {

    // MVP 階段：預設用全 Mock 組裝（文字翻譯會走通，其他有 Mock 資料），
    // Day 4 串 Apple Translation 前改成 `.makeDefault()`。
    @StateObject private var deps = AppDependencies.makeMock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(deps)
                .tint(Theme.Colors.accent)
                .preferredColorScheme(.light) // 設計以淺色為主
        }
        .modelContainer(deps.modelContainer)
    }
}
