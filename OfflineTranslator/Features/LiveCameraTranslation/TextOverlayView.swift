import SwiftUI

/// v1.4.0：把譯文疊在原文位置上。
///
/// 座標系轉換是這個檔案的重點：
/// - Vision 給的是 normalized（0~1）、**原點左下**、相對於「整張攝影機影像」
/// - SwiftUI 要的是 pixel、**原點左上**、相對於「螢幕上的 preview 區域」
/// - preview layer 用 `.resizeAspectFill`，所以影像會被裁切，必須把 aspect-fill
///   的縮放與置中位移一起算進去，否則譯文會整體偏移
struct TextOverlayView: View {
    let region: RecognizedTextRegion
    let viewSize: CGSize
    /// 攝影機影像的長寬比（直向 720x1280 → 0.5625）
    let cameraAspect: CGFloat

    var body: some View {
        let rect = Self.overlayRect(
            normalized: region.normalizedRect,
            viewSize: viewSize,
            cameraAspect: cameraAspect
        )

        if let translated = region.translatedText {
            // v1.4.0 hotfix5：**譯文框必須貼合原文那一行的大小**。
            //
            // 之前用 lineLimit(2) + 只固定寬度，長譯文會折成兩行，
            // 框高變成原文行高的兩倍以上，直接壓到上下相鄰的行 ——
            // 這就是 QA 影片裡「黑框互相交疊」的成因。
            //
            // 改成單行 + 縮放字級塞進原文的框（Google Lens 也是這個做法）：
            // 寧可字小一點，也不要蓋掉隔壁行。
            Text(translated)
                .font(.system(size: fontSize(for: rect), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .truncationMode(.tail)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .frame(
                    width: max(rect.width, 36),
                    height: max(rect.height, Self.minBoxHeight),
                    alignment: .center
                )
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.black.opacity(0.8))
                )
                .position(x: rect.midX, y: rect.midY)
                // 位置變動用動畫平滑過去，而不是瞬間跳。
                // 搭配 service 端的穩定 id + EMA，畫面才不會抖。
                .animation(.easeOut(duration: 0.3), value: rect)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(region.originalText)，譯為 \(translated)"))
        } else if region.showsPendingIndicator {
            // 譯文還沒回來、而且已經等了一小段時間，才畫虛線框。
            // v1.4.0 hotfix4：改用 showsPendingIndicator 而不是「translatedText == nil」——
            // 否則每個新區塊都會先閃一下虛線框再變成譯文，也是一種抖動。
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: max(rect.width, 24), height: max(rect.height, 14))
                .position(x: rect.midX, y: rect.midY)
                .animation(.easeOut(duration: 0.25), value: rect)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(region.originalText)，尚未翻譯"))
        }
    }

    /// 框的最小高度。太扁會看不清楚，但也不能大到蓋住隔壁行。
    static let minBoxHeight: CGFloat = 15

    /// 字級跟著 bounding box 高度走，讓譯文視覺上跟原文差不多大。
    /// v1.4.0 hotfix5：0.7 → 0.62，並把上限從 28 收到 24。
    /// 配合 `lineLimit(1)` + `minimumScaleFactor`，字會自己縮到塞得進原文的框，
    /// 不會再因為折行而把框撐高、壓到相鄰的行。
    private func fontSize(for rect: CGRect) -> CGFloat {
        min(max(rect.height * 0.62, 10), 24)
    }

    /// Vision normalized rect → SwiftUI rect（含 aspect-fill 補償）
    static func overlayRect(normalized: CGRect,
                            viewSize: CGSize,
                            cameraAspect: CGFloat) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0, cameraAspect > 0 else { return .zero }

        // 以 view 寬為基準推出影像若完整顯示時的尺寸，再取 aspect-fill 的放大倍率
        let frameW = cameraAspect
        let frameH: CGFloat = 1.0
        let scale = max(viewSize.width / frameW, viewSize.height / frameH)
        let scaledW = frameW * scale
        let scaledH = frameH * scale
        let offsetX = (viewSize.width - scaledW) / 2
        let offsetY = (viewSize.height - scaledH) / 2

        let x = normalized.origin.x * scaledW + offsetX
        // Y 翻轉：Vision 原點左下 → SwiftUI 原點左上
        let y = (1 - normalized.origin.y - normalized.height) * scaledH + offsetY
        return CGRect(
            x: x,
            y: y,
            width: normalized.width * scaledW,
            height: normalized.height * scaledH
        )
    }
}
