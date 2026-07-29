import Foundation
import AVFoundation

/// v1.5.0：語音活動偵測（VAD）。
///
/// 免持模式沒有「手指放開」這個訊號，所以要靠**靜音**來判斷一句話講完了。
/// 這支就是取代手指的那塊。
///
/// 做法：
/// 1. 每個 audio buffer 算 RMS → 轉 dBFS
/// 2. 用「近期最安靜的音量」動態估環境噪音底（不同場合噪音差很多，固定門檻會失準）
/// 3. 音量高過噪音底 + margin → 判定為說話
/// 4. 說話後持續靜音超過 `silenceToEndSeconds` → 判定這句結束
///
/// 為什麼要動態噪音底：咖啡廳跟安靜房間的背景音量可以差 20dB 以上。
/// 固定門檻在吵的地方會一直誤判成在說話，在安靜的地方又會漏掉小聲說話。
/// - Important: 執行緒約定 —— `process()` / `currentLevelDB` **只在 audio tap 執行緒**上使用；
///   `reset()` 只在 audio engine 未啟動時（start 前 / stop 後）由 MainActor 呼叫。
///   兩者不會同時發生，因此不需要鎖。
final class VoiceActivityDetector: @unchecked Sendable {

    enum Event: Equatable {
        /// 從靜音轉為說話
        case speechStarted
        /// 說話後靜了夠久 —— 這句話結束
        case speechEnded
        /// 沒有狀態變化
        case none
    }

    // MARK: - Tuning

    /// 高過噪音底多少 dB 才算說話。
    /// 太小會把冷氣聲當人聲，太大會漏掉小聲說話。
    private let speechMarginDB: Float
    /// 說話後要靜多久才算這句講完。
    ///
    /// 這個值是體感關鍵：
    /// - 太短（<0.5s）→ 句中換氣就被切斷，一句話被拆成好幾段
    /// - 太長（>1.5s）→ 對方講完要等很久才出譯文，感覺遲鈍
    private let silenceToEndSeconds: TimeInterval
    /// 一段語音至少要多長才算數，濾掉咳嗽、關門聲之類的短促噪音
    private let minSpeechSeconds: TimeInterval

    // MARK: - State

    /// 環境噪音底（dBFS），持續向上緩慢適應、向下快速適應
    private var noiseFloorDB: Float = -50
    private var isSpeaking = false
    private var speechStartedAt: Date?
    private var lastVoiceAt: Date?
    /// 還沒收集到足夠樣本前不做判斷，避免一開場就誤判
    private var warmupBuffers = 0

    init(speechMarginDB: Float = 10,
         silenceToEndSeconds: TimeInterval = 0.8,
         minSpeechSeconds: TimeInterval = 0.3) {
        self.speechMarginDB = speechMarginDB
        self.silenceToEndSeconds = silenceToEndSeconds
        self.minSpeechSeconds = minSpeechSeconds
    }

    /// 目前音量（dBFS），給 UI 畫音量指示用
    private(set) var currentLevelDB: Float = -100

    func reset() {
        noiseFloorDB = -50
        isSpeaking = false
        speechStartedAt = nil
        lastVoiceAt = nil
        warmupBuffers = 0
        currentLevelDB = -100
    }

    /// 餵一個 audio buffer，回傳狀態變化。
    /// - Note: 這支會在 audio tap 的執行緒上被高頻呼叫，必須輕量、不可阻塞。
    func process(buffer: AVAudioPCMBuffer, now: Date = Date()) -> Event {
        let level = Self.rmsDB(of: buffer)
        currentLevelDB = level

        // 前幾個 buffer 只拿來估噪音底
        if warmupBuffers < Self.warmupBufferCount {
            warmupBuffers += 1
            noiseFloorDB = min(noiseFloorDB, level)
            return .none
        }

        // 噪音底適應：安靜時快速下修、吵雜時緩慢上修。
        // 不對稱是刻意的 —— 人聲會把平均值拉高，若上修太快會把人聲本身當成噪音底。
        if level < noiseFloorDB {
            noiseFloorDB = level
        } else {
            noiseFloorDB += (level - noiseFloorDB) * Self.noiseFloorRiseRate
        }

        let isVoice = level > noiseFloorDB + speechMarginDB

        if isVoice {
            lastVoiceAt = now
            if !isSpeaking {
                isSpeaking = true
                speechStartedAt = now
                return .speechStarted
            }
            return .none
        }

        // 靜音中：檢查是否已經靜夠久，可以斷句
        guard isSpeaking, let lastVoice = lastVoiceAt else { return .none }
        guard now.timeIntervalSince(lastVoice) >= silenceToEndSeconds else { return .none }

        let duration = now.timeIntervalSince(speechStartedAt ?? lastVoice)
        isSpeaking = false
        speechStartedAt = nil

        // 太短的「說話」是噪音，不當成一句話
        guard duration >= minSpeechSeconds else { return .none }
        return .speechEnded
    }

    // MARK: - Helpers

    private static let warmupBufferCount = 8
    /// 噪音底上修速率（每個 buffer 逼近多少比例）
    private static let noiseFloorRiseRate: Float = 0.002

    /// 算 buffer 的 RMS 並轉成 dBFS。靜音回 -100。
    static func rmsDB(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -100 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -100 }

        // 只取第一個聲道就夠了（辨識用的是單聲道）
        let samples = channelData[0]
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let s = samples[i]
            sumSquares += s * s
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        guard rms > 0 else { return -100 }
        return max(-100, 20 * log10(rms))
    }
}
