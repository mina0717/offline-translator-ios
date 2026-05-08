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

    /// v1.3.0：當前下載的開始時間（用來計算已耗時、顯示給使用者）。
    @Published var downloadStartedAt: Date?
    /// v1.3.0：每秒更新一次的 elapsed 顯示用值。
    @Published var elapsedSeconds: Int = 0
    private var elapsedTimerTask: Task<Void, Never>?

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
        // v1.3.0：開計時器、給使用者「真的有在下載」的視覺回饋
        downloadStartedAt = Date()
        elapsedSeconds = 0
        startElapsedTimer()
        defer {
            downloadingPair = nil
            stopElapsedTimer()
        }

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

    /// v1.3.0：每秒更新 elapsedSeconds 讓 UI 顯示「下載中 (12s)」這類資訊
    private func startElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let started = self.downloadStartedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(started))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
        downloadStartedAt = nil
        elapsedSeconds = 0
    }

    /// v1.3.0：批次下載多對語言包（給「一鍵下載 4 國」按鈕用）。
    /// 一次只能跑一個下載（Apple 系統 sheet 限制），所以序列執行。
    func downloadBatch(_ pairs: [LanguagePair]) async {
        for pair in pairs {
            // 已下載的跳過
            if let info = packs.first(where: { $0.pair == pair }), info.status == .ready {
                continue
            }
            await download(pair)
            // 中途出錯就停（errorMessage 會被設）
            if errorMessage != nil { return }
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
