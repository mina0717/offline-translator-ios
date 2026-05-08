import SwiftUI

/// v1.3.0：設定頁。MVP 範圍只有「介面語言」一個 section。
///
/// 入口：HomeView 右上角齒輪按鈕（toolbar）。
struct SettingsView: View {
    @EnvironmentObject private var localeManager: AppLocaleManager
    @Environment(\.dismiss) private var dismiss

    /// v13.7：Bootstrap 下載量級（Off / Minimal / Tier1 / Full）
    @AppStorage("bootstrapMode") private var bootstrapModeRaw: String = LanguagePackBootstrap.Mode.minimal.rawValue
    private var bootstrapMode: Binding<LanguagePackBootstrap.Mode> {
        Binding(
            get: { LanguagePackBootstrap.Mode(rawValue: bootstrapModeRaw) ?? .minimal },
            set: { bootstrapModeRaw = $0.rawValue }
        )
    }
    /// 顯示用：當前 device 可用空間
    @State private var availableGB: Double = LanguagePackBootstrap.queryAvailableStorageGB()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $localeManager.preference) {
                        ForEach(AppUILocale.allCases) { option in
                            Text(option.displayKey).tag(option)
                        }
                    } label: {
                        Label {
                            Text("settings.locale.title")
                        } icon: {
                            Image(systemName: "globe")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("settings.locale.section_header")
                } footer: {
                    Text("settings.locale.footer")
                }

                // v13.7：自動下載量級（4 級選擇）
                Section {
                    Picker(selection: bootstrapMode) {
                        Text("關閉").tag(LanguagePackBootstrap.Mode.off)
                        Text("最小（中↔英、~160MB）").tag(LanguagePackBootstrap.Mode.minimal)
                        Text("標準（繁中相關 26 對、~2GB）").tag(LanguagePackBootstrap.Mode.tier1)
                        Text("全部（182 對、~15GB · 不建議）").tag(LanguagePackBootstrap.Mode.full)
                    } label: {
                        Label {
                            Text("啟動時自動下載")
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(String(format: "目前可用空間：%.1f GB", availableGB))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                } header: {
                    Text("語言包")
                } footer: {
                    Text("空間 < 3GB 會自動降到「最小」、< 1GB 會跳過下載並提示。其他配對（如英↔日）切換到時會在背景下載。")
                }

                // v1.3.0：關於區塊
                Section {
                    LabeledContent {
                        Text(appVersionString)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            Text("settings.about.version")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }

                    Link(destination: URL(string: "https://mina0717.github.io/offline-translator-ios/privacy.html")!) {
                        Label {
                            Text("settings.about.privacy")
                        } icon: {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                } header: {
                    Text("settings.about.section_header")
                }
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppLocaleManager())
}
