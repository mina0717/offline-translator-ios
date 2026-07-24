import Foundation
import AVFoundation
import UIKit

/// v1.4.0 hotfix6：按下快門後的單張結果。
///
/// 即時模式為了跟上畫面必須節流 + 用較保守的門檻，精度一定有妥協；
/// 按下快門凍結之後就沒有時間壓力了 —— 可以用更低的最小字高、
/// 把整批文字全部翻完，而且畫面不再變動，使用者能好好讀。
struct StillCapture {
    /// 凍結的畫面（已套用與即時預覽相同的方向，疊層座標因此完全共用）
    let image: UIImage
    let regions: [RecognizedTextRegion]
}

/// v1.4.0：即時鏡頭翻譯服務介面。
///
/// 設計沿用 v1.2.0 設計文件（2026-04-27）：
/// View 只認這個 protocol，真實作走 AVFoundation + Vision，Preview / 測試走 Mock。
///
/// 生命週期：`start()` → 訂閱 `regionStream` → `stop()`
@MainActor
protocol LiveCameraTranslationService: AnyObject {

    /// 給 `CameraPreviewLayer` 用的 capture session。
    /// Mock 實作回傳 nil（Preview 沒有相機）。
    var captureSession: AVCaptureSession? { get }

    /// 辨識 + 翻譯結果串流。每次節流通過的影格會 emit 一次完整的 region 陣列。
    var regionStream: AsyncStream<[RecognizedTextRegion]> { get }

    /// 啟動 capture（呼叫端需先確認相機權限）。
    func start() async throws

    /// v1.4.0 hotfix6：按下快門 —— 凍結當前影格，做一次**不節流的高品質**辨識 + 完整翻譯。
    /// 這條路徑不受 `setPaused` 影響（暫停時也拍得到）。
    func captureStill() async throws -> StillCapture

    /// 停止 capture 並釋放資源。
    func stop()

    /// 切換翻譯語言對。會清空快取（舊譯文對新方向無效）。
    func setLanguagePair(_ pair: LanguagePair) async

    /// 暫停 / 恢復 OCR（畫面仍然是活的，只是不再辨識）。
    func setPaused(_ paused: Bool)

    /// 發燙降頻開關，由 ViewModel 監聽 `ProcessInfo.thermalState` 後呼叫。
    func setThermallyThrottled(_ throttled: Bool)
}

/// 即時鏡頭翻譯可能的錯誤。
enum LiveCameraError: LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case configurationFailed(String)
    /// v1.4.0 hotfix：啟動看門狗逾時。避免使用者被卡在「翻譯引擎啟動中」無限等待。
    case startTimeout
    /// v1.4.0 hotfix3：單筆翻譯逾時。沒有它，一次卡住的 bridge 請求就會讓整條 pipeline 停擺。
    case translateTimeout

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return String(localized: "live.error.camera_unavailable")
        case .permissionDenied:
            return String(localized: "live.error.permission_denied")
        case .configurationFailed(let detail):
            return String(localized: "live.error.config_failed") + "\n" + detail
        case .startTimeout:
            return String(localized: "live.error.start_timeout")
        case .translateTimeout:
            return String(localized: "live.error.translate_timeout")
        }
    }
}
