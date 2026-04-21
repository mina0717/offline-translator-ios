# Changelog

All notable changes to **Offline Translator** (離線翻譯).
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] — 2026-04-21

### ✨ Added
- **📚 Vocabulary Notebook** — save any translation; browse by date; categorize; export CSV
- **🔗 Share Extension** — translate selected text from Safari, Notes, Messages, Mail
- **🎤 Hold-to-Speak gesture** — long-press the mic to record; release to translate; tactile haptic feedback
- **📣 Siri Shortcut integration** — `TranslateClipboardIntent` with `openAppWhenRun = true`
- **💡 TipKit onboarding** — 4 contextual tips (OCR, voice, dictionary, vocabulary)
- **🔠 Character counter** — live 5000-char limit with inline warning
- **↻ Retry button** — one-tap retry when translation fails (preserves last input)
- **📷 OCR image resize** — auto-downscale to 1024×1024 before Vision for speed + memory
- **🌙 Dedicated dark-mode palette** — not just color-inverted; hand-tuned for low-light reading
- **🇬🇧 Full English localization** — UI strings, error messages, empty states, onboarding

### 🔧 Changed
- Language packs page: improved a11y labels + VoiceOver descriptions
- Speech translation: UX polish on recording/canceling states
- Translation result card: added "Save to Vocabulary" CTA

### 🐛 Fixed
- **AppIntents** — `openAppWhenRun` now correctly launches the app when Siri runs the shortcut (Codex PR #1 fix)
- **Vocabulary Notebook** — race condition on concurrent reads/writes resolved via snapshot model (Codex PR #1 fix)
- **TextTranslation** — corrected character-count edge case at exactly 5000 chars
- **History view** — empty state no longer flickers on first launch

### 🛡 Security & Privacy
- `PrivacyInfo.xcprivacy` — complete manifest declaring zero tracking, zero data collection
- App Transport Security: all network calls blocked (100% on-device)
- No third-party SDKs · no analytics · no crash reporting · no ads

---

## [1.0.0] — 2026-04-15

### 🚀 Initial Release
- Four translation modes: Text · Voice · Photo · Dictionary
- On-device translation via Apple Translation framework (iOS 17.4+)
- MLKit fallback for iOS 17.0-17.3
- Live speech recognition via `SFSpeechRecognizer` (on-device)
- OCR via Apple Vision framework
- 170,000-word offline dictionary with POS tags and examples
- SwiftData-backed history with search and filters
- zh-Hant localization + English UI
- Full VoiceOver support + Dynamic Type + Dark Mode
- MIT License · open source on GitHub

---

## Release Notes — App Store (What's New)

### EN (v1.1)
```
What's new in 1.1:

• 📚 Vocabulary Notebook — save any translation, browse by date, export to CSV
• 🔗 Share Extension — translate from Safari, Notes, Messages, anywhere
• 🎤 Hold-to-Speak — long-press to record, release to translate, with haptics
• 📣 Siri Shortcut — "Translate clipboard" via voice
• 💡 TipKit onboarding — 4 quick tips for first-time users
• 🔠 Character counter & retry button — full UX polish
• 🌙 Dedicated dark-mode palette — hand-tuned, not just inverted
• 🇬🇧 Full English localization

Still: 0 data collection · 0 ads · 0 trackers · 100% offline.
```

### CN (v1.1)
```
v1.1 新功能：

• 📚 詞彙本 — 翻譯一鍵收藏，按日期瀏覽，匯出 CSV
• 🔗 分享擴充 — 從 Safari / 備忘錄 / 訊息 選字就翻
• 🎤 按住錄音 — 長按說話，放開即譯，含觸覺回饋
• 📣 Siri 捷徑 —「翻譯剪貼簿」語音快捷
• 💡 新手引導 — 4 組情境教學
• 🔠 字數上限 + 重試按鈕 — UX 全面打磨
• 🌙 深色模式專屬配色 — 人工調校，不只是反色
• 🇬🇧 完整英文介面

維持：零資料收集 · 零廣告 · 零追蹤 · 100% 離線。
```

[1.1.0]: https://github.com/mina0717/offline-translator-ios/releases/tag/v1.1.0
[1.0.0]: https://github.com/mina0717/offline-translator-ios/releases/tag/v1.0.0
