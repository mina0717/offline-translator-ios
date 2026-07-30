import SwiftUI
import UIKit

/// v1.5.0：贊助／打賞頁。
///
/// ⚠️ **App Store 審查風險**（見 v15.8 報告）：
/// Apple 審查指南 3.1.1 要求 App 內的「打賞／贊助」走 In-App Purchase，
/// 導向外部付款頁面在多數地區屬於違規（美國區 2025 年後有例外）。
/// 這一頁是依 Mina 指定的 ECPay QR 實作，**上架前建議先評估是否改走 IAP**。
///
/// 目前設計上已盡量降低風險：
/// - 放在「設定」內，不是主畫面的顯眼位置
/// - 純粹感謝性質，**不解鎖任何功能**（不影響 App 的任何能力）
/// - 文案不含任何「付費才能用」的暗示
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss

    /// ECPay 收款 QR
    private let qrImageURL = URL(string: "https://payment.ecpay.com.tw/Upload/QRCode/202601/QRCode_2a47a920-57c7-4c02-84fc-9a53f1ae479d.png")!

    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {

                    Image(systemName: "heart.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.pink)
                        .padding(.top, Theme.Spacing.lg)

                    VStack(spacing: Theme.Spacing.sm) {
                        Text("support.title")
                            .font(Theme.Font.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("support.body")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    // QR 區塊
                    VStack(spacing: Theme.Spacing.sm) {
                        AsyncImage(url: qrImageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .interpolation(.none)     // QR 用 none 才不會糊掉
                                    .scaledToFit()
                            case .failure:
                                qrFallback
                            case .empty:
                                ZStack {
                                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                                        .fill(.ultraThinMaterial)
                                    ProgressView()
                                }
                            @unknown default:
                                qrFallback
                            }
                        }
                        .frame(width: 220, height: 220)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

                        Text("support.qr.hint")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Theme.Spacing.md)
                    .glassCard()
                    .padding(.horizontal, Theme.Spacing.lg)

                    // 備用：直接開啟 / 複製連結
                    VStack(spacing: Theme.Spacing.sm) {
                        Link(destination: qrImageURL) {
                            Label {
                                Text("support.action.open")
                            } icon: {
                                Image(systemName: "safari")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .fill(Theme.Colors.accent)
                            )
                        }

                        Button {
                            UIPasteboard.general.string = qrImageURL.absoluteString
                            withAnimation { didCopy = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_800_000_000)
                                withAnimation { didCopy = false }
                            }
                        } label: {
                            Label {
                                Text(didCopy ? "support.action.copied" : "support.action.copy")
                            } icon: {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    Text("support.disclaimer")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .background(GradientBackground())
            .navigationTitle("support.nav_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
    }

    private var qrFallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("support.qr.offline")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }
}

#Preview {
    SupportView()
}
