# MacroBuilder (MB) v1.0.0 🚀

[![AutoHotkey v2](https://img.shields.com/badge/AutoHotkey-v2.0+-green.svg)](https://www.autohotkey.com/)
[![License](https://img.shields.com/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.com/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)

**MacroBuilder (MB)** 是一款基於 **AutoHotkey v2 (AHK v2)** 開發的高效能、多群組自動化巨集編輯與執行工具。擁有優雅無邊框的懸浮齒輪 UI、獨立執行圖示、雙層 GDI 進度條、多頁籤管理矩陣以及視覺化螢幕區域顏色偵測與自動測試功能。

---

## ✨ 核心特色與亮點 (Key Features)

- 🎨 **現代化懸浮 UI (Floating Widget)**
  - 極簡無邊框設計、支援半透明度控制與自由置頂 (AlwaysOnTop) 切換。
  - 彩色 Unicode Emoji (Segoe UI Emoji) 圖示，直覺好看。
  - 右鍵快捷選單支援，方便隨時開啟編輯器、匯入/匯出設定或安全退出。

- 📊 **雙層 GDI 實體動態進度條 (GDI Progress Bar)**
  - GDI 雙層漸層條：即時繪製**當前步驟進度 (水藍條)** 與 **總循環進度 (黃條)**。
  - 高品質微軟正黑體陰影文字，即時顯示當前執行群組、循環次數與詳細步驟狀態資訊。

- 🗂 **多群組巨集與頁籤矩陣 (Multi-Group & Tab Grid Matrix)**
  - 支援同時建立、管理與個別配置多個獨立巨集群組（如戰鬥、解任務、日常等）。
  - 3 欄式動態頁籤矩陣，點擊即可切換編輯，支援顯示/隱藏與獨立圖示設定。

- 🎯 **視覺化螢幕區域顏色偵測 (Visual Screen Region Color Detection)**
  - 支援滑鼠拖曳圈選畫面任意區域。
  - 自動採樣區域內的主色 (Dominant Color) 並擺脫選框殘影噪訊。
  - 提供 100% 乾淨極簡的水藍色標記框 (BoxGui)，支援滑鼠拖曳移位自動輪購檢測與即時自動測試。
  - 支援正向/反向 (未發現才點擊) 色彩偵測。

- ⚙️ **豐富的步驟與逾時轉向處置 (Advanced Action & Timeout Control)**
  - 支援「僅點擊中心點」、「僅發送按鍵」或「點擊 + 發送按鍵 (含按住時間)」等多種觸發動作。
  - 支援逾時機制 (0-300 秒)，逾時可自動發送特定按鍵，並選擇重試本步驟、推進下一步或跳轉至指定步驟。
  - 支援純秒數等待 (Wait) 步驟。

- 📥 **完整的 INI 設定檔匯入與匯出 (INI Configuration Management)**
  - 隨時匯出備份巨集設定，或從 INI 設定檔快速匯入巨集資料庫。

---

## 🖥 系統需求 (System Requirements)

- **作業系統**: Windows 10 / Windows 11 (64-bit)
- **環境依賴**: [AutoHotkey v2.0+](https://www.autohotkey.com/)

---

## 🚀 快速開始 (Quick Start)

### 1. 安裝 AutoHotkey v2
若電腦尚未安裝 AutoHotkey v2，請至 [AutoHotkey 官網](https://www.autohotkey.com/) 下載並安裝 **v2.0** 或以上版本。

### 2. 下載專案
使用 Git 複製本專案或下載 ZIP 解壓縮：
```bash
git clone https://github.com/czh00/mb.git
```

### 3. 執行腳本
雙擊執行 `macro_builder.ahk` 即可啟動工具。

---

## 📖 使用指南 (User Guide)

### 主懸浮列操作
- **⚙ (齒輪圖示)**：開啟/關閉多群組巨集編輯器。
- **圖示按鈕 (如 ⚔️, ⚡️ 等)**：點擊即可啟動或停止該群組巨集執行。
- **⏏ (離開圖示)**：停止巨集並關閉程式。
- **右鍵選單**：在懸浮列任意位置點擊右鍵，可呼出功能選單（編輯器、匯入/匯出 INI、離開）。

### 巨集編輯器操作
1. **切換群組**：點擊上方頁籤矩陣按鈕即可切換當前編輯的群組。
2. **新增群組**：點擊 `➕ 新增巨集群組`，可設定群組名稱、Emoji 圖示及是否顯示於主懸浮列。
3. **新增顏色偵測步驟**：
   - 點擊 `🎯 圈選顏色與動作`。
   - 在螢幕上按住滑鼠左鍵拖曳圈選目標區域。
   - 在彈出的對話框中微調目標顏色、容許值、動作類型（點擊/按鍵）及逾時處置機制。
4. **調整步驟順序**：使用 `▲` 與 `▼` 按鈕調整選取步驟的執行順序。
5. **儲存設定**：編輯完成後點擊 `💾 儲存`，設定將自動儲存至 `macro_config.ini`。

---

## 📁 檔案結構 (Project Structure)

```
mb/
├── macro_builder.ahk    # 巨集編輯器與執行引擎主程式 (AutoHotkey v2)
├── macro_config.ini     # 巨集設定檔 (執行後自動產生)
├── README.md            # 專案詳細說明文件
└── LICENSE              # MIT 開放原始碼授權條款
```

---

## 📄 授權條款 (License)

本專案採用 [MIT License](LICENSE) 進行許可。
