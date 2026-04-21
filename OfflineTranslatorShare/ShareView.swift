import SwiftUI
import Translation

/// Share Extension 內的 SwiftUI 主畫面。
/// 收到分享文字後，使用 Apple Translation framework 在 Extension 內直接翻譯，
/// 不需要回主 App。
struct ShareView: View {

    let initialText: String
    let onClose: () -> Void

    @State private var sourceText: String = ""
    @State private var translatedText: String = ""
    @State private var isTranslating: Bool = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var errorMessage: String?
    @State private var targetLocale: Locale.Language = Locale.Language(identifier: "en")

    private let supportedTargets: [(label: String, lang: Locale.Language)] = [
        ("🇺🇸 English",  Locale.Language(identifier: "en")),
        ("🇹🇼 繁體中文", Locale.Language(identifier: "zh-Hant")),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sourceCard
                        targetPicker
                        translateButton
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        translatedCard
                    }
                    .padding()
                }
            }
            .navigationTitle("離線翻譯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: onClose)
                        .disabled(translatedText.isEmpty)
                }
            }
            .translationTask(translationConfig) { session in
                await runTranslation(session: session)
            }
        }
        .onAppear {
            sourceText = initialText
        }
    }

    // MARK: - Subviews

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("原文")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $sourceText)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
                )
        }
    }

    private var targetPicker: some View {
        Picker("譯為", selection: Binding(
            get: { targetLocale.languageCode?.identifier ?? "en" },
            set: { newCode in
                targetLocale = Locale.Language(identifier: newCode)
            }
        )) {
            ForEach(supportedTargets, id: \.lang.languageCode?.identifier) { item in
                Text(item.label).tag(item.lang.languageCode?.identifier ?? "")
            }
        }
        .pickerStyle(.segmented)
    }

    private var translateButton: some View {
        Button {
            startTranslation()
        } label: {
            HStack {
                if isTranslating { ProgressView().tint(.white) }
                else {
                    Image(systemName: "sparkles")
                    Text("翻譯").bold()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
        }
        .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
        .opacity(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
    }

    private var translatedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("譯文")
                .font(.caption).foregroundStyle(.secondary)
            Text(translatedText.isEmpty ? "翻譯結果會顯示在這裡" : translatedText)
                .font(.body)
                .foregroundStyle(translatedText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
                )
                .textSelection(.enabled)
        }
    }

    // MARK: - Translation flow

    private func startTranslation() {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isTranslating = true
        errorMessage = nil
        translationConfig = TranslationSession.Configuration(
            source: nil, // 讓系統自動偵測
            target: targetLocale
        )
    }

    private func runTranslation(session: TranslationSession) async {
        defer { isTranslating = false }
        do {
            let response = try await session.translate(sourceText)
            translatedText = response.targetText
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

#Preview {
    ShareView(initialText: "Hello world") { }
}
