import Foundation
import SwiftUI

/// 語言包預下載器
///
/// **v1.3.0 演進**：
/// - v1.2.x：固定下 zh↔en 兩個方向
/// - v13.4：掃所有 supported pair，缺失就下載（7 國 ~3GB）
/// - v13.6：14 國 = 182 對太多 → 改成 Tier 1（繁中錨點 26 對 ~2GB）
/// - **v13.7：加 storage check + Bootstrap 模式選擇（4 級）**
///
/// **下載量級設計（v13.7）**：
/// | Mode | 下載量 | 配對數 | 適合 |
/// | --- | --- | --- | --- |
/// | `.off`     | 0 | 0 | 容量極緊 / 想完全手動的使用者 |
/// | `.minimal` | ~160MB | 2 | 大部分使用者（zh↔en 兩個方向）|
/// | `.tier1`   | ~2GB | 26 | 繁中重度使用者（涵蓋全部 14 國繁中互譯）|
/// | `.full`    | ~15GB | 182 | 不太建議（容量需求太高，幾乎沒人需要全互譯）|
///
/// **Storage safety**：開機檢查可用空間，**< 3GB 自動降級為 minimal、< 1GB 直接 off** 並警告。
@MainActor
final class LanguagePackBootstrap: ObservableObject {

    // MARK: - Mode enum

    enum Mode: String, CaseIterable, Identifiable {
        case off
        case minimal     // zh↔en 兩個方向
        case tier1       // 繁中錨點 26 對
        case full        // 全部 182 對（不建議）

        var id: String { rawValue }
    }

    // MARK: - Published

    @Published private(set) var phaseTag: Int = 0   // 0=idle 1=scanning 2=downloading 3=done 4=failed 5=lowStorage
    @Published private(set) var currentPairText: String = ""
    @Published private(set) var failureMessage: String?
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var availableStorageGB: Double = 0
    @Published private(set) var effectiveModeAfterStorageCheck: Mode = .minimal

    // MARK: - Settings

    /// v13.7：使用者選擇的下載量級。預設 .minimal（保守、不影響低容量機種）
    @AppStorage("bootstrapMode") private var bootstrapModeRaw: String = Mode.minimal.rawValue
    var bootstrapMode: Mode {
        get { Mode(rawValue: bootstrapModeRaw) ?? .minimal }
        set { bootstrapModeRaw = newValue.rawValue }
    }

    // MARK: - Private

    private var hasStarted = false

    // MARK: - Constants

    /// 低於這個閾值（GB）就把 mode 降級為 minimal
    private static let degradeThresholdGB: Double = 3.0
    /// 低於這個閾值（GB）就完全跳過 bootstrap
    private static let abortThresholdGB: Double = 1.0

    // MARK: - Public API

    func runIfNeeded(mtService: AppleMTService?) async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let mt = mtService else { phaseTag = 0; return }

        // v13.7：先檢查可用儲存空間，必要時降級 mode
        availableStorageGB = Self.queryAvailableStorageGB()
        let userMode = bootstrapMode
        let mode = Self.adjustModeForStorage(userMode: userMode, availableGB: availableStorageGB)
        effectiveModeAfterStorageCheck = mode

        if mode == .off {
            // 完全跳過（使用者選了 off、或空間不足 1GB 強制中止）
            if availableStorageGB < Self.abortThresholdGB && userMode != .off {
                phaseTag = 5   // lowStorage banner
            } else {
                phaseTag = 0
            }
            return
        }

        // 第一階段：掃描配對找出未下載
        phaseTag = 1
        let pairsToCheck = Self.pairs(for: mode)
        var missing: [LanguagePair] = []
        for pair in pairsToCheck {
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
        completedCount = 0
        totalCount = missing.count
        phaseTag = 2

        for (idx, pair) in missing.enumerated() {
            if isPaused { return }
            currentPairText = "\(pair.source.displayName) → \(pair.target.displayName)"
            do {
                try await mt.downloadLanguagePack(for: pair)
                mt.invalidateLanguagePackStatusCache()
            } catch is CancellationError {
                // 使用者取消單一語言 → 跳過
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

    func pause() {
        isPaused = true
        if phaseTag != 4 && phaseTag != 5 { phaseTag = 0 }
    }

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
    var hasFailed: Bool { phaseTag == 4 }
    var isLowStorageWarning: Bool { phaseTag == 5 }

    var bannerMessage: String? {
        switch phaseTag {
        case 1:  return "檢查語言包：\(currentPairText)"
        case 2:  return "自動下載中：\(currentPairText)"
        case 4:  return failureMessage
        case 5:  return String(format: "儲存空間不足（剩餘 %.1f GB），已暫停自動下載。可手動到「語言包」頁逐個下載。", availableStorageGB)
        default: return nil
        }
    }

    // MARK: - Pair lists per mode

    static func pairs(for mode: Mode) -> [LanguagePair] {
        switch mode {
        case .off:
            return []
        case .minimal:
            return [
                .init(source: .traditionalChinese, target: .english),
                .init(source: .english,            target: .traditionalChinese)
            ]
        case .tier1:
            return tier1Pairs
        case .full:
            return LanguagePair.supported
        }
    }

    /// v13.6：Tier 1 = 「繁中為錨點」的雙向配對 = 26 對 ≈ 2GB
    static var tier1Pairs: [LanguagePair] {
        let anchor: Language = .traditionalChinese
        var pairs: [LanguagePair] = []
        for other in Language.allCases where other != anchor {
            pairs.append(.init(source: anchor, target: other))
            pairs.append(.init(source: other, target: anchor))
        }
        return pairs
    }

    // MARK: - Storage helpers

    /// 查詢使用者裝置可用空間（GB）
    static func queryAvailableStorageGB() -> Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let bytes = values.volumeAvailableCapacityForImportantUsage {
                return Double(bytes) / 1_073_741_824.0  // 1 GiB
            }
        } catch {
            #if DEBUG
            print("⚠️ Storage query failed: \(error)")
            #endif
        }
        return 999  // 查不到就當很多空間
    }

    /// v13.7：根據可用空間 + 使用者 mode 決定實際要跑的 mode
    static func adjustModeForStorage(userMode: Mode, availableGB: Double) -> Mode {
        // 使用者選 off 永遠尊重
        if userMode == .off { return .off }

        // 空間 < 1GB：強制 off（即使使用者要 full）
        if availableGB < abortThresholdGB { return .off }

        // 空間 < 3GB：降級到 minimal（即使使用者要 tier1 / full）
        if availableGB < degradeThresholdGB && (userMode == .tier1 || userMode == .full) {
            return .minimal
        }

        // 否則尊重使用者選擇
        return userMode
    }
}
