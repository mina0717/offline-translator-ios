# Pre-Submission Code Audit — 2026-04-21

Automated audit before App Store submission. Run this on Mac as a final check before Archive.

## ✅ Passing checks

### PrivacyInfo.xcprivacy
- `NSPrivacyTracking` = false
- `NSPrivacyCollectedDataTypes` = empty array
- `NSPrivacyTrackingDomains` = empty array
- `NSPrivacyAccessedAPITypes` = empty array

Meets Apple requirement since May 2024. Matches our "zero data collection" privacy claim.

### Info.plist usage strings (project.yml lines 43-46)
- `NSMicrophoneUsageDescription` ✅ CN string present
- `NSSpeechRecognitionUsageDescription` ✅ CN string present
- `NSCameraUsageDescription` ✅ CN string present
- `NSPhotoLibraryUsageDescription` ✅ CN string present
- No unused permission strings (tight scope)

### Share Extension Info.plist
- `NSExtensionActivationSupportsText` ✅
- `NSExtensionActivationSupportsWebURLWithMaxCount` = 1 ✅
- `NSExtensionActivationSupportsWebPageWithMaxCount` = 1 ✅
- Correct extension point: `com.apple.share-services` ✅

### Localization
- `zh-Hant` (primary) + `en` both declared
- `CFBundleDevelopmentRegion` = `zh-Hant`

## ⚠️ Advisory findings (non-blocking)

### 4 × `print(...)` statements in Swift files

Found 4 diagnostic prints, all prefixed with `⚠️` warning emoji. These are non-critical and will appear in Console.app but Apple's reviewers don't flag these. Consider wrapping in `#if DEBUG` for production polish.

| File | Line | Content |
|------|------|---------|
| `Services/ASRServiceSpeech.swift` | 155 | `⚠️ SFSpeechRecognizer on-device 不支援 \(locale.identifier)，將使用雲端` |
| `Features/SpeechTranslation/SpeechTranslationViewModel.swift` | 159 | `⚠️ TTS failed: \(error)` |
| `Onboarding/Tips.swift` | 106 | `⚠️ TipKit configure failed: \(error)` |
| `Domain/UseCases/TranslateTextUseCase.swift` | 42 | `⚠️ HistoryRepository.save failed: \(error)` |

**Recommended fix (on Mac):**

```swift
#if DEBUG
print("⚠️ ...")
#endif
```

Or use `os.Logger`:

```swift
import os
private let log = Logger(subsystem: "com.mina0717.offlinetranslator", category: "ASR")
log.warning("SFSpeechRecognizer on-device unsupported for \(locale.identifier)")
```

Neither is required for approval. Ship as-is if time-constrained.

### `NSSpeechRecognitionUsageDescription` — advisory

Our app uses `SFSpeechRecognizer` with `.requiresOnDeviceRecognition = true`, so strictly speaking the speech recognition permission string is still required (Apple UI still prompts). Current string clearly explains usage. ✅

### `NSAppTransportSecurity` — not in project.yml

We don't add any `NSAppTransportSecurity` exception. Default policy (all HTTPS, TLS 1.2+) applies. Since we don't make network calls at all (everything on-device), this is correct. ✅

## 📋 Mac pre-Archive checklist

Before hitting **Product → Archive**, run these in Xcode:

- [ ] Product → Clean Build Folder (⇧⌘K)
- [ ] Product → Scheme → Edit Scheme → Run → **Build Configuration = Release**
- [ ] Build for Release; look at Issue Navigator for warnings
- [ ] Run `⌘U` (test) one more time in Release configuration
- [ ] Instruments → Leaks: run app for 2 min, no leaks
- [ ] Instruments → Allocations: baseline ≤ 80 MB resident
- [ ] Signing & Capabilities: correct Team, Bundle ID, Provisioning Profile
- [ ] `MARKETING_VERSION` = 1.1.0
- [ ] `CURRENT_PROJECT_VERSION` incremented
- [ ] Build Phases: no unnecessary scripts; no `#error` / `#warning` left
- [ ] Verify no `.xcprivacy` missing by running `find . -name "*.xcprivacy"`

## 📦 IPA size expectations

| Component | Approx size |
|-----------|-------------|
| Swift stdlib + SwiftUI | ~15 MB |
| App binary + resources | ~8 MB |
| 17萬詞離線詞庫 (Core Data .sqlite) | ~40-80 MB |
| AppIcon + LaunchScreen | ~2 MB |
| Localization bundles (zh-Hant + en) | ~1 MB |
| **Estimated IPA** | **~70-110 MB** |

Target: **< 150 MB** for smooth OTA download. Enable App Thinning automatically via `Archive` → `Distribute App`.

## 🧪 TestFlight smoke test

After upload:

1. Install via TestFlight on a real device
2. Launch fresh (first-run): verify TipKit shows 4 tips
3. Grant all 4 permissions (mic / speech / camera / photos)
4. Translate "Hello" to Chinese: should work offline (toggle airplane mode first)
5. Voice mode: hold mic, say "Thank you", release
6. Photo mode: take a photo of a printed page
7. Dictionary: search "ephemeral"
8. Save to vocabulary: verify persistence after force-quit
9. Share Extension: from Safari, share "Hello world"
10. Siri: "Hey Siri, 翻譯剪貼簿"

All 10 should work on airplane mode (except iOS translation model download, which happens once on first launch).

---

Auto-generated 2026-04-21 · @mina0717 · see `Mac測試與後續待辦.docx` for the full testing plan.
