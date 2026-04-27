import SwiftUI
import UIKit

/// App 進入點容器。負責：
/// 1. 放上漸層背景
/// 2. 包 NavigationStack
/// 3. **掛載 Apple Translation bridge modifier**
/// 4. **消費 AppIntents 丟過來的 pending 請求**
/// 5. **v1.2.1：啟動時 pre-download 兩個方向語言包，避免使用者首次翻譯時等 10 分鐘**
///
/// bridge modifier 只有在 MTService 是 `AppleMTService`（`.makeDefault()`）
/// 時才會實際生效；Mock 模式下是 no-op。
struct RootView: View {
    @EnvironmentObject private var deps: AppDependencies
    @StateObject private var intentStore = IntentRequestStore.shared

    /// v1.2.1：語言包預下載器（背景跑，UI 顯示進度條）
    @StateObject private var packBootstrap = LanguagePackBootstrap()

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
        // v1.1.3 critical fix：傳入 service 的 `bridge` instance（之前誤傳整個 service，
        // 導致 modifier 收到 nil，所有翻譯請求 hang 到 CancellationError）。
        .appleTranslationBridge((deps.mtService as? AppleMTService)?.bridge)
        // v1.1 fix：監聽 Siri / Shortcuts 送過來的 queue；每次 queue 非空就消費首筆。
        .onReceive(intentStore.$queue.filter { !$0.isEmpty }) { _ in
            drainQueue()
        }
        // v1.2.1：頂部 banner 顯示語言包下載進度
        .safeAreaInset(edge: .top) {
            if packBootstrap.isWorking {
                LanguagePackDownloadBanner(bootstrap: packBootstrap)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // v1.2.1：啟動就 pre-download 兩個方向語言包
        .task {
            await packBootstrap.runIfNeeded(
                mtService: deps.mtService as? AppleMTService
            )
        }
    }

    private func drainQueue() {
        let requests = intentStore.drainAll()
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
        path = NavigationPath()
        path.append(IntentNavigation(prefill: prefill, target: target))
    }
}

private struct IntentNavigation: Hashable {
    let prefill: String
    let target: Language
}

// MARK: - LanguagePackDownloadBanner

/// 頂部進度條：告訴使用者「正在下載語言包」，避免他們以為 App 壞了。
/// 中文使用者導向：訊息全部用中文，按鈕標籤親切。
private struct LanguagePackDownloadBanner: View {
    @ObservedObject var bootstrap: LanguagePackBootstrap

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .tint(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(bootstrap.bannerMessage ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // 進度文字
                Text("\(bootstrap.completedCount) / \(bootstrap.totalCount) 個方向已完成")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.accent.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bootstrap.bannerMessage ?? "下載語言包中")
    }
}
