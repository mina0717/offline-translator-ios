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
    @State private var path: NavigationPath

    init() {
        _path = State(initialValue: Self.launchPath())
    }

    /// v1.5.0：冷啟動時的初始導覽堆疊 —— 使用者若指定了「預設翻譯模式」，
    /// 就直接從那個畫面開始（主畫面仍在下面，按返回就回得去）。
    ///
    /// 為什麼放在 `@State` 的初始值，而不是 `onAppear` 之後再 push：
    /// - 冷啟動直接顯示目標畫面，不會先閃一下主畫面再滑進去
    /// - 避開「導覽堆疊尚未就緒就 push」的時序問題
    /// - `@State` 的初始值只在 view 第一次建立時採用，所以天然只套用一次：
    ///   從背景回到前景、使用者在設定頁改選項，都不會被硬拉到別的畫面
    ///
    /// Siri / 捷徑的優先權：若這次是由 App Intent 啟動，`drainQueue()` 會先把
    /// `path` 整個重設再導向翻譯頁，所以 Intent 一定贏過預設畫面。
    private static func launchPath() -> NavigationPath {
        var path = NavigationPath()
        if let destination = LaunchMode.current.destination {
            path.append(destination)
        }
        return path
    }

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
        // v13.7：也顯示 low storage 警告（phaseTag = 5）
        .safeAreaInset(edge: .top) {
            if packBootstrap.isWorking {
                LanguagePackDownloadBanner(bootstrap: packBootstrap)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if packBootstrap.isLowStorageWarning {
                LanguagePackLowStorageBanner(bootstrap: packBootstrap)
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

/// v13.7：當 phaseTag = 5（lowStorage）時顯示橘色警告
private struct LanguagePackLowStorageBanner: View {
    @ObservedObject var bootstrap: LanguagePackBootstrap

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(bootstrap.bannerMessage ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color.orange.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
    }
}

/// 頂部進度條：告訴使用者「正在下載語言包」，避免他們以為 App 壞了。
/// v1.3.0：加上暫停按鈕與整體進度（X / Y 個語言包）
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

                // 進度文字（v1.3.0：只在下載階段顯示）
                if bootstrap.totalCount > 0 {
                    Text("\(bootstrap.completedCount) / \(bootstrap.totalCount) 個語言包已完成")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            // v1.3.0：暫停按鈕，使用者覺得太煩可以隨時停
            Button {
                bootstrap.pause()
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(Text("暫停自動下載"))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.accent.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }
}
