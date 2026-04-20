import Foundation

/// 自動語音辨識（ASR）服務介面。
protocol ASRService {
    /// 開始辨識，回傳逐步更新的辨識文字。
    /// - Note: 串流過程中 ViewModel 應該邊收邊顯示 partial transcript。
    func startRecognition(in language: Language) -> AsyncThrowingStream<String, Error>

    /// 結束辨識，回傳最終文字。
    func stopRecognition() async throws -> String

    /// 確認是否支援某語言（on-device 與否）。
    func isSupported(for language: Language) -> Bool
}

enum ASRError: LocalizedError {
    case permissionDenied
    case notSupported
    case audioEngineFailed(Error)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:       return "尚未允許麥克風或語音辨識權限，請到設定開啟。"
        case .notSupported:           return "這個語言目前不支援語音辨識。"
        case .audioEngineFailed(let e): return "錄音失敗：\(e.localizedDescription)"
        case .underlying(let e):      return e.localizedDescription
        }
    }
}
