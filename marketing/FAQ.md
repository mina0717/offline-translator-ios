# 常見問題 FAQ — Offline Translator v1.1

Last updated: 2026-04-22 · @mina0717

雙語 FAQ（繁中 + English）。任何問題歡迎在 [@mina0717](https://twitter.com/mina0717) 或 [mina0717@proton.me](mailto:mina0717@proton.me) 聯繫。

---

## 🇹🇼 繁體中文

### 🔐 關於隱私

**Q1. 真的 100% 離線嗎？**
是。翻譯、語音辨識、OCR 全部在你的 iPhone 本地運算。第一次使用 Apple Translation 時會下載「語言包」（約 40 MB），之後就不需要網路。你可以把飛航模式打開試試看 — 還是完全可以用。

**Q2. 你有在收集我的使用資料嗎？**
沒有。零。

打開 `PrivacyInfo.xcprivacy` 就知道：`NSPrivacyCollectedDataTypes` 是空陣列、`NSPrivacyTracking` 是 false。程式碼是 MIT 授權、公開的，你可以自己搜 `URLSession` 驗證沒有任何網路呼叫。

**Q3. 那當機回報 / 分析 SDK 呢？**
一個都沒有。沒有 Firebase、沒有 Crashlytics、沒有 Mixpanel、沒有 Amplitude。我刻意不裝，因為裝了就不是「真的隱私」。

**Q4. 我看到第一次使用要下載語言包，那算不算網路？**
那是 iOS 系統級的下載，由 Apple 處理，你可以在 iPhone「設定 → 一般 → 語言與地區 → 翻譯語言」管理。下載完就再也不用。App 本身從來不上傳你的輸入內容。

---

### 📱 功能使用

**Q5. 支援哪些語言？**
v1.1 主打 繁體中文 ↔ 英文。Apple Translation 框架也支援日文、韓文、西班牙文、法文、德文、義大利文、葡萄牙文、俄文、阿拉伯文、泰文、越南文、印尼文、簡體中文（共 20 種以上），iOS 17.4+ 完全相容。

**Q6. 17 萬詞的離線字典是什麼？**
一個整合自多份開源英漢字典、清理後塞進 Core Data 的本地詞庫。每個字附詞性、中文釋義、例句。查詢速度 < 50ms。

**Q7. 拍照翻譯怎麼用？**
相機對準文字（招牌、菜單、說明書都可以）→ 自動偵測文字區塊 → 翻譯出現在原字上方。用的是 Apple Vision 框架 + Apple Translation，全程離線。

**Q8. 語音模式按住說話是怎樣？**
長按麥克風開始錄音 → 說話 → 放開手指 → 自動辨識 + 翻譯。觸覺回饋會告訴你什麼時候開始錄、什麼時候結束。用的是 `SFSpeechRecognizer` + `.requiresOnDeviceRecognition = true`，完全本地。

**Q9. 詞彙本可以匯出嗎？**
可以。進入「詞彙本」→ 右上角「匯出」→ 選 CSV → 透過分享選單傳到 Mail、Notes、Files 都行。CSV 包含原文、譯文、收藏日期、分類。

**Q10. Siri 捷徑「翻譯剪貼簿」怎麼用？**
複製任何文字 → 對 Siri 說「翻譯剪貼簿」→ App 開啟並顯示翻譯結果。第一次用要先到 iOS 設定 → Siri 與搜尋 → Offline Translator → 允許。

**Q11. 分享擴充（Share Extension）怎麼用？**
在 Safari / 備忘錄 / 訊息 選取文字 → 點「分享」→ 找到「Offline Translator」→ 翻譯結果直接出現在 share sheet。

---

### 💰 費用與商業模式

**Q12. 為什麼完全免費？**
因為沒成本。沒有伺服器、沒有分析、沒有訂閱後台 — 翻譯都在你手機上跑。唯一成本是我的時間，這個我自願付出。

**Q13. 會不會改成訂閱制？**
不會。我對自己承諾 v1.x 系列永遠免費、永遠不加廣告。如果未來有商業需求（比如 Pro 版高級功能），會是另外一個 App，不會影響現有版本。

**Q14. 有內購嗎？**
沒有。IAP = 0，廣告 = 0，訂閱 = 0，登入畫面 = 0。

---

### 🔧 技術問題

**Q15. 支援 iOS 多少版本？**
最低 iOS 17.0。iOS 17.4+ 可用 Apple Translation 框架（推薦）；iOS 17.0-17.3 會 fallback 到 MLKit（速度略慢、翻譯品質稍差）。

**Q16. 支援 iPad / Apple Watch 嗎？**
iPad：v1.1 可運作但 UI 還沒針對 iPad 優化，v1.2 會加入 Split View 雙欄對照。
Apple Watch：目前沒有，v1.2 考慮加上 Watch App + 現場翻譯字幕。

**Q17. 翻譯品質比 Google / DeepL 差？**
可能是。Apple Translation 框架為日常溝通調校，不是文學級翻譯。需要高精準度時建議用 DeepL / Google。這個 App 定位是旅行、訊息、菜單、快速查詢 — 這類場景 Apple Translation 表現夠好、且不犧牲隱私。

**Q18. 我的 iPhone 電量會被吃很兇嗎？**
不會。所有模型都是 Apple 針對 Neural Engine 優化過的。翻譯 1000 字大約消耗 0.5-1% 電量。OCR 單張圖片約 0.1%。

---

### 🛠 故障排除

**Q19. 開 App 的時候語音辨識說不支援？**
有少數舊機種（iPhone 11 以前）on-device speech 支援不完整。App 會提示切換為雲端辨識 — 但為了保護隱私，我們直接停用該模式。解法：換台支援的機種，或升級 iOS。

**Q20. 拍照翻譯找不到字？**
確認光線充足、字清楚、iPhone 鏡頭乾淨。如果字是手寫、斜體、或深色底淺色字，Vision 可能漏掉。建議先用手機相機拍張清楚的照片，再進來 App 匯入。

**Q21. 翻譯結果停住/卡住？**
- 關閉飛航模式（首次載入語言包需要網路）
- iOS 設定 → 一般 → 語言與地區 → 翻譯語言 → 下載對應語言
- 重新啟動 App
- 還是不行？發 issue 到 [GitHub](https://github.com/mina0717/offline-translator-ios/issues)

**Q22. 詞彙本的收藏不見了？**
v1.1 修掉了一個 race condition bug。如果你是從 v1.0 升上來，重啟 App 一次即可。未來會加 iCloud 同步（v1.2 目標）。

---

### 💻 開發者相關

**Q23. 開源了嗎？**
是。MIT 授權。https://github.com/mina0717/offline-translator-ios

**Q24. 為什麼開源？**
這樣你不用「相信我」。你可以自己看 code 確認沒有任何資料被偷偷送出去。這是「隱私是真的」的最誠實證明。

**Q25. 可以 fork / 自己編一個版本嗎？**
當然。MIT 授權。唯一要求是保留授權聲明。如果你做得更好，歡迎回來 PR。

**Q26. 想贊助你？**
謝謝，但請不要。我刻意不放贊助按鈕 — 這個 App 做給自己用、順便給朋友用。如果想支持，請：
- ⭐ 在 GitHub 按個 star
- 在 App Store 留個評價
- 跟一個朋友推薦

這三件事對我比金錢有意義。

---

## 🇬🇧 English

### 🔐 Privacy

**Q1. Is it really 100% offline?**
Yes. Translation, speech recognition, and OCR all run locally on your iPhone. On first use, Apple Translation downloads a ~40MB language pack; after that, no network. Turn on airplane mode and verify — the app still works.

**Q2. Do you collect any usage data?**
Zero. Open `PrivacyInfo.xcprivacy` and you'll see `NSPrivacyCollectedDataTypes` is an empty array and `NSPrivacyTracking` is false. The code is MIT-licensed; search for `URLSession` yourself to confirm there are zero network calls.

**Q3. What about crash reporting or analytics SDKs?**
None. No Firebase, Crashlytics, Mixpanel, or Amplitude. Intentionally omitted, because adding any of them would break the "privacy is real" claim.

**Q4. The first-time language pack download — doesn't that count as network?**
That's iOS system-level, handled by Apple. Manage it under Settings → General → Language & Region → Translation Languages. Once downloaded, never needed again. The app itself never uploads your input.

---

### 📱 Using the app

**Q5. Which languages are supported?**
v1.1 primary: Traditional Chinese ↔ English. Apple Translation also supports 20+ languages (Japanese, Korean, Spanish, French, German, Italian, Portuguese, Russian, Arabic, Thai, Vietnamese, Indonesian, Simplified Chinese, etc.) on iOS 17.4+.

**Q6. What's in the 170K-word dictionary?**
A curated merge of several open-source English-Chinese dictionaries, cleaned and loaded into Core Data. Each entry includes POS tags, Chinese glosses, and example sentences. Lookups < 50ms.

**Q7. How does photo translation work?**
Point your camera at text → Apple Vision detects text regions → Apple Translation translates → overlay appears. All on-device.

**Q8. What's "hold to speak"?**
Long-press the mic → speak → release. Haptic feedback tells you when recording starts and ends. Uses `SFSpeechRecognizer` with `.requiresOnDeviceRecognition = true`.

**Q9. Can I export my vocabulary notebook?**
Yes. Vocabulary → Export → CSV → share sheet. CSV includes source, translation, save date, category.

**Q10. How do I use the Siri shortcut?**
Copy text → say "Hey Siri, translate clipboard" → app opens with translation. First-time setup: Settings → Siri & Search → Offline Translator → allow.

**Q11. How does the Share Extension work?**
Select text in Safari/Notes/Messages → Share → Offline Translator → translation appears in the share sheet.

---

### 💰 Pricing & business model

**Q12. Why is it completely free?**
Because there are no costs. No servers, no analytics, no subscription backend — translation runs on your iPhone. The only cost is my time, and I donate it freely.

**Q13. Will it ever become a subscription?**
No. I've committed to keeping v1.x free forever with no ads. If I ever need to monetize, it'll be a separate Pro app — existing versions won't change.

**Q14. Any in-app purchases?**
None. IAP = 0, ads = 0, subscriptions = 0, sign-in screens = 0.

---

### 🔧 Technical

**Q15. Which iOS versions are supported?**
iOS 17.0 minimum. iOS 17.4+ uses Apple Translation framework (recommended). iOS 17.0-17.3 falls back to MLKit (slower, slightly lower quality).

**Q16. iPad / Apple Watch support?**
iPad: works in v1.1, no tablet-specific UI yet; v1.2 will add Split View dual-column. Apple Watch: not yet; v1.2 will consider adding a Watch app with live caption translation.

**Q17. Is translation quality worse than Google/DeepL?**
Possibly. Apple Translation is tuned for everyday communication, not literary translation. For high-precision work, use DeepL/Google. This app is built for travel, messages, menus, quick lookups — and for those, Apple Translation is plenty good *without* the privacy cost.

**Q18. Will it drain my battery?**
No. All models are optimized for Apple Neural Engine. Translating 1000 characters uses ~0.5-1% battery. OCR per image: ~0.1%.

---

### 🛠 Troubleshooting

**Q19. "Speech recognition not supported on this device"?**
Some older devices (pre-iPhone 11) have incomplete on-device speech support. To protect privacy, we disable cloud fallback. Fix: use a supported device or upgrade iOS.

**Q20. Photo OCR can't find text?**
Ensure good lighting, clear text, clean lens. Handwriting, italics, or low-contrast text may fail. Tip: take a clear photo first, then import.

**Q21. Translation hangs?**
- Enable network once to download language pack (Settings → General → Language & Region → Translation Languages)
- Restart app
- Still broken? File an issue: [GitHub](https://github.com/mina0717/offline-translator-ios/issues)

**Q22. My saved vocabulary disappeared?**
v1.1 fixed a race condition bug. If you upgraded from v1.0, restart once. iCloud sync coming in v1.2.

---

### 💻 For developers

**Q23. Open source?**
Yes. MIT license. https://github.com/mina0717/offline-translator-ios

**Q24. Why open source?**
So you don't have to trust me — read the code and confirm nothing leaves your phone.

**Q25. Can I fork it?**
Of course. MIT. Just keep the license. If you improve it, please PR back.

**Q26. Want to sponsor you?**
Please don't. I intentionally omitted the sponsor button. Instead:
- ⭐ Star on GitHub
- App Store review
- Tell one friend

Those three mean more to me than money.

---

**Still have questions?** → [@mina0717](https://twitter.com/mina0717) · [mina0717@proton.me](mailto:mina0717@proton.me)

Response time usually < 24 hours.

2026-04-22 · CC-BY 4.0 · Feel free to copy, translate, and share.
