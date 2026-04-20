import SwiftUI

/// 全 App 共用的色票、字型、圓角、間距 token。
/// 所有 UI 都應該透過 `Theme` 取值，禁止在 View 內硬寫色碼。
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// 淺粉紫漸層的起點（偏粉）
        static let gradientStart = Color(red: 1.00, green: 0.86, blue: 0.94)
        /// 淺粉紫漸層的中點（粉紫）
        static let gradientMid   = Color(red: 0.92, green: 0.82, blue: 0.97)
        /// 淺粉紫漸層的終點（偏紫）
        static let gradientEnd   = Color(red: 0.80, green: 0.78, blue: 1.00)

        /// 主要強調色（按鈵、選取狀態）
        static let accent        = Color(red: 0.73, green: 0.69, blue: 0.88)
        /// 內文文字色
        static let textPrimary   = Color(red: 0.15, green: 0.13, blue: 0.22)
        /// 次要文字色（label / placeholder）
        static let textSecondary = Color(red: 0.42, green: 0.40, blue: 0.50)
        /// 玻璃卡背後微微的描邊色
        static let glassStroke   = Color.white.opacity(0.55)
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

    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 32, weight: .bold,    design: .rounded)
        static let title      = SwiftUI.Font.system(size: 24, weight: .semibold, design: .rounded)
        static let headline   = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)
        static let body       = SwiftUI.Font.system(size: 16, weight: .regular,  design: .rounded)
        static let caption    = SwiftUI.Font.system(size: 13, weight: .regular,  design: .rounded)
    }
}
