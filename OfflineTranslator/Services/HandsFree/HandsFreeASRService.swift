import Foundation
import AVFoundation

/// v1.5.0：免持連續語音辨識服務。
///
/// 與既有 `ASRService`（按住說話）的差別：
/// - `ASRService`：手指按下 → 開始，放開 → 結束。**一次一句**。
/// - 這支：開一次麥克風就**持續聽**，靠靜音自動斷句，一句一句吐出來。
///
/// 刻意做成獨立服務而不是改 `ASRService` —— 那條已上架且穩定，
/// 不該為了新功能去動它的生命週期。
@MainActor
protocol HandsFreeASRService: AnyObject {

    /// 事件串流。**每次 `start()` 都會重建**，見實作說明。
    var events: AsyncStream<HandsFreeASREvent> { get }

    /// 開始持續聆聽。呼叫端需先確認麥克風與語音辨識權限。
    func start(language: Language) async throws

    /// 停止聆聽並釋放音訊資源。
    func stop()

    /// 該語言是否支援**離線**辨識。
    /// 免持模式會連續聽很久，若走雲端既違背離線承諾又耗流量，所以要先擋。
    func supportsOnDevice(_ language: Language) -> Bool
}

/// 免持辨識過程中的事件
enum HandsFreeASREvent: Equatable {
    /// 辨識中的即時文字（會不斷更新，尚未定案）
    case partial(String)
    /// 一句話講完了 —— 這是最終文字，可以送翻譯
    case finalized(String)
    /// 目前音量（dBFS），給 UI 畫音量指示
    case level(Float)
    /// 偵測到開始說話（UI 可以亮起「聆聽中」）
    case speechStarted
    /// 發生錯誤但服務仍在跑（例如某一輪辨識失敗，下一輪會自動重來）
    case recoverableError(String)
}

/// 免持模式可能的錯誤
enum HandsFreeASRError: LocalizedError {
    case permissionDenied
    case notSupportedOffline(Language)
    case audioEngineFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "handsfree.error.permission")
        case .notSupportedOffline(let lang):
            return String(
                format: String(localized: "handsfree.error.no_offline_asr"),
                lang.displayName
            )
        case .audioEngineFailed(let detail):
            return String(localized: "handsfree.error.audio_failed") + "\n" + detail
        }
    }
}
