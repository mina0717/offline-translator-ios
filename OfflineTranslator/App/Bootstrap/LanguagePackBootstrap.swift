import Foundation
import SwiftUI

/// 語言包預下載器
///
/// **v1.3.0 演進**：從原本只下 zh↔en 兩個方向，改為「**掃描全部 42 個 supported pair，
/// 把所有未下載的依序下載**」。Mina 對使用者期望的判斷：「打開 App 就自動下載」。
///
/// 為何不一次平行 42 個？
/// - Apple Translation framework 的 `prepareTranslation()` 一次只能配置一個 source/target，
///   因此只能序列下載
/// - 也避免一口氣 42 個 iOS 系統 sheet 噴出來
///
/// 使用者控制：
/// - `@AppStorage("autoDownloadAllPacks")` 預設 true（=「自動下載」）
/// - 在 SettingsView 可關閉，關閉後 bootstrap 退化為「不做任何事」
/// - 進行中可呼叫 `pause()` 暫停
@MainActor
final class LanguagePackBootstrap: ObservableObject {

    @Published private(set) var phaseTag: Int = 0   // 0=idle 1=scanning 2=downloading 3=done 4=failed
    @Published private(set) var currentPairText: String = ""
    @Published private(set) var failureMessage: String?
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var isPaused: Bool = false

    private var hasStarted = false
    private var pendingPairs: [LanguagePair] = []
    private var currentTask: Task<Void, Never>?

    /// v1.3.0：使用者偏好。預設「啟動時自動下載所有缺失語言包」開啟。
    @AppStorage("autoDownloadAllPacks") private var autoDownloadAllPacks: Bool = true

    func runIfNeeded(mtService: AppleMTService?) async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let mt = mtService else { phaseTag = 0; return }

        // v1.3.0：使用者關閉自動下載 → 跳過
        if !autoDownloadAllPacks {
            phaseTag = 0
            return
        }

        // 第一階段：掃描「Tier 1」配對找出未下載
        // v13.6：14 國 / 182 對全掃太多（15GB、182 個 iOS 系統 sheet）。
        // 改成只掃「以繁中為錨點」的雙向配對 = 26 對（~2GB）。
        // 其他配對（en↔ja、ja↔ko 等）走 v13.3 的 just-in-time preheat
        // （使用者切到那個語言時 VM 自動 preheat），或使用者到語言包頁手動下載。
        phaseTag = 1
        let tier1 = Self.tier1Pairs
        var missing: [LanguagePair] = []
        for pair in tier1 {
            if isPaused { phaseTag = 0; return }
            currentPairText = "\(pair.source.displayName) → \(pair.target.displayName)"
            let status = (try? await mt.languagePackStatus(for: pair)) ?? .notDownloaded
            if status != .ready {
                missing.append(pair)
            }
        }

        if missing.isEmpty {
            phaseTag = 3
            currentPairText = ""
            return
        }

        // 第二階段：序列下載
        pendingPairs = missing
        completedCount = 0
        totalCount = missing.count
        phaseTag = 2

        for (idx, pair) in missing.enumerated() {
            if isPaused { return }   // 暫停就停在這
            currentPairText = "\(pair.source.displayName) → \(pair.target.displayName)"
            do {
                try await mt.downloadLanguagePack(for: pair)
                mt.invalidateLanguagePackStatusCache()
            } catch is CancellationError {
                // 使用者在系統 sheet 取消單一語言 → 跳過、不算失敗
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if msg.localizedCaseInsensitiveContains("cancel") {
                    // 同上
                } else {
                    phaseTag = 4
                    failureMessage = "下載 \(currentPairText) 失敗：\(msg)"
                    return
                }
            }
            completedCount = idx + 1
        }

        phaseTag = 3
        currentPairText = ""
    }

    /// v1.3.0：使用者按 banner 上的暫停鈕
    func pause() {
        isPaused = true
        if phaseTag != 4 {
            phaseTag = 0
        }
    }

    /// 從暫停狀態恢復
    func resume(mtService: AppleMTService?) async {
        isPaused = false
        hasStarted = false
        await runIfNeeded(mtService: mtService)
    }

    func retry(mtService: AppleMTService?) async {
        hasStarted = false
        phaseTag = 0
        isPaused = false
        await runIfNeeded(mtService: mtService)
    }

    var isWorking: Bool { phaseTag == 1 || phaseTag == 2 }
    var isDone: Bool { phaseTag == 3 }

    var bannerMessage: String? {
        switch phaseTag {
        case 1:  return "檢查語言包：\(currentPairText)"
        case 2:  return "自動下載中：\(currentPairText)"
        case 4:  return failureMessage
        default: return nil
        }
    }

    /// v13.6：Tier 1 = 「繁中為錨點」的雙向配對。
    /// 14 種語言 × 2（繁中→其他、其他→繁中）− 1（繁中→繁中已排除） = **26 對**
    /// 大約 2GB。涵蓋 Taiwan 使用者最主要的 use case（中翻外、外翻中）。
    static var tier1Pairs: [LanguagePair] {
        let anchor: Language = .traditionalChinese
        var pairs: [LanguagePair] = []
        for other in Language.allCases where other != anchor {
            pairs.append(.init(source: anchor, target: other))
            pairs.append(.init(source: other, target: anchor))
        }
        return pairs
    }
}
