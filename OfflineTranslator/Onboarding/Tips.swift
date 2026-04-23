import Foundation
import TipKit

/// v1.1：用 TipKit 做三個關鍵的新手引導。
///
/// TipKit 的好處：
///   - 系統自動追蹤「已顯示 / 已解除」，不需要自己寫 UserDefaults
///   - iOS 17+ 原生，不用第三方依賴
///   - 可以接 rules 控制什麼時候才出現（例如 App 至少打開過一次）
///
/// 使用方式：
///   1. App 啟動時 `Tips.configure(...)`（在 OfflineTranslatorApp init）
///   2. 在對應 View 上加 `.popoverTip(HoldToSpeakTip())`
///   3. 用戶做過一次對應動作後 `HoldToSpeakTip.didInvoke.sendDonation(...)` 自動隱藏

// MARK: - 1. 按住說話（Speech tab 主要按鈕）

struct HoldToSpeakTip: Tip {
    /// 追蹤使用者是否已經至少完成過一次錄音（`.donate(...)` 時會自動 increment）
    @Parameter
    static var hasRecordedOnce: Bool = false

    var title: Text {
        Text("tip.hold_to_speak.title")
    }

    var message: Text? {
        Text("tip.hold_to_speak.message")
    }

    var image: Image? {
        Image(systemName: "mic.circle.fill")
    }

    /// 只在還沒錄過音時出現
    var rules: [Rule] {
        [
            #Rule(HoldToSpeakTip.$hasRecordedOnce) { $0 == false }
        ]
    }
}

// MARK: - 2. 拍照翻譯（Photo tab 入口）

struct CameraTip: Tip {
    @Parameter
    static var hasUsedCameraOnce: Bool = false

    var title: Text {
        Text("tip.camera.title")
    }

    var message: Text? {
        Text("tip.camera.message")
    }

    var image: Image? {
        Image(systemName: "camera.viewfinder")
    }

    var rules: [Rule] {
        [
            #Rule(CameraTip.$hasUsedCameraOnce) { $0 == false }
        ]
    }
}

// MARK: - 3. 語言切換（↔ 按鈕）

struct LanguageSwitchTip: Tip {
    @Parameter
    static var hasSwappedOnce: Bool = false

    var title: Text {
        Text("tip.language_switch.title")
    }

    var message: Text? {
        Text("tip.language_switch.message")
    }

    var image: Image? {
        Image(systemName: "arrow.left.arrow.right.circle")
    }

    var rules: [Rule] {
        [
            #Rule(LanguageSwitchTip.$hasSwappedOnce) { $0 == false }
        ]
    }
}

// MARK: - 全域設定

enum OnboardingTips {
    /// App 啟動時呼叫一次即可；錯誤不致命，只印 log
    static func configure() {
        #if canImport(TipKit)
        do {
            try Tips.configure([
                .displayFrequency(.immediate),      // 進到對應畫面就可以馬上展示
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            #if DEBUG
            print("⚠️ TipKit configure failed: \(error)")
            #endif
        }
        #endif
    }
}
