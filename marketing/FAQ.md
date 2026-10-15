# 常見問題 FAQ — 離線翻譯 Offline Translator

最後更新：2026-10-15 · @mina0717

雙語 FAQ（繁中 + English）。本文件已依 App 實際功能重寫；舊版（v1.1 時期草稿）有多處與事實不符，已移除。

> App Store 目前上架版本為 **1.3.0**；**1.5.0 已送審，通過後自動上線**。標註「（1.5.0）」的功能在上線前尚未提供。
> 意見回饋：1.5.0 起可在 App「設定」內以 Email 回報；在此之前請到 [GitHub Issues](https://github.com/mina0717/offline-translator-ios/issues)。

---

## 🇹🇼 繁體中文

### 🔐 關於隱私

**Q1. 真的是離線嗎？**
翻譯由 Apple 的 Translation 框架在你的 iPhone 上執行。每個語言第一次使用前，需要由 iOS 系統下載「語言包」（這一步需要網路，由系統處理）；下載完成後，翻譯、拍照／相機翻譯的文字辨識都不需要網路，飛航模式也能用。

**Q2. 你有在收集我的使用資料嗎？**
沒有。App 隱私清單（`PrivacyInfo.xcprivacy`）宣告：不追蹤（`NSPrivacyTracking` = false）、不收集任何資料類型（`NSPrivacyCollectedDataTypes` 為空）。原始碼公開在 GitHub，程式碼裡沒有 `URLSession` 等網路請求。

**Q3. 有分析或當機回報 SDK 嗎？**
沒有。沒有 Firebase、Crashlytics、Mixpanel、Amplitude 或廣告 SDK，也沒有任何第三方套件。

**Q4. 第一次要下載語言包，那算不算用網路？**
算，但那是 iOS 系統級的下載，由 Apple 處理，App 不會上傳你輸入的內容。大小依語言而異（約 80 MB 起）。下載後即可離線使用；可在 iPhone「設定 → App → 翻譯」管理語言。

**Q5. 語音辨識也是離線嗎？**
App 會優先使用「裝置端辨識」，但是否可用取決於你的 iPhone 與該語言：
- **免持模式**（雙向對話的免持、1.5.0 的免持聆聽）：若該語言沒有裝置端辨識，App 不會啟動，不會偷偷改用雲端。
- **按住說話**：優先使用裝置端辨識；如果你的 iPhone 對該語言沒有裝置端辨識，iOS 可能改用 Apple 的語音辨識服務（需要網路）。

---

### 📱 功能使用

**Q6. 支援哪些語言？**
14 種，任兩種都能互譯（共 182 個方向）：繁體中文、English、日本語、한국어、Deutsch、Français、Español、ไทย、Tiếng Việt、Português、Italiano、Bahasa Indonesia、Nederlands、Türkçe（土耳其文翻譯需要 iOS 18.4 以上）。

**Q7. 有哪些翻譯方式？**
- **文字翻譯**：輸入即譯，可把翻譯收進單字本。
- **語音翻譯**：按住說話，放開即譯。
- **雙向對話**：手機平放兩人之間，畫面上下分割，上半部旋轉 180° 給對方看。
- **相機翻譯**：鏡頭對準文字，譯文疊在原文位置。（1.3.0 為「拍照翻譯」，從相機或相簿取圖；1.5.0 合併為一個相機模式，可即時疊字、按快門拍單張、從相簿選圖。）
- **免持聆聽**（1.5.0）：不用按住按鈕，App 聽對方說話，把譯文顯示在螢幕上。

**Q8. 相機翻譯找不到字？**
確認光線充足、字體清楚、鏡頭乾淨。手寫字、斜體、低對比的字可能辨識不到；可以改用拍照（快門）取單張，或先用相機拍一張清楚的照片再從相簿匯入。

**Q9. 單字本可以匯出嗎？**
目前**不能**匯出。單字本是 App 內的收藏清單，用來把翻譯存起來之後回頭看。

**Q10. Siri 捷徑怎麼用？**
App 提供兩個捷徑：「翻譯文字」和「翻譯剪貼簿」，可在「捷徑」App 找到，也可以對 Siri 說「用 離線翻譯 翻譯剪貼簿」。

**Q11. 分享擴充（Share Extension）怎麼用？**
在 Safari、備忘錄等 App 選取文字 → 點「分享」→ 選「離線翻譯」。

**Q12. 可以設定開啟 App 就直接進入某個功能嗎？**（1.5.0）
可以。在 App「設定」的「啟動畫面」→「開啟 App 時直接進入」選一個功能，或在主畫面長按某個功能卡片選「設為啟動畫面」。設定後，開啟 App 會直接進入該功能，按返回仍可回到主畫面；在設定中改回「主畫面」，或長按選「取消設為啟動畫面」即可還原。

**Q13. 介面可以改成英文嗎？**
可以。「設定」內的「介面語言」可選 跟隨系統／繁體中文／English，立即生效，不用重開 App。

---

### 💰 費用

**Q14. 要錢嗎？**
免費。沒有廣告、沒有內購、不用註冊帳號。

**Q15. 為什麼能免費？**
翻譯在你的手機上執行，沒有伺服器要維護。

---

### 🔧 技術問題

**Q16. 支援哪些 iOS 版本？**
iOS 18.0 以上。土耳其文翻譯需要 iOS 18.4 以上。

**Q17. 支援 iPad / Apple Watch 嗎？**
App 只針對 iPhone 設計，沒有 iPad 專用版面，也沒有 Apple Watch 版。

**Q18. 翻譯品質比 Google / DeepL 差嗎？**
可能。這個 App 使用 Apple 的系統翻譯，適合旅遊、訊息、菜單等日常場景；需要高精準度的專業文件，建議搭配人工校對或其他工具。

---

### 🛠 故障排除

**Q19. 翻譯卡住或沒有結果？**
- 第一次使用某個語言需要網路下載語言包，請先連線下載
- 到 iPhone「設定 → App → 翻譯」確認語言已下載
- 重新啟動 App
- 還是不行？到 [GitHub Issues](https://github.com/mina0717/offline-translator-ios/issues) 回報（1.5.0 起也可從 App「設定」寄 Email）

**Q20. 提示「不支援語音辨識」？**
該語言在你的 iPhone 上可能沒有裝置端辨識（見 Q5）。換一種語言，或升級 iOS 試試。

---

### 💻 開發者相關

**Q21. 開源了嗎？**
原始碼公開在 GitHub：https://github.com/mina0717/offline-translator-ios 。目前 repo 尚未附上開源授權條款，因此請先聯絡開發者再轉用程式碼。

**Q22. 想支持這個 App？**
App 內沒有贊助或付費功能。如果覺得好用，歡迎在 App Store 留個評價、在 GitHub 按星，或推薦給朋友。

---

## 🇬🇧 English

> Live on the App Store: **1.3.0**. **1.5.0 is in review** and will be released automatically once approved; items marked "(1.5.0)" are not available until then.

### 🔐 Privacy

**Q1. Is it really offline?**
Translation runs on your iPhone through Apple's Translation framework. The first time you use a language, iOS downloads a language pack (this needs a network connection and is handled by the system). After that, translation and the on-device text recognition used by the camera need no network — airplane mode works.

**Q2. Do you collect any usage data?**
No. The privacy manifest (`PrivacyInfo.xcprivacy`) declares no tracking (`NSPrivacyTracking` = false) and no collected data types (`NSPrivacyCollectedDataTypes` is empty). The source is public on GitHub, and the code contains no `URLSession` or other network requests.

**Q3. Any analytics or crash-reporting SDKs?**
None — no Firebase, Crashlytics, Mixpanel, Amplitude, ad SDKs or other third-party packages.

**Q4. The language pack download — doesn't that count as network use?**
Yes, but it's an iOS system download handled by Apple; the app never uploads what you type or say. Size varies by language (about 80 MB and up). Manage languages in Settings → Apps → Translate.

**Q5. Is speech recognition offline too?**
The app asks for on-device recognition, but availability depends on your iPhone and the language:
- **Hands-free modes** (hands-free conversation, and hands-free listening in 1.5.0): if on-device recognition isn't available for the language, the mode simply doesn't start — it never falls back to the cloud.
- **Hold to speak**: on-device recognition is preferred; if your iPhone has none for that language, iOS may use Apple's speech recognition service (which needs a network).

---

### 📱 Using the app

**Q6. Which languages?**
14, any pair (182 directions): Traditional Chinese, English, Japanese, Korean, German, French, Spanish, Thai, Vietnamese, Portuguese, Italian, Indonesian, Dutch, Turkish (Turkish needs iOS 18.4+).

**Q7. What translation modes are there?**
- **Text** — type to translate; save results to your vocabulary notebook.
- **Voice** — hold to speak, release to translate.
- **Conversation** — lay the phone flat between two people; the split screen puts the top half upside down for the other person.
- **Camera** — point at text and the translation is overlaid on the original. (1.3.0 has "Photo translation" from camera or library; 1.5.0 merges them into one camera mode with live overlay, a shutter for single shots, and photo-library import.)
- **Hands-free listening** (1.5.0) — no button to hold; the app listens to the other person and shows the translation on screen.

**Q8. Camera can't find the text?**
Use good light, clear text, a clean lens. Handwriting, italics and low-contrast text may be missed — try the shutter for a single shot, or take a clear photo first and import it.

**Q9. Can I export my vocabulary notebook?**
Not currently. The notebook is an in-app list of saved translations.

**Q10. Siri shortcuts?**
Two shortcuts: "Translate text" and "Translate clipboard" — find them in the Shortcuts app, or ask Siri, e.g. "Translate clipboard with 離線翻譯".

**Q11. Share Extension?**
Select text in Safari, Notes, etc. → Share → 離線翻譯.

**Q12. Can the app open straight into my favorite mode?** (1.5.0)
Yes. In Settings, under "On Launch", pick a feature for "Open on launch" — or long-press a tile on the home screen and choose "Open on launch". Back still returns to the home screen. To undo, set it to "Home screen" or long-press and choose "Stop opening on launch".

**Q13. Can I switch the interface to English?**
Yes — Settings → Language: System default / 繁體中文 / English. It applies immediately, no restart.

---

### 💰 Pricing

**Q14. Does it cost anything?** Free. No ads, no in-app purchases, no account.

**Q15. Why is it free?** Translation runs on your phone, so there's no server to maintain.

---

### 🔧 Technical

**Q16. Which iOS versions?** iOS 18.0 or later (Turkish needs 18.4+).

**Q17. iPad / Apple Watch?** The app is designed for iPhone only; there's no iPad layout and no Apple Watch app.

**Q18. Is quality worse than Google/DeepL?** Possibly. It uses Apple's system translation, which suits travel, messages and menus. For professional documents, add human review or another tool.

---

### 🛠 Troubleshooting

**Q19. Translation hangs or returns nothing?**
- The first use of a language needs a network connection to download its language pack
- Check Settings → Apps → Translate to confirm the language is downloaded
- Restart the app
- Still broken? Open an issue on [GitHub](https://github.com/mina0717/offline-translator-ios/issues) (from 1.5.0 you can also email feedback from the app's Settings)

**Q20. "Speech recognition not supported"?**
That language may lack on-device recognition on your iPhone (see Q5). Try another language or update iOS.

---

### 💻 For developers

**Q21. Open source?** The source is public at https://github.com/mina0717/offline-translator-ios . The repo doesn't include an open-source license yet, so please contact the developer before reusing the code.

**Q22. Want to support the app?** There is no sponsorship or paid feature in the app. A review on the App Store, a star on GitHub, or telling a friend all help.

---

最後更新 2026-10-15 · @mina0717
