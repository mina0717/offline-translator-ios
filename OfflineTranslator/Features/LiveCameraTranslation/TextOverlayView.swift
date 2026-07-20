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
            Text(translated)
                .font(.system(size: fontSize(for: rect), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(width: max(rect.width, 40), alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.78))
                )
                .position(x: rect.midX, y: rect.midY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(region.originalText)，譯為 \(translated)"))
        } else {
            // v1.4.0 hotfix3：譯文還沒回來（或翻譯失敗）時，至少把「這裡有偵測到文字」畫出來。
            // 先前這個分支是空的，導致「OCR 沒抓到字」和「抓到了但翻不出來」在畫面上長得一模一樣，
            // 完全無從判斷是辨識還是翻譯出問題。
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: max(rect.width, 24), height: max(rect.height, 14))
                .position(x: rect.midX, y: rect.midY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(region.originalText)，尚未翻譯"))
        }
    }

    /// 字級跟著 bounding box 高度走，讓譯文視覺上跟原文差不多大。
    private func fontSize(for rect: CGRect) -> CGFloat {
        min(max(rect.height * 0.7, 11), 28)
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
