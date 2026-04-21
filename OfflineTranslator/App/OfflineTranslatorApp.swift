import SwiftUI
import SwiftData

@main
struct OfflineTranslatorApp: App {

    // MVP 階段：預設用全 Mock 組裝（文字翻譯會走通，其他有 Mock 資料），
    // Day 4 串 Apple Translation 前改成 `.makeDefault()`。
    @StateObject private var deps = AppDependencies.makeMock()

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
