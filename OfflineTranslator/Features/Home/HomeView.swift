import SwiftUI
import TipKit

/// 首頁：四個主入口（文字 / 語音 / 拍照 / 語言包）+ 歷史紀錄入口。
///
/// v1.3.0：
/// - 右上角加齒輪 → SettingsView（介面語言切換）
/// - HomeTile 的 title/subtitle 改用 `LocalizedStringKey`，
///   修復 v1.1 起就存在的 bug：透過 `String` 變數傳給 `Text` 不會走在地化。
struct HomeView: View {
    enum Destination: Hashable {
        case text, speech, languagePack, history, vocabulary, conversation
        /// v1.4.0：相機翻譯（原「拍照翻譯」已併入，見 LiveCameraTranslationView）
        case liveCamera
        /// v1.5.0：免持聆聽（單頁、聽對方講話看譯文）
        case handsFreeListening
    }

    /// v1.3.0：Settings sheet 開關
    @State private var isShowingSettings = false

    /// v1.5.0：一次性提示「長按功能格可設為啟動畫面」
    private let launchModeTip = LaunchModeTip()
    /// 用來偵測「使用者設定過啟動畫面」（長按或設定頁皆會改到同一個 key）
    @AppStorage(LaunchMode.storageKey) private var launchModeRaw: String = LaunchMode.home.rawValue

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

                // v1.5.0：一次性新手提示（按 X／設定過／主畫面出現滿 3 次就不再顯示）
                TipView(launchModeTip)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                              GridItem(.flexible(), spacing: Theme.Spacing.md)],
                    spacing: Theme.Spacing.md
                ) {
                    HomeTile(icon: "text.bubble.fill", title: "文字翻譯",  subtitle: "輸入即翻譯", destination: .text)
                    HomeTile(icon: "mic.fill",         title: "語音翻譯",  subtitle: "按住說話",   destination: .speech)
                    // v1.4.0：原「拍照翻譯」已併入「相機翻譯」
                    // （即時疊字 + 快門單張 + 相簿選圖，同一個入口）
                    HomeTile(icon: "camera.viewfinder", title: "相機翻譯", subtitle: "即時疊字或拍照", destination: .liveCamera)
                    HomeTile(icon: "bubble.left.and.bubble.right.fill", title: "雙向對話", subtitle: "面對面互譯", destination: .conversation)
                    // v1.5.0：免持聆聽 —— 手不用按著
                    HomeTile(icon: "ear.and.waveform", title: "免持聆聽", subtitle: "免動手·聽了就譯", destination: .handsFreeListening)
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
            case .liveCamera:   LiveCameraTranslationView()
            case .handsFreeListening: HandsFreeListeningView()
            case .conversation: ConversationView()
            case .languagePack: LanguagePackView()
            case .history:      HistoryView()
            case .vocabulary:   VocabularyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // v1.5.0：累計主畫面出現次數，給 LaunchModeTip 的「最多顯示 3 次」規則用
        .onAppear { LaunchModeTip.homeVisitCount += 1 }
        // v1.5.0：只要選了非「主畫面」的啟動畫面，提示就功成身退
        .onChange(of: launchModeRaw) { _, newValue in
            if newValue != LaunchMode.home.rawValue {
                LaunchModeTip.hasSetLaunchMode = true
            }
        }
        // v1.3.0：右上角設定齒輪
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel(Text("settings.title"))
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }
}

/// v1.3.0：title / subtitle 改用 `LocalizedStringKey`，這樣傳進來的中文字串
/// 仍會走 SwiftUI 在地化機制（從 zh-Hant.strings / en.strings 查表）。
private struct HomeTile: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let destination: HomeView.Destination

    /// v1.5.0：與設定頁共用同一個 key，兩邊改動會即時同步
    @AppStorage(LaunchMode.storageKey) private var launchModeRaw: String = LaunchMode.home.rawValue

    /// 這一格對應的啟動模式；語言包這類管理頁面為 nil（不能設成啟動畫面）
    private var tileMode: LaunchMode? { LaunchMode(destination: destination) }

    private var isLaunchDefault: Bool {
        guard let tileMode else { return false }
        return launchModeRaw == tileMode.rawValue
    }

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
            // v1.5.0：目前的啟動畫面標一個圖釘。
            // 這同時是這個功能的「可見線索」—— 免持按鈕當初不顯眼、
            // 民眾不知道能按，這次讓設定結果一眼看得到。
            .overlay(alignment: .topTrailing) {
                if isLaunchDefault {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Theme.Colors.accent))
                        .padding(10)
                        .accessibilityLabel(Text("launch.badge.accessibility"))
                }
            }
        }
        .buttonStyle(.plain)
        // v1.5.0：長按 → 設為（或取消）啟動畫面
        .contextMenu {
            if let tileMode {
                if isLaunchDefault {
                    Button {
                        launchModeRaw = LaunchMode.home.rawValue
                    } label: {
                        Label("launch.action.clear", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        launchModeRaw = tileMode.rawValue
                    } label: {
                        Label("launch.action.set", systemImage: "pin")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environmentObject(AppDependencies.makeMock())
        .environmentObject(AppLocaleManager())
        .background(GradientBackground())
}
