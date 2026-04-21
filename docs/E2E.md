# 端到端（E2E）驗證清單 — Offline Translator

> 目標：MVP 交付前（2026/5/4）必跑一次。分成
> **A. 純 Mock 驗證**（任何 Mac 即可）和
> **B. 真機驗證**（需要一支 iPhone + Apple Developer 帳號）。

---

## 一、前置動作（第一次拿到 Mac 時）

```bash
brew install xcodegen
cd OfflineTranslator
# 1) 填入 DEVELOPMENT_TEAM
#    project.yml → settings.base.DEVELOPMENT_TEAM = "<你的 Team ID>"
xcodegen generate
open OfflineTranslator.xcodeproj
```

在 Xcode 左上 scheme 選到 `OfflineTranslator`，目標選 `iPhone 15 Simulator`（或 17.4 以上），⌘R 跑起來。

若跑不起來，常見問題：
- `XcodeGen` 版本太舊 → `brew upgrade xcodegen`
- Bundle ID 撞到（你已經用過 `com.placeholder.OfflineTranslator`）→ 在 `project.yml` 改成自己的
- Deployment target 選到 < 17.4 → Apple Translation framework 不存在，翻譯會整個失敗

---

## 二、A. Mock 模式 E2E（模擬器即可）

`App/AppDependencies.swift` 預設 `makeMock()`。這條路不用權限、不用網路，就能跑通整個 UI 流程。

### A1. Home

- [ ] App 開啟後能看到 **「離線翻譯」** 標題 + 4 個卡片 + 歷史紀錄
- [ ] 點任一卡片能 push 進子頁面
- [ ] 回到 Home 不 crash

### A2. 文字翻譯（TextTranslation）

- [ ] 輸入 `你好` → 點「翻譯」按鈕 → 底下卡片出現 `[zh-Hant→en] 你好`
- [ ] 點「交換」箭頭：Source 從 zh-Hant → en，且原譯文被搬回 input
- [ ] 輸入空字串點翻譯 → 按鈕是 disabled 的（opacity=0.6）
- [ ] 輸入 `Hello` 後點「自動偵測」→ Source 變成 `英文`
- [ ] 輸入 `Hello` 點翻譯後，點「複製」→ 剪貼簿有值（可去 Notes app 貼一下驗證）
- [ ] 一次翻譯成功 → 回到 Home → 點「歷史紀錄」→ 看得到剛剛那筆

### A3. 語音翻譯（SpeechTranslation）

Mock 的 ASR 會逐字吐 `你好，這是一段測試語音。`

- [ ] 按住圓形麥克風 → 圖示變紅色、出現 `錄音中` 脈動點
- [ ] 畫面上方的辨識結果卡，逐字累加顯示（partial）
- [ ] 鬆開 → 辨識結果變 final → 下面出現譯文 `[zh-Hant→en] ...`
- [ ] 翻譯完 phase=.done，Mock TTS 的 log 會打 `lastSpokenText` 記到譯文
- [ ] 連續按三下快速按 → 不會重疊、不會 crash

### A4. 拍照翻譯（PhotoTranslation）

Mock OCR 回傳 `["Hello World", "This is a mocked OCR line."]`。

- [ ] 點「相簿」能開 PhotosPicker
- [ ] 選一張圖 → 進入處理狀態（右上角有「辨識翻譯中…」pill）
- [ ] 完成後下方出現「辨識到 2 行」卡 + 譯文卡
- [ ] 點 X 清除 → 恢復成「拍照或從相簿選一張有文字的圖」狀態
- [ ] 點「相機」在模擬器會 fallback 到相簿（見 `PhotoTranslationView.CameraPicker` 註解）

### A5. 語言包（LanguagePack）

Mock 的 MT 預設所有 pair 都 `.ready`。

- [ ] 頁面載入顯示 2 對：`🇹🇼 → 🇺🇸`、`🇺🇸 → 🇹🇼`
- [ ] 每一對有狀態點（綠色 = ready）、預估大小（80MB）
- [ ] 點「打開設定」可跳到系統設定 App

### A6. 歷史紀錄（History）

- [ ] 空狀態看得到時鐘圖示 + `尚無翻譯紀錄`
- [ ] 做一次翻譯後回來看得到一筆
- [ ] 右上「清空」→ 清空後回到空狀態

### A7. 單元測試

