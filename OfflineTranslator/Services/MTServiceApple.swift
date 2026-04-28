import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

// MARK: - ─────────────────────────────────────────────────────────────
// MARK: Apple Translation framework 的真實作（雙版草稿）
// MARK: ─────────────────────────────────────────────────────────────
//
// 撰寫日：2026-04-20（Windows 端草稿，待 Mac 實測）
//
// 【背景：為什麼需要 A/B 兩版】
// Apple Translation framework（iOS 17.4+）的 API 幾乎完全圍繞 SwiftUI。
// 核心物件 `TranslationSession` 沒有公開建構子，只能透過 View 的
// `.translationTask(_:action:)` modifier 由系統注入。這造成 protocol-based
// Service 層要呼叫翻譯時有兩條路線：
//
// ┌─────────┬────────────────────────────────────┬──────────────────────┐
// │ 版本    │ 做法                               │ 適合情境             │
// ├─────────┼────────────────────────────────────┼──────────────────────┤
// │ A（推）│ View 持有 session、用 bridge actor  │ 主推路徑，行為穩     │
// │         │ 把 translate 請求與結果橋接        │ 下載 sheet 自動顯示  │
// │ B（備）│ Service 只做 LanguageAvailability  │ 想完全脫鉤 Service   │
// │         │ 檢查；翻譯交由 View 層 modifier    │ 但 session 要手寫   │
// │         │ 直接執行                            │ holder、time-out    │
// └─────────┴────────────────────────────────────┴──────────────────────┘
//
// 【Mac 實測檢查表】（借到 Mac 的「借機日 1」第 1 小時照這個順序跑）
//   □ 1. import Translation 能編譯（需 Xcode 15.3+ / iOS 17.4+ SDK）
//   □ 2. `LanguageAvailability().status(from:to:)` 能跑、回傳合理狀態
//   □ 3. A 版：`.translationTask(_:action:)` 能在 TextTranslationView 掛上
//   □ 4. A 版：`session.translate("你好")` 回傳繁中→英譯文
//   □ 5. 把語言包手動刪光後 `session.prepareTranslation()` 會跳系統 sheet
//   □ 6. 同時 prepareTranslation 兩次會不會壞？→ 加 debounce
//   □ 7. App 背景化時 session 失效？→ 決定要不要重建
//   □ 8. 同一個 TranslationSession 能翻不同字串嗎？還是一次性？
//   □ 9. removeLanguagePack：Apple 沒提供 API，驗證只能引導使用者到系統設定
//   □ 10. error case：未連網（Apple Translation 是離線，不受影響）
//   □ 11. error case：使用者拒絕下載語言包 → throw `.modelNotAvailable`
//
// 【API 參考（2026-04 iOS 17.4+ SDK）】
//   - Translation.TranslationSession
//       沒有 public init；只能從 .translationTask action closure 拿到
//   - Translation.TranslationSession.Configuration
//       init(source: Locale.Language?, target: Locale.Language?)
//   - session.translate(_:)  →  TranslationSession.Response.targetText
//   - session.translations(from:)  →  批次
//   - session.prepareTranslation()   →  觸發系統下載 sheet（可等待）
//   - Translation.LanguageAvailability
//       status(from:to:) async → .installed | .supported | .unsupported
//   - View.translationTask(_:action:) modifier
//   - View.translationPresentation(...)  系統 UI（我們沒用）
//
// ─────────────────────────────────────────────────────────────

/// Apple Translation framework 的真實作入口。
///
/// 實際翻譯動作由 View 端掛載的 `.translationTask` 執行，
/// Service 透過 `AppleTranslationBridge`（actor）橋接非 UI 的呼叫端。
@MainActor
final class AppleMTService: MTService {

    // 單例 bridge，View 端與 Service 層共用同一個 session pipeline
    let bridge = AppleTranslationBridge()

    // v1.2.2：語言包狀態快取。每次翻譯都呼叫 LanguageAvailability().status(...)
    // 是 100-300ms 的 Apple framework 同步呼叫，1 分鐘內快取，避免重複付費。
    private struct StatusCacheEntry {
        let status: LanguagePackStatus
        let timestamp: Date
    }
    private var statusCache: [String: StatusCacheEntry] = [:]
    private static let statusCacheTTL: TimeInterval = 60

