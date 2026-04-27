import SwiftUI
import UIKit

/// 全 App 共用的色票、字型、圓角、間距 token。
/// 所有 UI 都應該透過 `Theme` 取值，禁止在 View 內硬寫色碼。
///
/// v1.1：色彩從靜態 Color 改為「亮/深雙套」動態 Color，
///       透過 `Color(uiColor: UIColor { traits in ... })` 在系統切換時自動跟著換。
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// 淺粉紫漸層的起點
        /// - 亮色：粉色（#FFDAF0 感）
        /// - 深色：暗紫色（深夜氣氛、避免螢幕過亮）
        static let gradientStart = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.13, green: 0.10, blue: 0.20, alpha: 1.0)
                : UIColor(red: 1.00, green: 0.86, blue: 0.94, alpha: 1.0)
        })

        /// 淺粉紫漸層的中點
        static let gradientMid = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.09, blue: 0.24, alpha: 1.0)
                : UIColor(red: 0.92, green: 0.82, blue: 0.97, alpha: 1.0)
        })

        /// 淺粉紫漸層的終點
        static let gradientEnd = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.26, alpha: 1.0)
                : UIColor(red: 0.80, green: 0.78, blue: 1.00, alpha: 1.0)
        })

        /// 主要強調色（按鈕、選取狀態）
        /// 深色模式改成亮一點的紫，讓按鈕在暗背景上跳得出來
        static let accent = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.82, green: 0.78, blue: 0.96, alpha: 1.0)
                : UIColor(red: 0.73, green: 0.69, blue: 0.88, alpha: 1.0)
        })

        /// 內文文字色
        /// 深色模式幾乎純白，確保對比度 > WCAG AA (4.5:1)
        static let textPrimary = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
                : UIColor(red: 0.15, green: 0.13, blue: 0.22, alpha: 1.0)
        })

        /// 次要文字色（label / placeholder）
        /// 深色模式用淺灰，避免次要文字在深背景上變成雜訊
        static let textSecondary = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.75, green: 0.73, blue: 0.82, alpha: 1.0)
                : UIColor(red: 0.42, green: 0.40, blue: 0.50, alpha: 1.0)
        })

        /// 玻璃卡背後微微的描邊色
        /// 深色模式用更柔的白，避免邊框在暗背景上太刺
        static let glassStroke = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.white.withAlphaComponent(0.55)
        })
    }

    // MARK: - Layout

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Typography
    //
    // v1.1.2 老人友善：所有字體放大 ~25-40%。原值見註解。
    // 翻譯內容用 `translation` 字型（更大、更易讀）。

    enum Font {
        /// 32 → 36 (主標題)
        static let largeTitle = SwiftUI.Font.system(size: 36, weight: .bold,     design: .rounded)
        /// 24 → 30
        static let title      = SwiftUI.Font.system(size: 30, weight: .semibold, design: .rounded)
        /// 18 → 24
        static let headline   = SwiftUI.Font.system(size: 24, weight: .semibold, design: .rounded)
        /// 16 → 20（一般內文 / button label）
        static let body       = SwiftUI.Font.system(size: 20, weight: .regular,  design: .rounded)
        /// 13 → 16（次要 label / 字數計數器）
        static let caption    = SwiftUI.Font.system(size: 16, weight: .regular,  design: .rounded)

        /// **v1.1.2 新增**：翻譯內容專用字型（原文 + 譯文）。
        /// 用最大字級確保中老年使用者讀得清楚。
        /// 26pt + medium weight，比 body 還醒目。
        static let translation = SwiftUI.Font.system(size: 26, weight: .medium,  design: .rounded)

        /// **v1.1.2 新增**：翻譯結果的「強調版」 — 用於目標語言譯文。
        /// 28pt + semibold，視覺重量比原文更重，讓使用者一眼看到結果。
        static let translationEmphasized = SwiftUI.Font.system(size: 28, weight: .semibold, design: .rounded)
    }
}
