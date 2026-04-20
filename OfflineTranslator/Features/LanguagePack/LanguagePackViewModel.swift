import Foundation
import SwiftUI
import UIKit

/// 語言包管理 ViewModel。
///
/// 關鍵設計：
///   1. Apple Translation **沒有提供靜默下載 API**。
///      `download(pair:)` 背後會觸發系統 sheet；
///      使用者可能取消 → 我們不把它當失敗（CancellationError 靜默忽略）。
///   2. Apple Translation **沒有提供刪除 API**。
///      `remove(pair:)` 一定會拋錯；我們改成提示
///      「請到設定 → 一般 → 語言與地區 → 翻譯」並給一顆「打開設定」按鈕。
@MainActor
final class LanguagePackViewModel: ObservableObject {

    // MARK: - Published state

    @Published var packs: [LanguagePackInfo] = []
    @Published var isLoading: Bool = false
    /// 哪一個 pair 正在下載（UI 用來顯示 ProgressView）
    @Published var downloadingPair: LanguagePair?

    /// 一般錯誤訊息（會顯示紅色 banner）
    @Published var errorMessage: String?
    /// 需要引導使用者到「設定」的提示（刪除語言包時）
    @Published var settingsHint: String?

    // MARK: - Deps

    private let repository: LanguagePackRepository

    init(repository: LanguagePackRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        packs = await repository.list()
    }

    func download(_ pair: LanguagePair) async {
        guard downloadingPair == nil else { return }
        errorMessage = nil
        downloadingPair = pair
        defer { downloadingPair = nil }

        do {
            try await repository.download(pair: pair)
            await reload()
        } catch is CancellationError {
            // 使用者在系統 sheet 按取消 → 不當錯誤
            await reload()
        } catch {
            // 有些錯其實是 CancellationError 被包過；用字串判斷兜底
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if msg.localizedCaseInsensitiveContains("cancel") {
                await reload()
            } else {
                errorMessage = msg
            }
        }
    }

    func remove(_ pair: LanguagePair) async {
        errorMessage = nil
        do {
            try await repository.remove(pair: pair)
            await reload()
        } catch {
            // Apple 不讓 App 刪語言包 → 引導到設定
            settingsHint = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// 打開 iOS「設定」App（用於刪除語言包提示）
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func dismissSettingsHint() { settingsHint = nil }
    func dismissError() { errorMessage = nil }
}