    /// v1.2.2：bootstrap / 下載完成時可手動清快取，下一次 translate 會重新檢查。
    func invalidateLanguagePackStatusCache() {
        statusCache.removeAll()
    }

    // MARK: MTService.translate

    func translate(text: String, pair: LanguagePair) async throws -> String {
        #if canImport(Translation)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }
        guard pair.isSupported else { throw TranslationError.unsupportedPair }

        // 先確認語言包已下載。未下載 → 拋 modelNotAvailable，
        // UI 會導使用者去「語言包管理」或直接觸發下載 sheet。
        let status = try await languagePackStatus(for: pair)
        if status != .ready {
            throw TranslationError.modelNotAvailable
        }

        // 把 request 交給 bridge，等 View 的 .translationTask 回填結果。
        return try await bridge.requestTranslation(text: trimmed, pair: pair)
        #else
        throw TranslationError.underlying(NSError(
            domain: "AppleMTService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Apple 翻譯框架不可用（需要 iOS 17.4 以上）"]
        ))
        #endif
    }

    // MARK: MTService.languagePackStatus

    func languagePackStatus(for pair: LanguagePair) async throws -> LanguagePackStatus {
        #if canImport(Translation)
        guard pair.isSupported else { return .notDownloaded }

        // v1.2.2：先查快取。.ready 狀態用 60s TTL（不太可能突然消失）；
        // 其他狀態不快取，讓使用者下載完語言包後立刻反映。
        let key = "\(pair.source.bcp47)→\(pair.target.bcp47)"
        if let cached = statusCache[key],
           cached.status == .ready,
           Date().timeIntervalSince(cached.timestamp) < Self.statusCacheTTL {
            return cached.status
        }

        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: pair.source.bcp47),
            to:   Locale.Language(identifier: pair.target.bcp47)
        )
        let mapped: LanguagePackStatus
        switch status {
        case .installed:   mapped = .ready
        case .supported:   mapped = .notDownloaded
        case .unsupported: mapped = .failed(message: "Apple 翻譯尚不支援 \(pair.source.displayName) → \(pair.target.displayName)")
        @unknown default:  mapped = .notDownloaded
        }
        if mapped == .ready {
            statusCache[key] = .init(status: mapped, timestamp: Date())
        } else {
            statusCache.removeValue(forKey: key)
        }
        return mapped
        #else
        return .notDownloaded
        #endif
    }

    // MARK: MTService.downloadLanguagePack

    func downloadLanguagePack(for pair: LanguagePair) async throws {
        #if canImport(Translation)
        // Apple Translation 沒有靜默下載 API，必須由 session.prepareTranslation()
        // 觸發系統 sheet；所以這裡把請求丟到 bridge，由 View 的 .translationTask
        // 當 session 可用時呼叫 prepareTranslation()。
        try await bridge.requestPrepare(pair: pair)
        #else
        throw TranslationError.underlying(NSError(
            domain: "AppleMTService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Translation framework 不可用（需 iOS 17.4+）"]
        ))
        #endif
    }

    // MARK: MTService.removeLanguagePack

    func removeLanguagePack(for pair: LanguagePair) async throws {
        // Apple Translation **不提供程式刪除單一語言包的 API**（經 Apple Docs 2026-04 確認）
        // MVP 做法：UI 顯示「請到 設定 → 一般 → 語言與地區 → 翻譯 → 已下載語言 刪除」
        // 這個函式存在只是為了讓 protocol 完整；直接拋錯讓 UI 顯示提示。
        throw TranslationError.underlying(NSError(
            domain: "AppleMTService",
            code: -10,
            userInfo: [NSLocalizedDescriptionKey:
                "Apple 不允許 App 直接刪除語言包，請到「設定 → 一般 → 語言與地區 → 翻譯」手動刪除。"]
        ))
    }
}

// MARK: - ─────────────────────────────────────────────────────────────
// MARK: A 版：SwiftUI bridge（主推路徑）
// MARK: ─────────────────────────────────────────────────────────────

