# 📰 Press Kit — Offline Translator（離線翻譯）

給記者、部落客、Podcast 主持人的一頁式資料。

> **最後更新：2026-10-15。** 本文件已依 App 實際功能重寫；舊版（v1.1 時期草稿）有多處與事實不符，已移除。
> App Store 目前上架版本為 **1.3.0**；**1.5.0 已送審，通過後自動上線**。標註「1.5.0」的內容在上線前尚未對外提供。

---

## 🎯 One-Line Pitch

**EN:** A privacy-first iPhone translator for 14 languages — text, voice, face-to-face conversation and camera — that runs on the device, with no ads, no accounts and no data collection.

**CN:** 一款隱私優先的 iPhone 離線翻譯 App：文字、語音、雙向對話、相機翻譯，14 種語言，翻譯在裝置本地運算，沒有廣告、不用註冊、不收集資料。

---

## 🏷 Product Facts

| Field | Value |
|-------|-------|
| **Product name** | Offline Translator（離線翻譯） |
| **Platform** | iPhone only · iOS 18.0+（土耳其文翻譯需 iOS 18.4+） |
| **Price** | Free · No ads · No in-app purchases · No account |
| **Languages** | 14 種，任兩種可互譯（共 182 個方向）：繁體中文、English、日本語、한국어、Deutsch、Français、Español、ไทย、Tiếng Việt、Português、Italiano、Bahasa Indonesia、Nederlands、Türkçe |
| **Translation engine** | Apple 系統 Translation 框架（語言包由 iOS 下載，下載後可離線使用） |
| **Language pack size** | 由 iOS 系統下載，依語言而異（約 80 MB 起） |
| **UI languages** | 繁體中文 / English（App 內可切換） |
| **Developer** | PEI HSUAN CHIANG（江珮瑄）· AI-FANS.TW · Made in Taiwan 🇹🇼 |
| **First App Store release** | 2026-04-30（v1.2.12） |
| **Live on App Store** | 1.3.0（14 種語言、App 內語言切換） |
| **In review** | 1.5.0（見下方「1.5.0 新增」） |
| **Bundle ID** | com.mina0717.offlinetranslator |
| **Source code** | 公開於 GitHub（目前 repo 尚未附開源授權條款） |

---

## ✅ What it does

- **文字翻譯** — 輸入即譯，可把翻譯收進單字本。
- **語音翻譯** — 按住說話、放開即譯。
- **雙向對話** — 手機平放在兩人之間，畫面上下分割，上半部旋轉 180° 給對方看。
- **相機翻譯** — 鏡頭對準招牌、菜單，譯文即時疊在原文位置（1.5.0；1.3.0 為「拍照翻譯」，從相機或相簿取圖）。
- **分享擴充 / Siri 捷徑** — 在 Safari、備忘錄等 App 選字直接翻譯；支援「翻譯文字」「翻譯剪貼簿」捷徑。
- **歷史紀錄、單字本**。

### 1.5.0 新增（審查中，通過後自動上線）

- **相機翻譯**取代原本分開的「拍照翻譯」與「相機翻譯」：即時疊字、快門拍單張、也可從相簿選圖。
- **免持聆聽** — 不用按住按鈕，App 聽對方說話並把譯文顯示在螢幕上。
- **預設翻譯模式** — 使用者可指定開啟 App 時直接進入哪個功能。
- **意見回饋** — 從 App 內寄 Email 給開發者。

---

## 🔐 Privacy（可查證的部分）

- App 的隱私清單（`PrivacyInfo.xcprivacy`）宣告：**不追蹤、不收集任何資料類型**。
- 原始碼中**沒有**使用 `URLSession` 等網路請求；**沒有**任何第三方分析、當機回報或廣告 SDK。
- 翻譯由 Apple 的 Translation 框架在裝置上執行；語言包需先由 iOS 下載一次（這一步由系統處理，不經過本 App）。
- 語音辨識使用 Apple 的 Speech 框架，**在裝置支援時強制使用裝置端辨識**；OCR 使用 Apple Vision 框架。
- 唯一會把內容寄出的功能是「意見回饋」，且是使用者自己在郵件畫面按送出。

---

## 📸 Press Release（EN）

### FOR IMMEDIATE RELEASE

**An iPhone translator that works offline — and doesn't collect your words.**

