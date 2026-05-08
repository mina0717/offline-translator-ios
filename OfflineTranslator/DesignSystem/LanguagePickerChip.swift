import SwiftUI

/// v1.3.0：可點選的語言 chip（Menu picker）。
///
/// 用在語音翻譯、雙向對話兩個入口的「來源 / 譯文」chip 上。
/// 點擊 chip → 從 Menu 選 7 種支援的語言之一。
///
/// `excluded` 用來避免「來源 = 目標」（例如選來源時把目標語言列為 disabled）。
struct LanguagePickerChip: View {
    let current: Language
    let options: [Language]
    let excluded: Language
    let caption: LocalizedStringKey
    let disabled: Bool
    let onSelect: (Language) -> Void

    var body: some View {
        Menu {
            ForEach(options) { lang in
                Button {
                    onSelect(lang)
                } label: {
                    HStack {
                        Text("\(lang.flag) \(lang.displayName)")
                        if lang == current {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(lang == excluded)
            }
        } label: {
            VStack(spacing: 2) {
                Text(caption)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: 4) {
                    Text("\(current.flag) \(current.displayName)")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .disabled(disabled)
    }
}

/// v1.3.0：對話模式用的緊湊版 picker（顯示在錄音按鈕上方）。
/// 比 `LanguagePickerChip` 更小、不佔用太多垂直空間。
struct ConversationLanguageMenu: View {
    let current: Language
    let options: [Language]
    let excluded: Language
    let disabled: Bool
    let onSelect: (Language) -> Void

    var body: some View {
        Menu {
            ForEach(options) { lang in
                Button {
                    onSelect(lang)
                } label: {
                    HStack {
                        Text("\(lang.flag) \(lang.displayName)")
                        if lang == current {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(lang == excluded)
            }
        } label: {
            HStack(spacing: 6) {
                Text("\(current.flag) \(current.displayName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .disabled(disabled)
    }
}
