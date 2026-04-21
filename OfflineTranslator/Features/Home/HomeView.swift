import SwiftUI

/// 首頁：四個主入口（文字 / 語音 / 拍照 / 語言包）+ 歷史紀錄入口。
struct HomeView: View {
    enum Destination: Hashable {
        case text, speech, photo, languagePack, history, vocabulary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                Text("離線翻譯")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.md)

                Text("不用網路也能溝通")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                              GridItem(.flexible(), spacing: Theme.Spacing.md)],
                    spacing: Theme.Spacing.md
                ) {
                    HomeTile(icon: "text.bubble.fill", title: "文字翻譯",  subtitle: "輸入即翻譯", destination: .text)
                    HomeTile(icon: "mic.fill",         title: "語音翻譯",  subtitle: "按住說話",   destination: .speech)
                    HomeTile(icon: "camera.fill",      title: "拍照翻譯",  subtitle: "辨識圖片文字", destination: .photo)
                    HomeTile(icon: "arrow.down.circle.fill", title: "語言包", subtitle: "離線管理",   destination: .languagePack)
                }

                // v1.1：生詞本入口
                NavigationLink(value: Destination.vocabulary) {
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("字典生詞")
                                .font(Theme.Font.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("儲存常用詞")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .glassCard()
                }
                .buttonStyle(.plain)

                NavigationLink(value: Destination.history) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                        Text("歷史紀錄")
                            .font(Theme.Font.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .glassCard()
                }
                .buttonStyle(.plain)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .navigationDestination(for: Destination.self) { dest in
            switch dest {
            case .text:         TextTranslationView()
            case .speech:       SpeechTranslationView()
            case .photo:        PhotoTranslationView()
            case .languagePack: LanguagePackView()
            case .history:      HistoryView()
            case .vocabulary:   VocabularyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let destination: HomeView.Destination

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 120)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environmentObject(AppDependencies.makeMock())
        .background(GradientBackground())
}
