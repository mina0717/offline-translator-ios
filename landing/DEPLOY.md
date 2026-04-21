# Landing Page 部署指南

兩個檔案、單一資料夾，任何靜態網站服務都能託管。推薦 GitHub Pages（免費、自動 HTTPS、和專案同倉庫）。

---

## 方案 A：GitHub Pages（推薦）

### 1. 把 `landing/` 內容搬進 repo 的 `docs/` 資料夾

在 Mac 或用 GitHub 網頁編輯器把這兩個檔案放到 repo root 的 `docs/`：

```
offline-translator-ios/
└── docs/
    ├── index.html     ← 從這個資料夾的 landing/index.html 複製
    └── privacy.html   ← 從這個資料夾的 landing/privacy.html 複製
```

### 2. 開啟 GitHub Pages

到 repo 的 **Settings → Pages**：

- **Source**: `Deploy from a branch`
- **Branch**: `main` / folder: `/docs`
- **Save**

一兩分鐘內會得到 URL：
```
https://mina0717.github.io/offline-translator-ios/
```

子頁：
```
https://mina0717.github.io/offline-translator-ios/privacy.html
```

把第二個 URL 填進 App Store Connect 的 Privacy Policy URL 欄位。

---

## 方案 B：Cloudflare Pages（自訂網域）

如果想要自訂網域（例如 `offlinetranslator.app`）：

1. 買網域（Cloudflare Registrar 最便宜）
2. Cloudflare Pages → Connect to Git → 選 repo → Build directory: `docs` (或 `landing`)
3. 自訂網域：Pages → Custom domains → 加上你的網域
4. Cloudflare 會自動設 DNS 和 HTTPS

---

## 方案 C：Vercel / Netlify

Drag & drop 這個資料夾就好：
- Vercel: `vercel --prod` 或用網頁 drag-drop
- Netlify: drop 整個 `landing/` 到 [app.netlify.com/drop](https://app.netlify.com/drop)

---

## 本地預覽

```bash
cd landing
python3 -m http.server 8000
# 開 http://localhost:8000
```

或直接雙擊 `index.html` 用瀏覽器開也可以。

---

## 未來擴充

這個 landing 是單一 HTML + inline CSS，故意不用任何 build tool。要擴充只要編輯 `index.html`。

建議後續加：
- **Analytics**：注意本 App 主打零分析，如果 landing 要加 GA 要在隱私政策裡另外寫「僅網站使用」
- **Open Graph 圖片**：準備一張 1200×630 的 `og-image.png` 放同資料夾，然後 `<meta property="og:image" content="./og-image.png">`
- **Favicon 系列**：從 `brand/AppIcon-*.png` 衍生，或用 realfavicongenerator.net
