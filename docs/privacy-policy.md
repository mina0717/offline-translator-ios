# 離線翻譯 — 隱私政策

**最後更新：2026-04-29**

「離線翻譯」（以下簡稱「本 App」）是一款完全離線運作的翻譯工具。我們重視你的隱私，本政策說明本 App 如何處理你的資料。

## 1. 我們不收集個人資料

本 App **不收集、不上傳、不儲存任何使用者個人資料到我們的伺服器**。

具體來說：
- 你輸入的翻譯文字
- 你錄音的語音內容
- 你拍的照片
- 你的翻譯歷史紀錄
- 你的裝置識別碼

以上所有資料**只存在你的 iPhone 本機**，本 App 開發者**完全無法存取**。

## 2. 本機處理的資料

本 App 使用以下 Apple 系統服務，所有處理都在你的裝置上完成：

| 服務 | 用途 | 資料流向 |
|---|---|---|
| Apple Translation Framework | 文字翻譯 | 完全本機 |
| Apple Speech Recognition | 語音轉文字（可選 on-device） | 預設本機；可關閉雲端 |
| Apple Vision Framework | 圖片文字辨識（OCR） | 完全本機 |
| AVSpeechSynthesizer | 文字轉語音（朗讀譯文） | 完全本機 |
| SwiftData | 翻譯歷史 / 收藏紀錄 | 只在本機 |

## 3. 權限使用說明

本 App 在使用以下功能時會請求相應權限：

- **麥克風 (NSMicrophoneUsageDescription)**：語音翻譯與雙向對話模式錄音
- **語音辨識 (NSSpeechRecognitionUsageDescription)**：將語音轉換成文字
- **相機 (NSCameraUsageDescription)**：拍照翻譯
- **相片 (NSPhotoLibraryUsageDescription)**：從相簿選擇照片進行翻譯

你可以隨時在「設定 → 離線翻譯」中關閉這些權限。

## 4. 網路使用

本 App 在以下情況會使用網路：

- **首次下載 Apple 語言包**：iOS 系統觸發的官方下載，不經本 App 處理
- **OS 更新檢查**：iOS 系統行為，與本 App 無關

除上述情況外，本 App 在你使用翻譯功能時**不會發送任何網路請求**。

## 5. 第三方服務

本 App **不使用任何第三方分析、廣告或追蹤服務**：
- ❌ 無 Google Analytics
- ❌ 無 Firebase
- ❌ 無廣告 SDK
- ❌ 無 Crashlytics
- ❌ 無任何第三方 SDK

## 6. 兒童隱私

本 App 適用所有年齡層使用，不會主動向 13 歲以下兒童收集個人資料。

## 7. 資料安全

由於本 App **不向開發者傳送任何資料**，你的隱私安全主要由 iOS 系統的本機加密與權限機制保障。請使用裝置密碼／Face ID 保護你的 iPhone。

## 8. 資料刪除

要刪除本 App 內的所有資料，只需從 iPhone 刪除本 App 即可。所有翻譯歷史、收藏紀錄會隨之刪除。

## 9. 政策變更

本政策可能會更新，最新版本永遠在這個 URL 上。如有重大變更會在 App 內通知。

## 10. 聯絡方式

對隱私政策有疑問，請透過以下方式聯絡：
- GitHub Issues: https://github.com/mina0717/offline-translator-ios/issues

---

# Privacy Policy (English)

**Last updated: 2026-04-29**

Offline Translator is a fully offline translation tool. We respect your privacy. This policy explains how the App handles your data.

## 1. No Personal Data Collection

We **do not collect, upload, or store any personal user data on our servers**.

This includes:
- Text you enter for translation
- Audio recordings
- Photos
- Translation history
- Device identifiers

All such data **stays on your iPhone**. The developer cannot access it.

## 2. On-Device Processing

The App uses Apple system frameworks that process all data on your device:
- Apple Translation Framework (text translation)
- Apple Speech Recognition (speech-to-text, on-device option)
- Apple Vision Framework (OCR)
- AVSpeechSynthesizer (text-to-speech)
- SwiftData (local history storage)

## 3. Permissions

- Microphone: voice translation, conversation mode
- Speech Recognition: speech-to-text conversion
- Camera: photo translation
- Photo Library: select photos for OCR

You can revoke these in Settings → Offline Translator.

## 4. Network Usage

The App only uses the network:
- When iOS system downloads Apple language packs (handled by iOS, not by us)
- For iOS update checks (system behavior)

The App makes **no network requests** during translation.

## 5. Third-Party Services

The App uses **no third-party analytics, ads, or tracking SDKs**.

## 6. Children's Privacy

The App is suitable for all ages and does not collect data from children under 13.

## 7. Data Security

Since no data leaves your device, your privacy depends on iOS device security. Use a passcode/Face ID.

## 8. Data Deletion

Deleting the App removes all stored data.

## 9. Policy Changes

The policy may be updated. The latest version is always at this URL.

## 10. Contact

GitHub Issues: https://github.com/mina0717/offline-translator-ios/issues
