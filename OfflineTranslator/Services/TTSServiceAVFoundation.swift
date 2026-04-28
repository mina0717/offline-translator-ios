import Foundation
import AVFoundation

/// AVSpeechSynthesizer 的真實作。
/// 不需要權限，不需要網路，本機朗讀。
final class AVFoundationTTSService: NSObject, TTSService {

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    /// v1.2.2：避免 didFinish 與 timeout 同時觸發造成 continuation double-resume
    private var hasResumed = false

    /// v1.2.2：TTS 安全上限（秒）。一段譯文最長唸 30 秒，超過視為卡死自動 resume。
    private static let speakTimeout: UInt64 = 30_000_000_000

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, language: Language) async throws {
        // v1.2.2：空字串直接 return，不開 continuation
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 確保前一段先停掉
        stop()

        // v1.2.5 critical fix：強制把 audio session 切到 .playback
        // 之前對話 / 語音翻譯先跑 ASR 把 session 設成 .record，
        // 結束後雖然 setActive(false) 但 category 沒變回 playback，
        // 導致使用者按喇叭圖示沒聲音（AVSpeechSynthesizer 在 .record 上不發聲）
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            #if DEBUG
            print("⚠️ TTS audio session setup failed: \(error)")
            #endif
            // 不擋朗讀：即使切換失敗，先試著直接 speak（某些情境 iOS 自己會處理）
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language.bcp47)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.hasResumed = false
            // v1.2.2：加 timeout，避免 didFinish/didCancel 都沒觸發時永遠 hang
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.speakTimeout)
                self?.resumeIfNeeded()
            }
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resumeIfNeeded()
    }

    /// v1.2.2：集中 resume 邏輯，保證 continuation 只會 resume 一次
    private func resumeIfNeeded() {
        guard !hasResumed, let cont = continuation else {
            continuation = nil
            return
        }
        hasResumed = true
        continuation = nil
        cont.resume()
    }
}

extension AVFoundationTTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        timeoutTask?.cancel()
        timeoutTask = nil
        resumeIfNeeded()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        timeoutTask?.cancel()
        timeoutTask = nil
        resumeIfNeeded()
    }
}
