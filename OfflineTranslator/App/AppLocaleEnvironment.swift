import SwiftUI

/// v1.3.0：App 內介面語言切換的核心。
///
/// 設計：用 `@AppStorage` 把使用者選擇（"system" / "zh-Hant" / "en"）存到 UserDefaults，
/// 再透過 SwiftUI `.environment(\.locale, ...)` 把 Locale 注入整個 view tree，
/// 所有 `Text("...")`、`Label("...", systemImage:)`、SwiftUI Button label 等
/// 都會立刻切換到對應語言，**不需要重啟 App**。
///
/// 限制（誠實揭露）：
/// 1. Service 層（ASRService、OCRService、MTServiceApple 等）裡用 `String` 直接寫的
///    錯誤訊息**不會**跟著切，會維持系統 locale 對應的版本。v1.3.1+ 再清。
/// 2. App Intents（Siri / Shortcuts）標題目前寫死中文，跟系統 locale 走，不受此設定影響。
/// 3. NavigationTitle 的 `.navigationTitle("拍照翻譯")` 是 LocalizedStringKey，會自動跟。
///
/// 用法（在 OfflineTranslatorApp.swift 或 RootView.swift 注入）：
/// ```swift
/// @StateObject private var localeManager = AppLocaleManager()
///
/// var body: some Scene {
///     WindowGroup {
///         RootView()
///             .environment(\.locale, localeManager.effectiveLocale)
///             .environmentObject(localeManager)
///     }
/// }
/// ```

/// 介面語言選項（v1.3.0 範圍：跟隨系統 / 中 / 英）
enum AppUILocale: String, CaseIterable, Identifiable {
    case system
    case zhHant = "zh-Hant"
    case english = "en"

    var id: String { rawValue }

    /// Settings 顯示用名稱（key 寫在 Localizable.strings，會跟著當前 locale 切換）
    var displayKey: LocalizedStringKey {
        switch self {
        case .system:  return "settings.locale.system"
        case .zhHant:  return "settings.locale.zh_hant"
        case .english: return "settings.locale.english"
        }
    }

    /// 對應的 Locale。`system` → 回傳 nil 讓 SwiftUI fallback 到 Locale.current
    var locale: Locale? {
        switch self {
        case .system:  return nil
        case .zhHant:  return Locale(identifier: "zh-Hant")
        case .english: return Locale(identifier: "en")
        }
    }
}

/// 介面語言狀態管理。注入到 RootView，由 SettingsView 修改。
@MainActor
final class AppLocaleManager: ObservableObject {

    @AppStorage("preferredUILocale") private var storedRawValue: String = AppUILocale.system.rawValue

    /// 公開的目前選擇（讀寫此屬性會自動同步到 @AppStorage）
    @Published var preference: AppUILocale = .system {
        didSet {
            storedRawValue = preference.rawValue
        }
    }

    /// 算出實際要套用的 Locale。
    /// `system` → 回傳 `Locale.current`，由 SwiftUI 用系統 locale。
    var effectiveLocale: Locale {
        preference.locale ?? Locale.current
    }

    init() {
        // 從 @AppStorage 還原使用者上次選擇
        let raw = UserDefaults.standard.string(forKey: "preferredUILocale")
            ?? AppUILocale.system.rawValue
        self.preference = AppUILocale(rawValue: raw) ?? .system
    }
}
