import Foundation

/// 文字轉語音（TTS）服務介面。
protocol TTSService {
    /// 朗讀指定文字。
    func speak(text: String, language: Language) async throws
    /// 立刻停止朗讀。
    func stop()
}
