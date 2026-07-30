import SwiftUI
import PhotosUI
import MessageUI
import UIKit

/// v1.5.0：使用者反饋。
///
/// **為什麼走 Mail 而不是自架後端**：
/// 這個 App 的核心賣點是 100% 離線、零資料上傳。
/// 為了收反饋而架一台伺服器，等於自己戳破那個承諾（隱私政策也要跟著改）。
/// 用系統 Mail 撰寫視窗：資料直接從使用者的信箱寄出、我們沒有任何伺服器碰得到，
/// 使用者也能在送出前看到全部內容 —— 這才符合這個 App 的定位。
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var message: String = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var attachments: [FeedbackAttachment] = []
    @State private var isLoadingAttachments = false
    @State private var showMailComposer = false
    @State private var showMailUnavailable = false
    @State private var sizeWarning: String?

    /// 收件信箱
    private let supportEmail = "lb0018575@gmail.com"

    /// Mail 附件總量上限。超過多數郵件服務會直接退信。
    private static let maxTotalBytes = 20 * 1024 * 1024   // 20 MB

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("feedback.placeholder")
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("feedback.section.message")
                } footer: {
                    Text("feedback.footer.message")
                }

                Section {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 5,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Label {
                            Text("feedback.action.add_media")
                        } icon: {
                            Image(systemName: "paperclip")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }

                    if isLoadingAttachments {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("feedback.status.loading_media")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    ForEach(attachments) { item in
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: item.isVideo ? "video.fill" : "photo.fill")
                                .foregroundStyle(Theme.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                    .font(Theme.Font.caption)
                                    .lineLimit(1)
                                Text(item.readableSize)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Button {
                                attachments.removeAll { $0.id == item.id }
                                recomputeSizeWarning()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let warning = sizeWarning {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(Theme.Font.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("feedback.section.media")
                } footer: {
                    Text("feedback.footer.media")
                }

                Section {
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showMailComposer = true
                        } else {
                            showMailUnavailable = true
                        }
                    } label: {
                        Label {
                            Text("feedback.action.send")
                        } icon: {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || isLoadingAttachments)
                } footer: {
                    Text("feedback.footer.privacy")
                }
            }
            .navigationTitle("feedback.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.done") { dismiss() }
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                loadAttachments(from: newItems)
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposer(
                    recipient: supportEmail,
                    subject: Self.subjectLine,
                    body: composedBody,
                    attachments: attachments
                ) { didSend in
                    showMailComposer = false
                    if didSend { dismiss() }
                }
                .ignoresSafeArea()
            }
            .alert("feedback.alert.no_mail.title", isPresented: $showMailUnavailable) {
                Button("feedback.action.copy") { copyToClipboard() }
                Button("action.done", role: .cancel) { }
            } message: {
                Text(String(format: String(localized: "feedback.alert.no_mail.body"), supportEmail))
            }
        }
    }

    // MARK: - Compose

    private static var subjectLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return String(format: String(localized: "feedback.mail.subject"), v)
    }

    /// 附上裝置資訊，這樣回報 bug 時才查得到問題。
    /// 都是非個資的技術欄位，且使用者在寄出前看得到全部內容。
    private var composedBody: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current.model
        let os = UIDevice.current.systemVersion

        return """
        \(message)

        ────────────────
        \(String(localized: "feedback.mail.device_section"))
        App: v\(version) (\(build))
        Device: \(device)
        iOS: \(os)
        """
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = "\(supportEmail)\n\n\(composedBody)"
    }

    // MARK: - Attachments

    private func loadAttachments(from items: [PhotosPickerItem]) {
        isLoadingAttachments = true
        Task {
            var loaded: [FeedbackAttachment] = []
            for (index, item) in items.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                let ext = isVideo ? "mov" : "jpg"
                let mime = isVideo ? "video/quicktime" : "image/jpeg"
                loaded.append(
                    FeedbackAttachment(
                        filename: "attachment-\(index + 1).\(ext)",
                        mimeType: mime,
                        data: data,
                        isVideo: isVideo
                    )
                )
            }
            attachments = loaded
            pickerItems = []
            isLoadingAttachments = false
            recomputeSizeWarning()
        }
    }

    private func recomputeSizeWarning() {
        let total = attachments.reduce(0) { $0 + $1.data.count }
        if total > Self.maxTotalBytes {
            let mb = Double(total) / 1_048_576
            sizeWarning = String(
                format: String(localized: "feedback.warning.too_large"),
                mb
            )
        } else {
            sizeWarning = nil
        }
    }
}

// MARK: - Attachment model

struct FeedbackAttachment: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let isVideo: Bool

    var readableSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

// MARK: - Mail composer wrapper

private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachments: [FeedbackAttachment]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for item in attachments {
            vc.addAttachmentData(item.data, mimeType: item.mimeType, fileName: item.filename)
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish(result == .sent)
        }
    }
}

#Preview {
    FeedbackView()
}
