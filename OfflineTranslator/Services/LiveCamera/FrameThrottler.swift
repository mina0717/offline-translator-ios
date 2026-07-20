import Foundation

/// v1.4.0：相機影格節流器。
///
/// 相機以 30–60 fps 吐 frame，但 OCR + 翻譯每秒跑 5 次就足夠「即時」的感受，
/// 而且能把 CPU / 發熱壓在可接受範圍。這個 class 決定「這一幀要不要進 pipeline」。
///
/// 兩個節流來源：
/// 1. `targetFPS` — 基礎頻率（預設 5）
/// 2. `thermalState` — 裝置發燙時自動降頻（v15 規劃新增的防護）
///
/// Thread-safety：`shouldProcess()` 會被 AVCapture 的 video queue 呼叫，
/// 用 `os_unfair_lock` 保護內部時間戳。
final class FrameThrottler: @unchecked Sendable {

    /// 一般狀態下的目標頻率
    private let baseFPS: Double
    /// 發燙時降到這個頻率
    private let throttledFPS: Double

    private var lastProcessedAt: TimeInterval = 0
    private let lock = NSLock()

    /// 由外部（ViewModel 監聽 thermalState）更新
    private var isThermallyThrottled = false

    init(targetFPS: Double = 5, throttledFPS: Double = 2) {
        self.baseFPS = targetFPS
        self.throttledFPS = throttledFPS
    }

    /// 目前實際生效的 fps（UI 可顯示、debug 用）
    var currentFPS: Double {
        lock.lock(); defer { lock.unlock() }
        return isThermallyThrottled ? throttledFPS : baseFPS
    }

    /// 發燙降頻開關。`.serious` / `.critical` 時由 ViewModel 打開。
    func setThermallyThrottled(_ throttled: Bool) {
        lock.lock(); defer { lock.unlock() }
        isThermallyThrottled = throttled
    }

    /// 這一幀是否該進入 OCR pipeline。呼叫端在 capture delegate 裡用。
    func shouldProcess(now: TimeInterval = CACurrentMediaTimeShim()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let fps = isThermallyThrottled ? throttledFPS : baseFPS
        let minInterval = 1.0 / fps
        guard now - lastProcessedAt >= minInterval else { return false }
        lastProcessedAt = now
        return true
    }

    /// 重置（切換語言 / 重新啟動 session 時用）
    func reset() {
        lock.lock(); defer { lock.unlock() }
        lastProcessedAt = 0
    }
}

/// `CACurrentMediaTime()` 需要 QuartzCore；抽成 shim 方便單元測試注入假時間。
func CACurrentMediaTimeShim() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}
