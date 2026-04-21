import Foundation
import Combine

/// v1.1 fix (Codex review)：AppIntents → App 的 request queue。
///
/// 為什麼需要這個？
///   `AppleMTService.translate` 需要 SwiftUI View tree 上的 `.translationTask`
///   modifier 來實際執行翻譯（由 `RootView.appleTranslationBridge(...)` 掛載）。
///   AppIntents 在 View tree **之外**執行，直接 `await service.translate(...)` 會
///   永遠無法 resume，Siri shortcut 會卡住直到 timeout。
///
/// 解法：
///   Intent 把請求寫進這個 shared store → 設 `openAppWhenRun = true` 把 App 拉到前景
///   → `RootView.onReceive(store.$queue)` 消費 queue 首筆 → 走 ViewModel 正常翻譯流程
///   → UI 顯示結果。
///
/// ## v1.1.1 fix：單 slot → FIFO queue
/// 先前 `pending` 是單一 slot，如果使用者快速連按兩個 Shortcut（或 Siri 連發），
/// 後到的 submit 會覆蓋掉還沒被 View 消費的前一筆，導致第一個請求默默被丟棄。
/// 改用 FIFO queue 確保每一筆都被看到；View 端每次 dequeue 一筆處理完再拿下一筆。
///
/// 這個 store 刻意放在主 app process（跟 AppIntents 同 process）用單例即可；
/// Share Extension 另外有自己的流程，不經過這裡。
@MainActor
final class IntentRequestStore: ObservableObject {
    static let shared = IntentRequestStore()

    /// AppIntents 可能發出的請求種類。
    enum Request: Equatable {
        /// 翻譯一段傳進來的文字
        case translateText(text: String, target: Language)
        /// 翻譯剪貼簿當下的內容
        case translateClipboard(target: Language)
    }

    /// FIFO queue。View 層觀察 `$queue` 並在非空時 `consume()` 首筆。
    @Published private(set) var queue: [Request] = []

    /// 方便 View 用「首筆是否存在」觸發導航的 helper。
    var nextPending: Request? { queue.first }

    private init() {}

    // MARK: - AppIntent 端寫入

    func submit(_ request: Request) {
        queue.append(request)
    }

    // MARK: - View 端消費

    /// 取出並移除 queue 首筆。只應該由 View tree 呼叫（拿到後就要去執行翻譯）。
    @discardableResult
    func consume() -> Request? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    /// 一次取走所有 pending 請求並清空 queue（單一 @Published 更新，避免 View
    /// 端 onReceive 在 for-loop 中反覆 reentrant 觸發）。
    func drainAll() -> [Request] {
        let snapshot = queue
        queue = []
        return snapshot
    }
}
