import SwiftUI
import UIKit

/// App 進入點容器。負責：
/// 1. 放上漸層背景
/// 2. 包 NavigationStack
/// 3. **掛載 Apple Translation bridge modifier**（Mac 借機日驗證）
/// 4. **消費 AppIntents 丟過來的 pending 請求**（v1.1 Codex fix）
///
/// bridge modifier 只有在 MTService 是 `AppleMTService`（`.makeDefault()`）
/// 時才會實際生效；Mock 模式下是 no-op。
///
/// ## v1.1.1 fix：path-based navigation + queue consumption
/// 先前用 `navigationDestination(item:)` 綁單一 `IntentNavigation?`，
/// 連兩個 intent 進來會讓 NavigationStack 疊兩層 TextTranslationView。
/// 改用 `NavigationPath` 手動管理：每收到一筆 intent 先 `path = NavigationPath()`
/// reset 回 Home，再 append 新目的地，確保同一時間只有一個翻譯畫面。
struct RootView: View {
    @EnvironmentObject private var deps: AppDependencies
    @StateObject private var intentStore = IntentRequestStore.shared

    /// NavigationStack 的 path — 由我們自己管，避免 intent 重複 push 造成疊層。
    @State private var path = NavigationPath()

    var body: some View {
        ZStack {
            GradientBackground()
            NavigationStack(path: $path) {
                HomeView()
                    .navigationDestination(for: IntentNavigation.self) { nav in
                        TextTranslationView(prefill: nav.prefill, target: nav.target)
                    }
            }
        }
        // 把 AppleMTService 的 bridge 掛到 View tree 上，
        // .translationTask modifier 才能在需要時執行翻譯與語言包下載。
        .appleTranslationBridge((deps.mtService as? AppleMTService)?.bridge)
        // v1.1 fix：監聽 Siri / Shortcuts 送過來的 queue；每次 queue 非空就消費首筆。
        .onReceive(intentStore.$queue.filter { !$0.isEmpty }) { _ in
            drainQueue()
        }
    }

    /// 把 queue 裡能處理的請求全部 dequeue 並導航到對應畫面。
    /// 用 `drainAll()` 一次取乾淨，避免 for-loop 中 `consume()` 的 @Published
    /// 更新反覆觸發 onReceive 導致 reentrant。多筆 intent 時只保留最後一筆
    /// 有效的請求（使用者意圖通常是最新那筆）。
    private func drainQueue() {
        let requests = intentStore.drainAll()
        // 找出最後一個「可處理」的請求作為最終目的地
        var finalPrefill: String?
        var finalTarget: Language?

        for request in requests {
            switch request {
            case .translateText(let text, let target):
                finalPrefill = text
                finalTarget = target

            case .translateClipboard(let target):
                let clip = UIPasteboard.general.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !clip.isEmpty else { continue }
                finalPrefill = clip
                finalTarget = target
            }
        }

        if let prefill = finalPrefill, let target = finalTarget {
            pushTextTranslation(prefill: prefill, target: target)
        }
    }

    private func pushTextTranslation(prefill: String, target: Language) {
        // 先 pop 回 Home，再 push，避免同時存在兩個 TextTranslationView。
        path = NavigationPath()
        path.append(IntentNavigation(prefill: prefill, target: target))
    }
}

/// NavigationPath 的目的地 payload。
private struct IntentNavigation: Hashable {
    let prefill: String
    let target: Language
}

#Preview {
    RootView()
        .environmentObject(AppDependencies.makeMock())
}
