import Foundation
import AppIntents
import UIKit

/// v1.1：用 AppIntents 把翻譯接到 Siri / Shortcuts。
///
/// 三個 Intent：
///   1. TranslateTextIntent — 從 Shortcuts 傳文字給我們翻（「嘿 Siri，用離線翻譯翻譯這句 Hello」）
///   2. TranslateClipboardIntent — 一鍵把剪貼簿內容翻譯並回寫
///   3. (未來) OpenSpeechTranslateIntent — 用 Siri 打開錄音畫面
///
/// 注意：
///   - @MainActor 讓我們可以直接摸 UIPasteboard
///   - 走 Apple Translation framework（iOS 17.4+）；如果模型沒下載會由底層自己彈系統對話框
///   - 單元測試用 MTServiceMock 可以驗證 perform() 邏輯
@available(iOS 17.0, *)
struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource = "intent.translate_text"
    static var description = IntentDescription(
        "用離線翻譯翻譯一段文字，不用連網。"
    )

    /// 使用者的輸入文字
    @Parameter(title: "Text")
    var sourceText: String

    /// 目標語言（預設英文；MVP 只支援 zh-Hant / en）
    @Parameter(title: "Target Language", default: IntentLanguage.english)
    var target: IntentLanguage

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$sourceText) 翻成 \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // 這裡刻意用輕量的 in-process 服務，不 spawn 完整 AppDependencies；
        // 對 Shortcuts 來說「快且穩」比「乾淨的 DI」重要
        let service = AppleMTService()
        let pair = LanguagePair(
            source: target.mirror,      // 把目標語言的「相反」當 source（MVP 只有兩個方向）
            target: target.language
        )

        do {
            let translated = try await service.translate(text: sourceText, pair: pair)
            return .result(
                value: translated,
                dialog: IntentDialog(stringLiteral: translated)
            )
        } catch {
            throw $sourceText.needsValueError("翻譯失敗，請確認語言包已下載。")
        }
    }
}

// MARK: - 剪貼簿翻譯（一鍵快捷指令）

@available(iOS 17.0, *)
struct TranslateClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "intent.translate_clipboard"
    static var description = IntentDescription(
        "把剪貼簿裡的文字翻譯好再放回剪貼簿。"
    )

    /// 設為 true → 翻譯完直接寫回 UIPasteboard
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Target Language", default: IntentLanguage.english)
    var target: IntentLanguage

    static var parameterSummary: some ParameterSummary {
        Summary("翻譯剪貼簿 → \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard
            let clipboard = UIPasteboard.general.string,
            !clipboard.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return .result(dialog: "剪貼簿是空的。")
        }

        let service = AppleMTService()
        let pair = LanguagePair(source: target.mirror, target: target.language)

        do {
            let translated = try await service.translate(text: clipboard, pair: pair)
            UIPasteboard.general.string = translated
            return .result(
                dialog: IntentDialog(stringLiteral: "已翻譯並複製：\(translated)")
            )
        } catch {
            return .result(dialog: "翻譯失敗，可能是語言包尚未下載。")
        }
    }
}

// MARK: - Enum 參數（Siri 選單用）

@available(iOS 17.0, *)
enum IntentLanguage: String, AppEnum {
    case traditionalChinese
    case english

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "語言"

    static var caseDisplayRepresentations: [IntentLanguage: DisplayRepresentation] = [
        .traditionalChinese: "繁體中文",
        .english: "English"
    ]

    /// 對應到 Domain Language
    var language: Language {
        switch self {
        case .traditionalChinese: return .traditionalChinese
        case .english:            return .english
        }
    }

    /// 另一半 — MVP 只有 zh-Hant ⇄ en 兩個方向
    var mirror: Language {
        switch self {
        case .traditionalChinese: return .english
        case .english:            return .traditionalChinese
        }
    }
}

// MARK: - AppShortcutsProvider
// 把 Intent 綁進 Shortcuts App，使用者第一次安裝完就能看到這兩個快捷

@available(iOS 17.0, *)
struct OfflineTranslatorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateTextIntent(),
            phrases: [
                "用 \(.applicationName) 翻譯",
                "翻譯這句用 \(.applicationName)",
                "Translate with \(.applicationName)"
            ],
            shortTitle: "intent.translate_text",
            systemImageName: "character.book.closed.fill"
        )

        AppShortcut(
            intent: TranslateClipboardIntent(),
            phrases: [
                "用 \(.applicationName) 翻譯剪貼簿",
                "Translate clipboard with \(.applicationName)"
            ],
            shortTitle: "intent.translate_clipboard",
            systemImageName: "doc.on.clipboard.fill"
        )
    }

    /// 讓 iOS 在系統設定 → Siri 裡顯示我們的 Intents
    static var shortcutTileColor: ShortcutTileColor = .purple
}
