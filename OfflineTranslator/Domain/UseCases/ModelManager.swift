import Foundation

/// 語言包（Apple Translation 的 on-device model）狀態。
enum LanguagePackStatus: Equatable, Hashable {
    /// 從未下載
    case notDownloaded
    /// 下載中（progress 0.0–1.0）
    case downloading(progress: Double)
    /// 已下載完成
    case ready
    /// 下載失敗
    case failed(message: String)
}

/// 語言包管理 Use Case 介面
/// 注意：MVP 範圍僅處理 Apple Translation 的語言包，
/// 不維護自家 CDN / Core ML 模型。
protocol ModelManager {
    /// 列出 MVP 支援的所有語言對及其當前狀態。
    func status(for pair: LanguagePair) async -> LanguagePackStatus

    /// 觸發下載（背後會打開 Apple 系統 sheet）。
    func download(pair: LanguagePair) async throws

    /// 從本機刪除（如果系統 API 允許）。
    func remove(pair: LanguagePair) async throws

    /// 預估容量（MB），純粹給 UI 顯示，可以是估值。
    func estimatedSize(for pair: LanguagePair) -> Int
}

/// MVP 預估（Apple 沒有公開精確值；之後實測再校正）
struct DefaultModelManager: ModelManager {
    let mtService: MTService

    func status(for pair: LanguagePair) async -> LanguagePackStatus {
        do {
            return try await mtService.languagePackStatus(for: pair)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func download(pair: LanguagePair) async throws {
        try await mtService.downloadLanguagePack(for: pair)
    }

    func remove(pair: LanguagePair) async throws {
        try await mtService.removeLanguagePack(for: pair)
    }

    func estimatedSize(for pair: LanguagePair) -> Int {
        // 粗估：每對 ~80MB；之後從實機測試結果校正。
        80
    }
}
