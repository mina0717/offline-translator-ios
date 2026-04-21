import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Social

/// Share Extension 入口。
/// 從其他 App 收到分享文字 / URL 後，呼叫 onCompletion 結束 Extension。
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadSharedText()
    }

    // MARK: - Item providers

    /// 嘗試從 NSExtensionContext 讀出純文字 / URL，
    /// 都讀不到就直接退出。
    private func loadSharedText() {
        guard
            let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = extensionItem.attachments
        else {
            present(text: "")
            return
        }

        let textType = UTType.plainText.identifier
        let urlType  = UTType.url.identifier

        // 優先吃 plain text
        if let textProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            textProvider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] item, _ in
                let str = (item as? String) ?? (item as? NSAttributedString)?.string ?? ""
                Task { @MainActor in self?.present(text: str) }
            }
            return
        }

        // 退而求其次：URL（用網址作為翻譯來源也合理）
        if let urlProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            urlProvider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] item, _ in
                let str: String
                if let url = item as? URL {
                    str = url.absoluteString
                } else if let strItem = item as? String {
                    str = strItem
                } else {
                    str = ""
                }
                Task { @MainActor in self?.present(text: str) }
            }
            return
        }

        present(text: "")
    }

    // MARK: - Hosting SwiftUI

    @MainActor
    private func present(text: String) {
        let view = ShareView(initialText: text) { [weak self] in
            self?.finish()
        }
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        self.hostingController = host
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
