import SwiftUI

/// v1.5.0：App 開啟時要自動進入哪個功能（使用者自選的「預設翻譯模式」）。
///
/// 只收「翻譯模式」：文字 / 語音 / 相機 / 雙向對話 / 免持聆聽。
/// 語言包、歷史、生詞本是管理類頁面，不適合當啟動畫面，所以不在這裡。
///
/// ## 設計原則
/// - **預設是主畫面**：沒設定過的人（包含所有舊版升級上來的使用者）行為完全不變。
/// - **未知值一律退回主畫面**：raw value 存在 UserDefaults，日後若改了 case 名稱，
///   讀到舊值不能讓 App 卡在奇怪的狀態。
/// - **只在冷啟動套用一次**：由 `RootView` 在建立導覽堆疊時決定，
///   App 從背景回來、或使用者在設定頁改選項，都不會被硬拉到別的畫面。
enum LaunchMode: String, CaseIterable, Identifiable {
    case home
    case text
    case speech
    case camera
    case conversation
    case handsFree

    /// `@AppStorage` / `UserDefaults` 共用的 key
    static let storageKey = "defaultLaunchMode"

    var id: String { rawValue }

    /// 目前生效的啟動模式。讀不到或讀到未知值都回 `.home`。
    static var current: LaunchMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return LaunchMode(rawValue: raw) ?? .home
    }

    // MARK: - 對應首頁導覽目標

    /// 要自動導覽到哪一頁。`nil` 代表停在主畫面。
    var destination: HomeView.Destination? {
        switch self {
        case .home:         return nil
        case .text:         return .text
        case .speech:       return .speech
        case .camera:       return .liveCamera
        case .conversation: return .conversation
        case .handsFree:    return .handsFreeListening
        }
    }

    /// 反向對應：首頁某個 tile 是否能被設為啟動畫面。
    ///
    /// 這裡刻意**逐一列出所有 case，不用 default** ——
    /// 日後 `HomeView.Destination` 新增功能時，編譯器會逼我們在這裡
    /// 明確決定「它能不能當啟動畫面」，而不是默默漏掉。
    init?(destination: HomeView.Destination) {
        switch destination {
        case .text:               self = .text
        case .speech:             self = .speech
        case .liveCamera:         self = .camera
        case .conversation:       self = .conversation
        case .handsFreeListening: self = .handsFree
        case .languagePack, .history, .vocabulary:
            return nil
        }
    }

    // MARK: - 顯示

    /// 沿用首頁 tile 的標題 key（中文原文當 key，見專案在地化慣例），
    /// 這樣選單文字和首頁格子永遠一致。
    var titleKey: LocalizedStringKey {
        switch self {
        case .home:         return "launch.mode.home"
        case .text:         return "文字翻譯"
        case .speech:       return "語音翻譯"
        case .camera:       return "相機翻譯"
        case .conversation: return "雙向對話"
        case .handsFree:    return "免持聆聽"
        }
    }

    var iconName: String {
        switch self {
        case .home:         return "house.fill"
        case .text:         return "text.bubble.fill"
        case .speech:       return "mic.fill"
        case .camera:       return "camera.viewfinder"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .handsFree:    return "ear.and.waveform"
        }
    }
}
