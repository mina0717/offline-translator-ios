# Offline Translator (iOS MVP)

兩週版 iOS 離線翻譯 App。MVP 範圍：文字翻譯、語音翻譯（按住說話）、拍照翻譯、離線語言包管理、歷史紀錄。

- **平台**：iOS 17.4+ (iPhone only)
- **語言**：Swift 5.10 / SwiftUI
- **架構**：SwiftUI + MVVM + Use Case + Repository
- **翻譯引擎**：Apple Translation framework（離線）
- **OCR**：Apple Vision
- **ASR**：Apple Speech
- **TTS**：AVSpeechSynthesizer
- **持久層**：SwiftData
- **語言對**：繁中⇄英（MVP v0.1 縮減範圍，日文延至 v1.1）

---

## 一、第一次跑起來

### 1. 安裝 XcodeGen

```bash
brew install xcodegen
```

### 2. 產生 .xcodeproj

```bash
cd OfflineTranslator
xcodegen generate
```

### 3. 打開專案 + Run

```bash
open OfflineTranslator.xcodeproj
```

預設使用 **Mock 服務**（`AppDependencies.makeMock()`），所以：

- 文字翻譯：可端到端跑通，譯文會加上 `[zh-Hant→en]` 之類前綴
- 語音 / 拍照：UI 看得到、但功能還沒實作
- 歷史紀錄：每次文字翻譯都會寫入並顯示

切換到真引擎：把 `OfflineTranslatorApp.swift` 裡的
```swift
@StateObject private var deps = AppDependencies.makeMock()
```
改成
```swift
@StateObject private var deps = AppDependencies.makeDefault()
```

### 4. 你還需要做的事
- 在 `project.yml` 裡填上你的 `DEVELOPMENT_TEAM` ID
- 視需要修改 `PRODUCT_BUNDLE_IDENTIFIER`（目前是 `com.placeholder.OfflineTranslator`）
- 改完後重跑 `xcodegen generate`

---

## 二、專案結構

```
OfflineTranslator/
├── App/                       # @main、RootView、依賴注入容器
├── DesignSystem/              # 色票、玻璃卡、漸層背景
├── Domain/
│   ├── Models/                # Language, LanguagePair, TranslationResult
│   └── UseCases/              # TranslateTextUseCase, SpeechTranslateUseCase, …
├── Services/                  # MTService / OCRService / ASRService / TTSService
│                              # 每個都有 protocol + Mock + 真實作 stub
├── Data/
│   ├── Store/                 # SwiftData @Model
│   ├── Repositories/          # HistoryRepository, LanguagePackRepository
│   └── SwiftDataContainer    # ModelContainer 單例
├── System/                    # PermissionManager
├── Features/
│   ├── Home/                  # 首頁（四入口 + 歷史紀錄）
│   ├── TextTranslation/       # ✅ 完整實作 (MVVM)
│   ├── SpeechTranslation/     # ✅ 完整實作（按住說話 + 自動 TTS）
│   ├── PhotoTranslation/      # ✅ 完整實作（相機/相簿 + OCR + 翻譯）
│   ├── LanguagePack/          # ✅ 完整實作（狀態檢查 / 下載 / 引導設定）
│   └── History/               # ✅ 完整可運作
└── Resources/                 # Info.plist, Assets.xcassets
```

---

## 三、Day-by-Day 排程（對齊原計劃）

