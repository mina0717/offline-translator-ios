# Offline Translator · Brand Guidelines

品牌視覺的單一事實來源。Landing Page、IG 圖卡、App Icon、App Store 截圖文字都從這份文件延伸。

---

## 1. Logo / App Icon

**源檔**: `AppIcon.svg`（SVG，可無限縮放）
**匯出**: `AppIcon-1024.png`（App Store 用）、180 / 120 / 60（iOS runtime）

### 概念

兩個重疊的對話框，分別是冷色（青綠）與暖色（珊瑚）— 讀作「兩種語言正在對話」。背景深夜靛藍色系暗示「離線」與「隱私」。白色三點與深底三點讀作「訊息進行中」的脈動。

### 為什麼這樣設計

- **無文字** — 符合 Apple HIG，全球通用
- **高對比雙色** — 小尺寸（60×60 Home Screen）仍清晰可辨
- **對話框形狀** — 直接傳達「翻譯 / 溝通」
- **深夜底色** — 與市面多數彩色翻譯 App 明顯區隔（Google、DeepL、Papago 都是高彩）；也暗示 Privacy / Offline

---

## 2. 品牌配色

```
PRIMARY BACKGROUND  深夜靛藍
#0B1438  ← 主背景
#050A24  ← 漸層終點
```

```
ACCENT · 冷色（代表目標語言 / 聆聽）
#5EE2D7  ← 亮青
#00A6B4  ← 深青
```

```
ACCENT · 暖色（代表來源語言 / 表達）
#FFB07C  ← 亮珊瑚
#FF6B6B  ← 暖紅
```

```
NEUTRAL
#FFFFFF  ← 純白
#F5F5F7  ← 超淺灰（次要背景）
#D2D2D7  ← 分隔線
#6E6E73  ← 次要文字
#1D1D1F  ← 主要文字（淺色模式）
```

### 配色使用原則

- **深色模式**：背景 `#0B1438` + 文字 `#F5F5F7`
- **淺色模式**：背景 `#FFFFFF` + 文字 `#1D1D1F`
- **強調按鈕**：冷色 → 主要動作；暖色 → 次要 / 警示
- **絕不**把暖色和冷色放在同色塊做背景（降低對比）

---

## 3. 字體系統

Apple 系統字體（不用外部 webfont，速度與一致性最好）：

- **Display / 標題**: `SF Pro Display` (iOS), `-apple-system` fallback chain
- **Body**: `SF Pro Text`
- **中文**: `PingFang TC`, `Noto Sans TC` (web fallback), `Microsoft JhengHei` (Windows 預覽)
- **程式碼**: `SF Mono`, `Menlo`

Web CSS stack：

```css
font-family: -apple-system, BlinkMacSystemFont,
             "SF Pro Text", "Segoe UI",
             "PingFang TC", "Microsoft JhengHei",
             sans-serif;
```

---

## 4. 氣質與語氣

- **Tone**: 直白、專業、溫度介於 Apple 官方與獨立工具中間
- **避免**: 感嘆號連發、行銷口吻浮誇用詞（「革命性」「顛覆」）、emoji 填充
- **偏好**: 具體動詞、量化承諾（「0 個第三方 SDK」、「1 tap save」）

範例對照：

| ❌ 不要 | ✅ 要 |
|---|---|
| 革命性的翻譯體驗！ | 四種翻譯方式，一個 App 搞定 |
| AI 超強大🚀 | 由 Apple Neural Engine 驅動 |
| 你的隱私對我們很重要 | 0 個伺服器、0 個分析工具、0 個廣告 |

---

## 5. 資產清單

| 檔案 | 用途 | 尺寸 |
|---|---|---|
| `AppIcon.svg` | 源檔，所有衍生品之根 | 1024×1024 (viewBox) |
| `AppIcon-1024.png` | App Store Connect 上傳 | 1024×1024 |
| `AppIcon-180.png` | iPhone 60pt @3x | 180×180 |
| `AppIcon-120.png` | iPhone 60pt @2x | 120×120 |
| `AppIcon-60.png` | Home Screen mock | 60×60 |
| `AppIcon-512.png` | Marketing / README | 512×512 |

（Xcode 16+ 只需要 1024×1024；其他尺寸 Xcode 會自動生成。這裡多備是給 landing page / social 用）

---

**版本**: 1.0 · **建立**: 2026-04-21
