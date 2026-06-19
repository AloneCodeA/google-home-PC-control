# Google Home Screen Control 設計規格

日期：2026-06-19

## 目標

讓 Google Home Mini 在同一個區域網路內控制 Windows 11 電腦的全部螢幕：

- Off：關閉顯示訊號，但保持電腦、網路及背景程式運作。
- On：恢復所有顯示器，必要時使用低干擾輸入後備方案。
- 使用者仍可用滑鼠或鍵盤喚醒。
- 不使用 VPS、Home Assistant 或公開 webhook。

## 已確認需求

- 作業系統：Windows 11 Pro。
- 網路介面：`Ethernet`。
- 顯示器：兩台 Dell，一律同時控制。
- Matter 裝置名稱：`Computer Screen`。
- 背景服務：目前使用者登入後自動啟動。
- Matter 首次安全配對後，日常控制不依賴行動 App。
- Off 不得造成睡眠、休眠、鎖定或登出。

## 不在範圍內

- 個別控制每一台螢幕。
- DDC/CI 亮度或輸入來源控制。
- BIOS、關機、休眠或 Wake-on-LAN。
- 遠端 Internet 控制。
- 自動化 Google 帳戶登入或繞過 Matter commissioning。

## 架構決策

### Matterbridge DynamicPlatform

使用 Matterbridge 3.9.0 建立標準 `On/Off Plug-In Unit`。Google Home 可直接理解 On/Off 能力，不需要建立自訂 Google Smart Home cloud integration。

### 獨立 Windows 主機

Node.js 不直接承擔 Windows 訊息迴圈。`ScreenControl.Host.exe` 使用 .NET 8 Windows Forms message pump 接收顯示電源通知，並透過 Win32 API 控制顯示器。

責任分離：

- Matterbridge：Matter 裝置模型、commissioning、命令處理及屬性同步。
- Windows 主機：互動式工作階段、顯示電源、系統喚醒鎖及真實狀態。
- PowerShell：建置、網路、防火牆、安裝、排程與復原。

## 程序協定

Matterbridge 以 stdio JSON Lines 與主機通訊。stdout 只允許協定訊息，診斷錯誤寫入 stderr。

命令：

```json
{"type":"setDisplayPower","requestId":"uuid","isOn":true}
```

結果：

```json
{"type":"result","requestId":"uuid","success":true,"error":null}
```

狀態事件：

```json
{"type":"displayState","isOn":true}
```

`requestId` 用來關聯並行輸入與結果。Matterbridge 端序列化顯示命令，避免 On/Off 競爭；協定仍保留 request correlation 以便錯誤隔離與未來擴充。

## 顯示控制

### Off

向所有 top-level windows 廣播 `WM_SYSCOMMAND / SC_MONITORPOWER`，`lParam = 2`。

### On

1. 廣播 `SC_MONITORPOWER`，`lParam = -1`。
2. 暫時送出 `ES_DISPLAY_REQUIRED`。
3. 等待兩秒並檢查 Windows console display state。
4. 若仍未開啟，使用 `SendInput` 將滑鼠移動一像素後移回。

### 保持電腦喚醒

主機存活期間維持 `ES_CONTINUOUS | ES_SYSTEM_REQUIRED`。這只阻止系統自動睡眠，不強迫螢幕持續亮起。

### 實際狀態

message-only window 註冊 `GUID_CONSOLE_DISPLAY_STATE`：

- `0` 對應 Off。
- `1` 或 `2` 對應 On。
- 重複狀態不重送。

因此滑鼠、鍵盤或其他 Windows 行為改變顯示狀態時，Matter 屬性仍可同步。

## 錯誤處理

- 主機回覆失敗時不先行改寫 Matter On/Off 屬性。
- 每個命令有 timeout，逾時後移除 pending request。
- 主機退出時拒絕所有 pending request。
- 監督器在命令失敗後只重建主機並重試一次。
- 重試仍失敗時將錯誤交回 Matterbridge，不進入無限循環。
- 自我測試使用 `finally` 邏輯確保五秒後要求恢復顯示。

## 網路與安全

- Matter/mDNS 需要 IPv6 與 multicast 可達。
- 安裝時將指定介面設為 `Private` 並啟用 IPv6。
- 只為 Node.js 建立 `Private`、`LocalSubnet`、UDP 5353/5540 inbound 規則。
- Matterbridge frontend 綁定 `127.0.0.1:8283`。
- 不建立 Internet ingress。
- 首次安裝保存原始網路狀態；解除安裝預設復原。

## 生命週期

1. 使用者登入。
2. Windows 排程工作等待 5 秒，且要求網路可用。
3. 本機啟動器輪詢指定介面，直到介面 Up、IPv6 啟用且有 Preferred IPv6 位址。
4. 啟動器刪除 `sessions.resumptionRecords` 與 `root.subscriptions.subscriptions`；fabric 與 operational credentials 保留。
5. 啟動器建立 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` Windows Job Object，並將 Node 指派進去。
6. Matterbridge 啟動並載入外掛；其 Windows 主機子程序繼承同一個 Job Object。
7. Windows 主機取得 system-required wake lock。
8. 關機、登出或工作停止時，Job Object 關閉並由核心終止整棵子程序樹。

啟動器等待網路最長 120 秒，逾時會以非零代碼退出。排程工作在異常退出時每分鐘重試，最多 999 次。這是互動式桌面控制的必要限制；登出後沒有可控制的桌面工作階段。

## 測試策略

- .NET：Win32 對應、狀態解析、去重、命令處理、JSONL、self-test 與真實程序協定。
- TypeScript：傳輸、request correlation、timeout、狀態事件、單次重試、序列化及 Matter 平台生命週期。
- PowerShell：ValidateOnly 報告、session cache 保護、網路 timeout、Job Object 子程序清理、安裝/解除安裝計畫與語法。
- 發布：單檔 framework-dependent win-x64 EXE、TypeScript build、npm pack dry-run。

## 取捨

- Matterbridge 比自行實作 Matter stack 更可維護，但固定依賴經驗證的 3.9.0 版本。
- Windows 廣播會同時控制所有螢幕，符合需求但不支援個別裝置。
- 登入排程不提供登出狀態控制，換取正確的互動式 Windows session ownership。
- 啟動時捨棄 session resumption/subscription cache 會增加一次 CASE 建連成本，但避免 Windows 恢復後沿用不可達 peer；fabric 與配對不受影響。
- 後備滑鼠輸入可能觸發極小移動，因此只在直接喚醒與 display-required 均失敗後執行，並立即移回。
