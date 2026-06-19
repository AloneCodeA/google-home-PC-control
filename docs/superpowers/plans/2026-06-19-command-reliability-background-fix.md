# Google Home 命令可靠性與背景啟動修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 Google Home 命令執行後回報錯誤、螢幕關閉後無法可靠喚醒，以及 Matterbridge 主控台視窗可見三個問題。

**Architecture:** 保留既有 Google Home Mini -> Matter -> Matterbridge -> Windows Host 本機資料流。Matterbridge 的 `OnOffServer` 負責命令完成後更新 Matter 屬性，外掛只執行 Host 動作；Windows Host 在開啟時一律送出無淨位移的輸入喚醒訊號，不依賴不可靠的顯示狀態通知；啟動器以隱藏視窗建立 Node 程序並繼續使用 Job Object 管理完整程序樹。

**Tech Stack:** TypeScript、Matterbridge 3.9、.NET 8/C#、Win32、PowerShell/Pester

---

### Task 1: 建立失敗測試

**Files:**
- Modify: `plugin/test/module.test.ts`
- Modify: `tests/ScreenControl.Host.Tests/WindowsDisplayPowerControllerTests.cs`
- Modify: `tests/PowerShell/Start-Matterbridge.Tests.ps1`

- [ ] **Step 1: Matter 命令處理測試**

將命令測試改為驗證 Host 成功後，外掛命令處理器不直接呼叫 `setAttribute`；Matterbridge `OnOffServer.super.on/off()` 才是屬性擁有者。

- [ ] **Step 2: Windows 喚醒測試**

將既有顯示狀態為 `true` 的案例改為仍須呼叫一次 `SendWakeInput()`，重現過時狀態造成後備喚醒被略過的問題。

- [ ] **Step 3: 隱藏程序測試**

驗證 `Start-Matterbridge.ps1` 包含 `-WindowStyle Hidden` 且不包含 `-NoNewWindow`。

- [ ] **Step 4: 執行測試確認 RED**

Run:

```powershell
dotnet test .\GoogleHomeScreenControl.sln --configuration Release --no-restore
npm.cmd test -- --run .\test\module.test.ts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-All.ps1
```

Expected: 新增或修改的三項斷言因現行行為而失敗。

### Task 2: 實作最小修正

**Files:**
- Modify: `plugin/src/module.ts`
- Modify: `src/ScreenControl.Host/Display/WindowsDisplayPowerController.cs`
- Modify: `Start-Matterbridge.ps1`

- [ ] **Step 1: 移除命令內重複 Matter 屬性寫入**

`setDisplayPower` 只等待 Host 成功並更新 `lastKnownDisplayState`；使用活動命令計數器避免 Host 狀態事件在 OnOff 命令期間另開屬性交易，並保留 `onConfigure` 的外部同步路徑。

- [ ] **Step 2: 一律送出開啟喚醒輸入**

開啟順序維持 `SC_MONITORPOWER` 與 `ES_DISPLAY_REQUIRED`，等待兩秒後無條件嘗試 `SendWakeInput()`；若 Windows 因 UIPI 或桌面邊界回傳 `Win32Exception`，保留主要喚醒訊號的成功結果。

- [ ] **Step 3: 隱藏 Node 主控台**

將 Node 的 `Start-Process -NoNewWindow` 改為 `Start-Process -WindowStyle Hidden`，維持 `-PassThru` 與 Job Object 指派。

- [ ] **Step 4: 執行針對性測試確認 GREEN**

Run:

```powershell
dotnet test .\GoogleHomeScreenControl.sln --configuration Release --no-restore
Push-Location .\plugin; npm.cmd test -- --run .\test\module.test.ts; Pop-Location
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-All.ps1
```

Expected: 所有測試通過。

### Task 3: 文件、部署與實機驗證

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 更新 README 稽核紀錄**

記錄 What Was Wrong、Why It Was Bad、What To Avoid Next Time、Correct Approach，以及 Changed/Why/Previous Problems/Avoid Next Time/Correct Direction。

- [ ] **Step 2: 執行完整驗證**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-All.ps1
```

Expected: .NET、TypeScript、PowerShell、語法與封裝驗證全部通過。

- [ ] **Step 3: 重新安裝並重啟排程**

使用既有提升權限安裝包裝器部署新 Host、外掛與啟動器；確認排程為 Running、Node/Host 各一個，且 Matter subscription 為 1。

- [ ] **Step 4: 實機命令驗證**

驗證關閉後可自動開啟、Matterbridge 視窗不顯示，並從紀錄確認 Google OnOff 命令成功完成。
