# Google Home Screen Control 實作計畫

日期：2026-06-19

## 交付條件

- Google Home 將 `Computer Screen` 視為標準 Matter On/Off 裝置。
- Off 關閉全部顯示器但電腦保持喚醒。
- On 恢復全部顯示器。
- 滑鼠與鍵盤可喚醒，狀態能同步回 Matter。
- 服務於 Windows 登入後自動啟動。
- 不使用 VPS、Home Assistant 或公開網路入口。
- 安裝與解除安裝可稽核、可重跑、可復原。

## 階段一：儲存庫與測試骨架

- [x] 建立獨立 Git 儲存庫與功能分支。
- [x] 建立 .NET solution、xUnit 專案與 TypeScript/Vitest 專案。
- [x] 固定 Matterbridge 3.9.0、Node.js 24.x 與 .NET 8 邊界。

## 階段二：Windows 顯示主機

- [x] 以測試定義顯示電源 native API 行為。
- [x] 實作全部螢幕 Off/On。
- [x] 實作 system-required wake lock。
- [x] 實作 console display state 監聽與去重。
- [x] 實作兩秒確認後的低干擾 SendInput fallback。
- [x] 實作 JSON Lines request/result/event 協定。
- [x] 實作五秒 self-test 與程序整合測試。

## 階段三：Matterbridge 外掛

- [x] 實作真實 child-process stdio transport。
- [x] 實作 request correlation、timeout 及退出清理。
- [x] 實作單次程序重建與重試。
- [x] 實作命令序列化與持久狀態訂閱。
- [x] 註冊 `Computer Screen` On/Off Plug-In Unit。
- [x] 僅在主機成功後更新 Matter 屬性。
- [x] 同步 Windows 實際顯示狀態。
- [x] 建立設定 schema 與 npm 發布內容。

## 階段四：Windows 安裝生命週期

- [x] 實作不變更系統的 `Install.ps1 -ValidateOnly`。
- [x] 保存原始 IPv6 與網路類別，重跑時不覆寫初始備份。
- [x] 建立 Private/LocalSubnet mDNS 與 Matter 防火牆規則。
- [x] 建置、測試、打包及全域安裝外掛。
- [x] 建立登入排程、自動重啟與本機前端綁定。
- [x] 啟動前等待 Ethernet/IPv6 就緒並重建 session/subscription cache。
- [x] 使用 kill-on-close Windows Job Object 管理 Node 與 Windows Host 子程序樹。
- [x] 啟用背景檔案日誌。
- [x] 實作可復原且預設保留 commissioning data 的解除安裝。

## 階段五：文件與驗證

- [x] 撰寫 README 安裝、配對、語音、診斷與解除安裝流程。
- [x] 記錄架構、安全、錯誤處理及取捨。
- [x] 建立 `Test-All.ps1` 單一驗證入口。
- [x] 通過 28 個 .NET 測試。
- [x] 通過 16 個 TypeScript 測試。
- [x] 通過 TypeScript typecheck/build 與 npm pack dry-run。
- [x] 通過 5 個 PowerShell 測試與語法解析。

## 階段六：本機部署驗收

- [x] 以系統管理員權限執行正式安裝。
- [x] 驗證 `Ethernet` IPv6、Private profile 與防火牆規則。
- [x] 驗證登入排程、Matterbridge 外掛與本機 frontend。
- [x] 執行五秒顯示器實機 self-test。
- [x] 完成一次性 Google Home Matter commissioning。
- [ ] 實測 Home Mini Off/On 語音命令。

## 驗收證據

每次發布前執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-All.ps1
```

本機部署後收集：

```powershell
Get-NetAdapterBinding -Name 'Ethernet' -ComponentID ms_tcpip6
Get-NetConnectionProfile -InterfaceAlias 'Ethernet'
Get-NetFirewallRule -DisplayName 'Google Home Screen Control*'
Get-ScheduledTask -TaskName 'Google Home Screen Control'
matterbridge.cmd --list
```

## 回復策略

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 `
    -Confirm:$false
```

解除安裝必須先移除排程、外掛與專用防火牆規則，再依保存狀態復原 IPv6 與網路類別。除非明確指定 `-PurgeMatterData`，不得刪除 Matter commissioning data。