/// Service 與 View 之間的橋接 actor。
/// 典型流程：
///   1. ViewModel → `service.translate(...)` → `bridge.requestTranslation(...)` 把 continuation 存起來
///   2. View 的 `.translationTask` 監聽 bridge 的 pending config 變化，set `session` 後執行翻譯
///   3. 拿到結果 → `bridge.finish(text:)` → continuation 解開
///
/// ⚠️ 這個 bridge **一次只處理一個 request**。若有並發需求，改成 id+dictionary。
@MainActor
@Observable
final class AppleTranslationBridge {

    // 當前等待 View 執行的翻譯請求
    struct PendingTranslation: Equatable {
        let id: UUID
        let text: String
        let source: String   // BCP-47
        let target: String
    }

    /// View 透過 `$bridge.pending` 觀察；有值就要掛 `.translationTask`
    var pending: PendingTranslation?

    /// 下載 sheet 觸發請求（語言包管理用）
    var pendingPrepare: PendingTranslation?

    // 非 UI 端的 continuation
    private var translateContinuation: CheckedContinuation<String, Error>?
    private var prepareContinuation: CheckedContinuation<Void, Error>?

    // MARK: Service 端呼叫

    func requestTranslation(text: String, pair: LanguagePair) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            // v1.2.2：先取出舊 continuation 再清，避免 finish callback 同時觸發造成 double resume
            if let old = translateContinuation {
                translateContinuation = nil
                old.resume(throwing: CancellationError())
            }
            translateContinuation = cont
            pending = .init(
                id: UUID(),
                text: text,
                source: pair.source.bcp47,
                target: pair.target.bcp47
            )
        }
    }

    func requestPrepare(pair: LanguagePair) async throws {
        try await withCheckedThrowingContinuation { cont in
            if let old = prepareContinuation {
                prepareContinuation = nil
                old.resume(throwing: CancellationError())
            }
            prepareContinuation = cont
            pendingPrepare = .init(
                id: UUID(),
                text: "",
                source: pair.source.bcp47,
                target: pair.target.bcp47
            )
        }
    }

    // MARK: View 端呼叫（由 .translationTask callback）

    /// v1.2.2：保證每個 continuation 只 resume 一次
    func finishTranslate(text: String) {
        guard let cont = translateContinuation else { pending = nil; return }
        translateContinuation = nil
        pending = nil
        cont.resume(returning: text)
    }

    func failTranslate(error: Error) {
        guard let cont = translateContinuation else { pending = nil; return }
        translateContinuation = nil
        pending = nil
        cont.resume(throwing: error)
    }

    func finishPrepare() {
        guard let cont = prepareContinuation else { pendingPrepare = nil; return }
        prepareContinuation = nil
        pendingPrepare = nil
        cont.resume(returning: ())
    }

    func failPrepare(error: Error) {
        guard let cont = prepareContinuation else { pendingPrepare = nil; return }
        prepareContinuation = nil
        pendingPrepare = nil
        cont.resume(throwing: error)
    }
}

// MARK: - View modifier：把這個掛到 RootView 上

#if canImport(Translation)
/// 在 RootView 或 TextTranslationView 上掛 `.appleTranslationBridge(bridge)`
/// 這個 modifier 會監聽 bridge.pending，必要時建 TranslationSession 並執行翻譯。
///
/// 用法（Mac 借機日時接）：
///   RootView { ... }
///     .appleTranslationBridge(deps.mtService as? AppleMTService)
struct AppleTranslationBridgeModifier: ViewModifier {
    let bridge: AppleTranslationBridge?

