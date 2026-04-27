import Foundation
import SwiftUI

/// 語言包預下載器（v1.2.1）
///
/// 動機：Apple Translation framework 的語言包是「每個翻譯方向各下載一次」
/// 的設計（zh-Hant→en 與 en→zh-Hant 是兩個獨立檔案），首次下載每個方向
/// 約 1-3 分鐘。如果使用者進入文字翻譯才被動觸發下載，他們會以為 App 壞了。
///
/// 這個 bootstrap 在 RootView 出現時就背景下載**兩個方向**的語言包，
/// 並對外提供 `phase` 讓 UI 顯示橫幅進度條。
///
/// 重要：這個類別必須由 `RootView` 持有並掛上 `.appleTranslationBridge(...)`
/// modifier，否則 `mt.downloadLanguagePack(for:)` 內部會卡在 bridge 等待。
@MainActor
final class LanguagePackBootstrap: ObservableObject {

    enum Phase: Equatable {
        case idle
        case checking(pair: LanguagePair)
        case downloading(pair: LanguagePair)
        case done
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = LanguagePair.supported.count

    /// 標記是否已啟動過，避免 RootView 重複進入時重跑
    private var hasStarted = false

    /// 主入口：檢查 + 下載兩個方向。若已下載過則跳過。
    /// 失敗不會 throw，會用 `phase = .failed(...)` 表達，UI 應顯示重試。
    func runIfNeeded(mtService: AppleMTService?) async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let mt = mtService else {
            phase = .idle
            return
        }

        completedCount = 0

        for pair in LanguagePair.supported {
            // Step 1: 檢查狀態
            phase = .checking(pair: pair)
            let status: LanguagePackStatus
            do {
                status = try await mt.languagePackStatus(for: pair)
            } catch {
                phase = .failed(message: "檢查語言包狀態失敗：\(localized(error))")
                return
            }

            if status == .ready {
                completedCount += 1
                continue
            }

            // Step 2: 下載
            phase = .downloading(pair: pair)
            do {
                try await mt.downloadLanguagePack(for: pair)
            } catch {
                // CancellationError 通常是使用者剛剛在 UI 觸發了翻譯導致 bridge 接力。
                // 此時把這個 pair 當作完成，後面真正翻譯時會再觸發一次 prepare。
                if (error as NSError).domain == "Swift.CancellationError"
                    || error is CancellationError {
                    completedCount += 1
                    continue
                }
                phase = .failed(message: "下載語言包失敗：\(localized(error))")
                return
            }
            completedCount += 1
        }

        phase = .done
    }

    /// 手動重試（使用者點 banner 上的「重試」）
    func retry(mtService: AppleMTService?) async {
        hasStarted = false
        phase = .idle
        await runIfNeeded(mtService: mtService)
    }

    // MARK: - Derived

    var isWorking: Bool {
        switch phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    /// 給 banner 顯示的文字（中文使用者導向）
    var bannerMessage: String? {
        switch phase {
        case .idle, .done:
            return nil
        case .checking(let pair):
            return "正在檢查語言包：\(pair.source.displayName) → \(pair.target.displayName)"
        case .downloading(let pair):
            return "首次下載語言包中：\(pair.source.displayName) → \(pair.target.displayName)（約需 1-3 分鐘）"
        case .failed(let msg):
            return msg
        }
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    // MARK: - Helpers

    private func localized(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
