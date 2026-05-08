import SwiftUI

/// v1.3.0：設定頁。MVP 範圍只有「介面語言」一個 section。
///
/// 入口：HomeView 右上角齒輪按鈕（toolbar）。
struct SettingsView: View {
    @EnvironmentObject private var localeManager: AppLocaleManager
    @Environment(\.dismiss) private var dismiss

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