*Taiwan — Offline Translator*, a free iPhone app by independent developer PEI HSUAN CHIANG (AI-FANS.TW), translates between 14 languages with text, voice, face-to-face conversation and camera modes. Translation runs on the device through Apple's Translation framework; once a language pack is downloaded, the app works in airplane mode. The app has no ads, no accounts and no in-app purchases, and its privacy manifest declares no tracking and no collected data.

The app first reached the App Store on 2026-04-30. The current App Store version (1.3.0) added 14 languages and an in-app interface-language switch; version 1.5.0, now in review, merges photo and live camera translation into a single camera mode, adds hands-free listening, and lets users choose which mode the app opens to.

**Developer contact:** see "Interview requests" below.

**###**

---

## 📸 Press Release（CN）

### 即時發布

**一款真正能離線使用的 iPhone 翻譯 App — 不收集你的資料。**

*台灣 —《離線翻譯》*是獨立開發者江珮瑄（AI-FANS.TW）開發的免費 iPhone App，提供文字、語音、雙向對話與相機四種翻譯方式，支援 14 種語言互譯。翻譯透過 Apple 的 Translation 框架在裝置本地執行，語言包下載後，飛航模式也能使用。App 沒有廣告、不需註冊、沒有內購，隱私清單宣告不追蹤、不收集任何資料。

App 於 2026-04-30 首次上架 App Store。目前上架的 1.3.0 版新增 14 種語言與 App 內介面語言切換；送審中的 1.5.0 版將「拍照翻譯」與「相機翻譯」合併為單一相機模式，並新增免持聆聽與「預設翻譯模式」。

**開發者聯絡：** 請見下方「採訪邀約」。

**###**

---

## 🎨 Visual Assets

以下檔案都在 repo 內：

- **App icon**（1024×1024 PNG；SVG 原檔）：`/brand/AppIcon-1024.png`、`/brand/AppIcon.svg`
- **IG 貼文卡片** ×5（1080×1080 PNG）：`/ig-cards/01-cover.png` … `/ig-cards/05-cta.png`
- **截圖範本** ×5（1290×2796 PNG）：`/marketing/screenshot-template/01-hero.png` … `05-privacy.png`
- **品牌規範**（色彩、字體、語氣）：`/brand/BRAND_GUIDELINES.md`

> ⚠️ **上述 IG 卡片與截圖範本是 v1.1 時期製作**，部分畫面仍含已不符現況的字眼（例如「字典」「四種翻譯：文字/語音/拍照/字典」）。**對外使用前請先確認，或改用 App Store 上最新的截圖。**

**品牌色：** Deep Navy `#0B1438` · Accent Cyan `#5EE2D7` · Accent Coral `#FF6B6B`

---

## ❓ FAQ for journalists

**Q：沒有廣告也沒有內購，怎麼維持？**
A：翻譯在使用者的手機上執行，沒有伺服器要養。成本主要是開發者的時間。

**Q：Apple 的 Translation 框架真的能離線嗎？**
A：能。語言包下載後翻譯就在裝置上進行；可以開飛航模式驗證。首次下載語言包需要網路，這一步由 iOS 系統處理。

**Q：為什麼公開原始碼？**
A：讓使用者與記者能自行檢查程式有沒有把內容送出去。

**Q：有 Android 版嗎？**
A：沒有。

**Q：誰在做這個 App？**
A：獨立開發者一人，台灣。

---

## 📩 Interview requests

<!-- TODO(Mina)：Email 已確認為 lb0018575@gmail.com；Twitter／Threads 帳號沿用舊版文件，尚未查證。 -->
- **Email**: [lb0018575@gmail.com](mailto:lb0018575@gmail.com)
- **Twitter/X**: [@mina0717](https://twitter.com/mina0717)
- **Threads**: [@mina0717](https://threads.net/@mina0717)
- **GitHub**: [mina0717](https://github.com/mina0717)

---

## 🔗 Links

- **官方介紹頁**：<https://mina0717.github.io/offline-translator-ios/>
- **隱私權政策**：<https://mina0717.github.io/offline-translator-ios/privacy.html>
- **GitHub**：<https://github.com/mina0717/offline-translator-ios>
- **Release 版本紀錄**：<https://github.com/mina0717/offline-translator-ios/releases>

---

最後更新 2026-10-15 · @mina0717
