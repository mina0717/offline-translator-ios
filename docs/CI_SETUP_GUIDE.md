# 🤖 GitHub Actions 雲端 Mac Build — 設定指南

**一次設定，之後每次 `git push` 自動 build + 上 TestFlight。完全不需要本地 Mac。**

預估時間：**30-45 分鐘**（全程用瀏覽器）。

---

## 前置條件（必備）

- ✅ Apple Developer Program 會員（$99 USD / 年，在 [developer.apple.com/programs](https://developer.apple.com/programs/) 加入）
- ✅ GitHub repo：[mina0717/offline-translator-ios](https://github.com/mina0717/offline-translator-ios)
- ✅ `.github/workflows/ios-release.yml` 已在 repo（這個 commit 之後就有）

---

## Step 1｜Apple Developer Portal → 註冊 Bundle ID

打開 → [developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)

### 1-1 主 App Bundle ID

1. 點右上 `+`
2. 選 **App IDs** → Continue → **App** → Continue
3. 填：
   - **Description**：`Offline Translator`
   - **Bundle ID**：選 `Explicit` → 填 `com.mina0717.offlinetranslator`
4. Capabilities 勾：
   - ✅ **App Groups**（Share Extension 和主 app 共享資料）
   - ✅ **Siri**（App Intents 需要）
5. Continue → Register

### 1-2 Share Extension Bundle ID

重複一次：
- **Description**：`Offline Translator Share`
- **Bundle ID**：`com.mina0717.offlinetranslator.Share`
- Capabilities 勾：✅ **App Groups**

### 1-3 建立 App Group

左側選單 → **Identifiers** → 右上下拉改 **App Groups** → `+`
- **Description**：`Offline Translator Shared`
- **Identifier**：`group.com.mina0717.offlinetranslator`
- Continue → Register

然後回到剛剛兩個 Bundle ID，**編輯** → 勾 App Groups → 選這個剛建的 group → Save。

---

## Step 2｜App Store Connect → 建立 App 記錄

打開 → [appstoreconnect.apple.com/apps](https://appstoreconnect.apple.com/apps)

1. 左上 `+` → **New App**
2. 填：
   - **Platform**：iOS
   - **Name**：`Offline Translator`（App Store 上顯示的名字，可後改）
   - **Primary Language**：繁體中文（台灣）
   - **Bundle ID**：選剛註冊的 `com.mina0717.offlinetranslator - Offline Translator`
   - **SKU**：`OT-2026-04`（隨便，不對外）
   - **User Access**：Full Access
3. Create

完成後先不用填 App Store 上架資訊，那等 build 上來再填。

---

## Step 3｜建立 App Store Connect API Key

這支 key 就是雲端 Mac 的「身分證」，讓它能自動簽名 + 上傳。

打開 → [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)

1. 若第一次用，按 **Request Access** → 等 Apple 核准（通常秒過）
2. 點 **Keys** tab → `+`
3. 填：
   - **Name**：`GitHub Actions CI`
   - **Access**：**App Manager**（最小能上傳 TestFlight 的權限）
4. Generate

**下載畫面很重要！**
- 點 **Download API Key**，存下那個 `.p8` 檔案（**只能下載一次！**）
- 記住這兩個值（複製貼到記事本）：
  - **Key ID**（10 字元，例：`ABC123DEFG`）
  - **Issuer ID**（UUID，例：`12345678-1234-1234-1234-123456789012`）

---

## Step 4｜拿到你的 Team ID

打開 → [developer.apple.com/account](https://developer.apple.com/account) → 往下拉 **Membership details**

複製 **Team ID**（10 字元，例：`A1B2C3D4E5`）

---

## Step 5｜把 4 個值設為 GitHub Secrets

打開 → [github.com/mina0717/offline-translator-ios/settings/secrets/actions](https://github.com/mina0717/offline-translator-ios/settings/secrets/actions)

按 **New repository secret**，加入下面 4 個：

| Name | Value 怎麼來 |
|------|-------------|
| `APPLE_TEAM_ID` | Step 4 的 Team ID（10 字元） |
| `APP_STORE_CONNECT_API_KEY_ID` | Step 3 的 Key ID（10 字元） |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Step 3 的 Issuer ID（UUID） |
| `APP_STORE_CONNECT_API_KEY` | Step 3 下載的 `.p8` 檔**轉 base64**（見下） |

### 如何把 .p8 轉 base64？

**在任何電腦上**（Windows / Linux / Mac / 線上工具）都可：

**線上工具**（最簡單）：
- 打開 [base64encode.org](https://www.base64encode.org/)
- 把 `.p8` 檔用記事本開啟 → 全選複製 → 貼到網站 → Encode
- 把結果整段複製貼到 `APP_STORE_CONNECT_API_KEY` 的 Value

**Linux / Mac terminal**：
```bash
base64 -i AuthKey_ABC123DEFG.p8
```

**Windows PowerShell**：
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_ABC123DEFG.p8"))
```

---

## Step 6｜觸發第一次 build

### 方法 A：手動跑（推薦第一次用）

1. 打開 → [github.com/mina0717/offline-translator-ios/actions](https://github.com/mina0717/offline-translator-ios/actions)
2. 左側選 **iOS Release (TestFlight)**
3. 右邊按 **Run workflow** → 選 `main` branch
4. `marketing_version` 填 `1.1.0`（或留空）
5. **Run workflow**

跑大約 **15-25 分鐘**，看 log 即時狀態。

### 方法 B：用 git tag（正式 release）

```bash
git tag v1.1.0
git push origin v1.1.0
```

Tag 一推就自動觸發 workflow。

---

## Step 7｜在 iPhone 用 TestFlight 測試

- build 成功後，Apple 會寄 email 給你
- 或直接打開 [appstoreconnect.apple.com/apps/{你的 app}/testflight](https://appstoreconnect.apple.com/apps) → **TestFlight** tab
- 狀態從 `Processing` → `Ready to Submit`（約 10-30 分鐘）
- iPhone 裝 TestFlight app → 用 Apple ID 登入 → build 就出現了
- 裝起來 → **開始手機實機測試** 🚀

---

## 常見錯誤排除

### ❌ `No profile matching 'com.mina0717.offlinetranslator' found`

→ Step 1 的 Bundle ID 沒註冊成功，或跟 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` 不一致。

### ❌ `Authentication credentials are missing or invalid`

→ `.p8` base64 轉壞了，或 Key ID / Issuer ID 貼錯。重新貼一次。

### ❌ `No development team provided`

→ `APPLE_TEAM_ID` secret 沒設，或跟 Apple Developer Account 的 Team ID 不一致。

### ❌ `Unable to upload app: This bundle is invalid`

→ 通常是 app version 跟 build number 跟之前一模一樣，TestFlight 不接受重複。把 marketing version 或 build number 加 1 重跑。

### ❌ `Xcode 16.2 is not installed`

→ GitHub runner 把預設 Xcode 版號改了。打開 workflow 檔，把 `XCODE_VERSION: "16.2"` 改成當下 [runner-images](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) 有的版本。

---

## 之後的 release 流程（設定完之後的每一次）

```bash
# 1. 改完程式、commit、push
git add .
git commit -m "feat: xxx"
git push

# 2. 開新版就打 tag
git tag v1.2.0
git push origin v1.2.0

# 3. 等 20 分鐘，TestFlight 上就有新版
# 4. iPhone 開 TestFlight 點 Update → 測
```

這樣就完全沒 Mac 的事了 ✨

---

2026-04-22 · 問題直接截 Actions 的 log 給 Claude 看。