```bash
xcodebuild test \
  -project OfflineTranslator.xcodeproj \
  -scheme OfflineTranslator \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

- [ ] 全部綠燈（應該有 6 個測試檔案、~25 個 test cases）
- [ ] 任一個紅燈 → 先修好再往下走

---

## 三、B. 真機 E2E（交付前必跑）

準備：一支 iPhone（iOS 17.4+）、Apple Developer 個人帳號、Lightning/USB-C 線。

### B1. 切換到真實依賴

編輯 `App/OfflineTranslatorApp.swift`：

```swift
// @StateObject private var deps = AppDependencies.makeMock()
@StateObject private var deps = AppDependencies.makeDefault()
```

### B2. 權限流程

- [ ] 第一次進**文字翻譯**輸入文字 → 應該看到 Apple Translation
      系統 sheet（`Translation.TranslationSession` 首次使用會提示下載模型）
- [ ] 第一次進**語音翻譯**按住錄音 → 跳出「允許存取語音辨識」+「允許存取麥克風」
- [ ] 第一次進**拍照翻譯**點相機 → 跳「允許存取相機」
- [ ] 第一次點相簿 → 跳「允許存取相片」
- [ ] 以上四種權限每一種拒絕 → App 不 crash，errorMessage 會顯示

### B3. 離線驗證（「離線翻譯」的招牌）

1. 在連網狀態先下載好 `zh-Hant ⇄ en` 語言包（到語言包頁點下載）
2. 打開 **飛航模式** 或把 Wi-Fi + 行動數據都關掉
3. [ ] 文字翻譯：`你好` → `Hello` 能正常翻出
4. [ ] 語音翻譯：按住說「早安」→ 能辨識 + 翻譯 + 朗讀
5. [ ] 拍照翻譯：拍一張英文招牌 → 能 OCR + 翻譯

> ⚠️ 若 B3 任一項失敗，代表 `requiresOnDeviceRecognition` 或
> Apple Translation 的 on-device model 沒成功下載。檢查：
> - `SpeechASRService.startEngine(for:)` 裡 `supportsOnDeviceRecognition` 是否為 true
> - Apple Translation 下載 sheet 有沒有點「下載」

### B4. 品質基準（主觀）

- [ ] 文字翻譯：10 句日常對話，至少 8 句人看得懂
- [ ] 語音翻譯：安靜環境說「早安」「我想去廁所」「多少錢」→ 辨識率 > 80%
- [ ] 拍照翻譯：一張印刷體收據 / 招牌 → 至少能認出大部分的字
- [ ] TTS：譯文朗讀出來清晰、不會斷詞在奇怪的地方

### B5. 效能

- [ ] 文字翻譯反應時間 < 1 秒（在 iPhone 12 以上）
- [ ] 語音翻譯從「鬆開」到看到譯文 < 2 秒
- [ ] 拍照翻譯（3000×4000 照片）從「選圖」到看到譯文 < 4 秒
- [ ] App 啟動到 Home 顯示 < 1.5 秒
- [ ] 長時間按住麥克風（30 秒）不會卡頓

### B6. 錯誤與邊界

- [ ] 語音錄音中被來電搶走 → App 不 crash，回到 idle
- [ ] 拍照翻譯挑一張純白的圖 → 顯示「找不到文字」類型的錯誤訊息
- [ ] 輸入 2000 字的長文字 → 翻譯會完成（可能較慢）
- [ ] 切到背景 30 秒再回來 → 輸入內容還在
- [ ] 刪除語言包（設定 App 操作）後再用 → 會引導重新下載

---

## 四、Demo 錄影（5/3–5/4）

準備 2–3 分鐘影片，建議鏡頭：

1. 開 App → Home → 點文字翻譯 → 打字 `你好世界` → 翻成 `Hello World`
2. 回 Home → 語音翻譯 → 長按說「今天天氣很好」→ 自動朗讀英文
3. 回 Home → 拍照翻譯 → 拍一張英文選單 → 秒出中文譯文
4. **開飛航模式** → 重複 1 或 2，證明離線能力
5. 語言包頁 → 展示已下載的 2 對語言包
6. 歷史紀錄 → 展示剛剛 3 次翻譯都在

---

## 五、交付前最後 Checklist

- [ ] `project.yml` 的 `DEVELOPMENT_TEAM` 已填、`PRODUCT_BUNDLE_IDENTIFIER` 已改到自己的
- [ ] `.xcodeproj` 不被 commit（`.gitignore` 已排除）
- [ ] `OfflineTranslatorApp.swift` 用 `.makeDefault()`（不是 mock）
- [ ] App Icon 不是預設的灰色
- [ ] 所有 `#if DEBUG print(...)` 保留（release build 會自動移除）
- [ ] 單元測試全綠
- [ ] 實機 B3 離線驗證通過
- [ ] Demo 影片錄好
- [ ] GitHub repo push 到最新
