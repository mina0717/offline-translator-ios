import SwiftUI
import SwiftData

@main
struct OfflineTranslatorApp: App {

    // 上線版本：使用真實的 Apple Translation / Speech / Vision services。
    // 開發 / Preview 才用 `.makeMock()`（會回傳假資料、不打到系統 framework）。
    @StateObject private var deps = AppDependencies.makeDefault()

    // v1.1：啟動時初始化 TipKit（新手引導）
    init() {
        OnboardingTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(deps)
                .tint(Theme.Colors.accent)
                // v1.1：拿掉 .preferredColorScheme(.light) 鎖定。
                // Theme.Colors.* 現在是動態色，會跟著系統切亮／暗。
        }
        .modelContainer(deps.modelContainer)
    }
}