| Day | 工作 | 對應目錄 / 檔案 |
|---|---|---|
| 1 | ✅ 範圍 / 技術 / UI 風格定案 | （已完成） |
| 2–3 | ✅ 專案骨架、SwiftData、歷史紀錄底層 | `Data/`, `App/`, `DesignSystem/` |
| 4–5 | ✅ 文字翻譯串 Apple Translation | `Services/MTServiceApple.swift`, `Features/TextTranslation/` |
| 6–7 | ✅ 語音翻譯（ASR + 翻譯 + TTS） | `Services/ASRServiceSpeech.swift`, `Features/SpeechTranslation/` |
| 8–9 | ✅ 拍照翻譯（Vision OCR + 翻譯） | `Services/OCRServiceVision.swift`, `Features/PhotoTranslation/` |
| 10 | ✅ 語言包管理（下載 / 引導刪除 / 狀態） | `Domain/UseCases/ModelManager.swift`, `Features/LanguagePack/` |
| 11–12 | ✅ 整合測試、UI 微調、權限流程、無障礙標籤 | 全 App |
| 13 | ✅ P3 Polish（OCR resize、觸覺、重試、字數、隱私聲明、在地化骨架、UseCase 測試） | `Services/OCRServiceVision.swift`、`Features/**/*View.swift`、`Resources/PrivacyInfo.xcprivacy`、`Resources/**/Localizable.strings` |
| 13.5 | 🟡 QA、修 bug、效能檢查（需實機驗證） | `OfflineTranslatorTests/`, `docs/E2E.md` |
| 14 | ⬜ 打包 Demo (5/3 交付) | — |

---

## 四、設計原則 (寫程式時請遵守)

1. **UI 不能直接呼叫 Service**：UI → ViewModel → UseCase → Service → Repository
2. **依賴透過 protocol 注入**：所有 Service / Repository 都有對應 protocol，方便寫測試
3. **顏色 / 字型 / 圓角全走 `Theme`**：禁止 View 內硬寫色碼
4. **任何卡片型容器一律包 `.glassCard()`**：保持淺粉紫漸層 + 玻璃感一致
5. **錯誤要走 `LocalizedError`**：UI 才能直接顯示 `errorDescription`

---

## 五、測試

```bash
xcodebuild test \
  -project OfflineTranslator.xcodeproj \
  -scheme OfflineTranslator \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

目前已有（共 9 個測試檔案）：
- `LanguageTests`：語言對覆蓋測試
- `TranslateTextUseCaseTests`：文字翻譯 happy / empty / unsupported / error path
- `PhotoTranslateUseCaseTests`：拍照翻譯 UseCase — OCR 透傳、merge 多行、空輸入 / unsupported / history 失敗容忍
- `SpeechTranslateUseCaseTests`：語音翻譯 UseCase — ASR 串流、stop / translate trim / tts 透傳
- `TextTranslationViewModelTests`：VM 的 translate / swap / autoDetect / clear
- `SpeechTranslationViewModelTests`：按住錄音 → 翻譯 → 自動 TTS 全流程
- `PhotoTranslationViewModelTests`：OCR 成功 / 失敗 / swap / clear
- `LanguagePackViewModelTests`：reload / download / cancellation / remove 引導
- `HistoryViewModelTests`：reload / clearAll / repository 失敗

Service 層真實作（`MTServiceApple`、`ASRServiceSpeech`、`OCRServiceVision`、`TTSServiceAVFoundation`）因依賴 iOS 系統 framework，需在實機 / 模擬器上做整合測試，見 `docs/E2E.md`。

---

## 六、已知 TODO（借到 Mac + 實機後要驗的項目）

完整檢查表請見 `docs/E2E.md`。簡版：

- [ ] Mac 上裝 XcodeGen 並 `xcodegen generate` 能生成 `.xcodeproj`
- [ ] 填入 `DEVELOPMENT_TEAM` 後能在模擬器跑起來
- [ ] Mock 模式下 Home → 四個入口 → 歷史紀錄全部能點開不 crash
- [ ] 切到 `makeDefault()` 後：
    - [ ] 文字翻譯：第一次會觸發 Apple Translation 下載 sheet
    - [ ] 語音翻譯：會跳麥克風 + 語音辨識權限對話框
    - [ ] 拍照翻譯：會跳相機 + 相簿權限對話框
    - [ ] 飛航模式下文字翻譯依然能運作（驗證「離線」承諾）
- [ ] 語言包頁：下載/引導到設定刪除流程 OK
- [ ] 跑完整 XCTest suite，全部綠燈