    @State private var currentConfig: TranslationSession.Configuration?
    // v1.2.2：記住目前 config 的 source/target，避免相同語言對重建 session
    @State private var currentSource: String?
    @State private var currentTarget: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: bridge?.pending) { _, newValue in
                guard let p = newValue else { return }
                applyConfig(source: p.source, target: p.target)
            }
            .onChange(of: bridge?.pendingPrepare) { _, newValue in
                guard let p = newValue else { return }
                applyConfig(source: p.source, target: p.target)
            }
            .translationTask(currentConfig) { session in
                guard let bridge else { return }

                // 1. 優先處理翻譯請求
                //   v1.2.2：跳過 prepareTranslation()，因為 service 端已在 translate(text:pair:)
                //   先用 LanguageAvailability 檢查過 .ready 才會送進來，
                //   每次都呼叫 prepareTranslation() 會多花 1-3 秒，是先前「轉超久」的主因。
                if let pending = bridge.pending {
                    do {
                        let response = try await session.translate(pending.text)
                        bridge.finishTranslate(text: response.targetText)
                    } catch {
                        // 後援：若 session.translate 直接失敗（例如語言包剛被刪除），
                        // 補打 prepareTranslation 再重試一次。
                        do {
                            try await session.prepareTranslation()
                            let retry = try await session.translate(pending.text)
                            bridge.finishTranslate(text: retry.targetText)
                        } catch {
                            bridge.failTranslate(error: TranslationError.underlying(error))
                        }
                    }
                }

                // 2. 處理「純下載語言包」請求
                if bridge.pendingPrepare != nil {
                    do {
                        try await session.prepareTranslation()
                        bridge.finishPrepare()
                    } catch {
                        bridge.failPrepare(error: TranslationError.underlying(error))
                    }
                }
            }
    }

    /// v1.2.2：只在語言對真的變了才重建 session；
    /// 同一語言對的下一筆請求改用 `invalidate()` 觸發 `.translationTask` 重跑，
    /// 沿用同一個 session 大幅減少首次建立的延遲。
    /// invalidate() 是 mutating，必須透過 var 暫存後寫回 @State，否則無法呼叫。
    private func applyConfig(source: String, target: String) {
        if source == currentSource && target == currentTarget && currentConfig != nil {
            var cfg = currentConfig
            cfg?.invalidate()
            currentConfig = cfg
        } else {
            currentSource = source
            currentTarget = target
            currentConfig = .init(
                source: Locale.Language(identifier: source),
                target: Locale.Language(identifier: target)
            )
        }
    }
}

extension View {
    /// 把 AppleTranslationBridge 掛到 View tree 上，讓 Service 層的翻譯請求能執行。
    /// 通常放在 App 根節點（RootView）。
    func appleTranslationBridge(_ bridge: AppleTranslationBridge?) -> some View {
        modifier(AppleTranslationBridgeModifier(bridge: bridge))
    }
}
#else
extension View {
    /// Stub：非 iOS 17.4+ 環境（Windows 編譯）直接回原 View。
    func appleTranslationBridge(_ bridge: AppleTranslationBridge?) -> some View { self }
}
#endif

// MARK: - ─────────────────────────────────────────────────────────────
// MARK: B 版：純 Service 版（備援 / 參考）
// MARK: ─────────────────────────────────────────────────────────────
//
// 如果 A 版實測後發現 bridge actor 在某些邊界情況（例如 ViewModel 生命週期
// 結束前 session 還沒 resume）會爛掉，可以改走這個 B 版：
// Service 只負責查狀態，翻譯本身由 ViewModel 直接透過 .translationTask 執行。
//
// 介面調整：
//   MTService 再加一個「給 View 用的」inline 方法，protocol 不變
//   但 DefaultTranslateTextUseCase 需要改成不直接呼叫 mtService.translate，
//   而是 ViewModel 收到譯文後反向回寫 history。
//
// 這個 B 版 **目前不啟用**，保留為文字註解避免編譯警告。
// Mac 實測 A 版失敗時再把這段擴展為正式檔案。
//
/*
final class LightweightAppleMTService: MTService {
    func translate(text: String, pair: LanguagePair) async throws -> String {
        throw TranslationError.underlying(NSError(
            domain: "LightweightAppleMTService",
            code: -100,
            userInfo: [NSLocalizedDescriptionKey:
                "B 版不直接翻譯；請改由 View 層 .translationTask 處理"]
        ))
    }

    func languagePackStatus(for pair: LanguagePair) async throws -> LanguagePackStatus {
        // 同 A 版 LanguageAvailability 檢查
        .notDownloaded
    }

    func downloadLanguagePack(for pair: LanguagePair) async throws {
        // ViewModel 端 prepareTranslation，這裡 no-op
    }

    func removeLanguagePack(for pair: LanguagePair) async throws {
        // 同 A 版：Apple 不允許，引導至系統設定
    }
}
*/
