# Google Home Screen Control

> Turn every monitor on your Windows 11 PC on and off by voice, through **Google Home Mini** over local **Matter** — while the computer keeps running.

```text
OK Google, turn off Computer Screen
OK Google, turn on  Computer Screen
```

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%2011-0078D6?logo=windows11&logoColor=white)
![.NET](https://img.shields.io/badge/.NET-8.0-512BD4?logo=dotnet&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-24.x-339933?logo=nodedotjs&logoColor=white)
![Matter](https://img.shields.io/badge/Matter-local%20fabric-F38020)

When you turn the screens off, Windows, the network, and background programs keep running — no sleep, no lock, no sign-out. Moving the mouse or pressing a key wakes the displays as usual.

Everything runs **on your own machine and LAN**. There is no cloud bridge, no VPS, no Home Assistant, and no inbound port opened to the internet.

---

## Contents

- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [First-time Matter pairing](#first-time-matter-pairing)
- [Voice control](#voice-control)
- [How it behaves](#how-it-behaves)
- [Diagnostics](#diagnostics)
- [Uninstall](#uninstall)
- [Security](#security)
- [Design notes](#design-notes)
- [Project structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **One voice switch for all displays.** Every connected monitor is exposed as a single Matter On/Off device named `Computer Screen`.
- **The PC stays awake.** Only the display power signal is toggled — the machine never sleeps, locks, or logs out, so it stays reachable on the network.
- **Driven by the real display state.** The actual Windows display state is written back to Matter, so a manual mouse/keyboard wake is reflected in Google Home.
- **No DDC/CI dependency.** Uses Windows display-power messages, so multiple monitors (including two Dell panels on the dev machine) switch together reliably.
- **Fully local.** Matter runs on your LAN via [Google Home Mini as a Matter hub](https://support.google.com/googlenest/answer/12391458?hl=en). After the one-time pairing, day-to-day commands never leave the network.
- **Repeatable, auditable install.** A single PowerShell installer configures the build, firewall, IPv6, and a logon scheduled task — and saves the original network state so uninstall can restore it.

## How it works

```mermaid
flowchart LR
    Voice["Google Home Mini"] --> Hub["Google Home<br/>Matter Fabric"]
    Hub -->|"Local IPv6 / Matter"| Bridge["Matterbridge 3.9.0<br/>(plugin)"]
    Bridge -->|"JSON Lines over stdio"| Host["ScreenControl.Host.exe"]
    Host -->|"Windows power messages"| Displays["All connected displays"]
```

- A **Matterbridge plugin** (TypeScript) publishes a standard On/Off Matter device to the Google Home fabric.
- A dedicated **.NET 8 host** (`ScreenControl.Host.exe`) does the interactive Windows display work and reports the true display state back over a simple JSON-Lines protocol.
- The plugin only updates Matter state **after** the host confirms the action. If the host stops unexpectedly, a supervisor rebuilds it and retries a command once — never in a loop.

## Requirements

- **Windows 11**
- **Node.js 24.x**
- **.NET 8 Desktop Runtime** (or SDK)
- An **`Ethernet`** network interface that is connected
- The Google Home Mini and the PC on the **same LAN** that passes multicast / mDNS
- **Administrator** rights to run the installer

> Matter requires link-local IPv6. The installer enables IPv6 on the chosen interface and sets its network category to `Private`. The original settings are saved so uninstall can restore them.

## Installation

1. **Get the code.** Download the latest source from the [Releases page](../../releases/latest) (or `git clone` this repository) and extract it.
2. **Run the installer** from an **elevated** ("Run as administrator") PowerShell, in the repository folder:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 `
       -InterfaceAlias 'Ethernet' `
       -Confirm:$false
   ```

   > If your wired adapter is not named `Ethernet`, pass its name to `-InterfaceAlias`. Check with `Get-NetAdapter`.

The installer will:

1. Validate Windows, Node.js, .NET, and the network interface.
2. Save the current IPv6 binding and network category.
3. Enable IPv6 and set the interface to `Private`.
4. Create firewall rules limited to `Private` / `LocalSubnet` for UDP 5353 (mDNS) and 5540 (Matter).
5. Build and publish the Windows display-control host.
6. Build and install Matterbridge 3.9.0 and this plugin.
7. Install a launcher that waits for the interface and IPv6 to be ready.
8. Register a scheduled task that auto-starts after the current user signs in.
9. Run a five-second display self-test to confirm real control works.

Re-running the installer is safe: it stops the existing Matterbridge process tree, swaps the global package, and restarts the task. The network settings saved on the **first** run are never overwritten — to change interfaces, uninstall first.

**Preview without changing anything:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 `
    -ValidateOnly `
    -InterfaceAlias 'Ethernet'
```

Add `-SkipSelfTest` to skip the five-second screen test.

## First-time Matter pairing

1. Confirm the scheduled task `Google Home Screen Control` is running.
2. On this PC, open <http://127.0.0.1:8283/>.
3. The Matterbridge home page shows a Matter QR code and pairing code.
4. In the Google Home app, add a new Matter device and scan the QR code.
5. Add it to the same Home as the Home Mini, keeping the name `Computer Screen`.

This is a one-time secure commissioning. Signing in again or rebooting does **not** require re-pairing, and uninstall preserves the Matter pairing data by default.

## Voice control

After pairing:

```text
OK Google, turn off Computer Screen
OK Google, turn on  Computer Screen
```

Prefer your own phrasing? Create two Google Home Household Automations that map custom sentences (for example "turn off this computer screen") to `Computer Screen` Off/On. That only changes phrase parsing — the local control path is unchanged.

## How it behaves

**Turning off** — The host broadcasts `SC_MONITORPOWER = 2` so all displays stop their signal. The computer stays awake and Matterbridge keeps running.

**Turning on** — The host broadcasts `SC_MONITORPOWER = -1` plus a momentary display-required signal. If Windows still reports the screen off after two seconds, it performs a single one-pixel mouse nudge (then returns the cursor) as a fallback wake.

**Manual wake** — Mouse or keyboard wakes the screens normally; the real Windows display state is written back to the Matter `OnOff` attribute.

**Login session** — Display control needs an interactive Windows session, so the task starts after the current user signs in (control is not available while signed out). On logon or power-state resume, `Start-Matterbridge.ps1` waits for the interface to be `Up` with a preferred IPv6 address, then clears only the safe-to-rebuild Matter session/subscription caches — the Google Home fabric, commissioning, and access-control data are preserved. Node and the host run inside a `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` Windows Job Object so nothing is orphaned if the task stops.

## Diagnostics

Check the scheduled task:

```powershell
Get-ScheduledTask -TaskName 'Google Home Screen Control' | Select-Object TaskName, State
```

Restart the background service:

```powershell
Stop-ScheduledTask  -TaskName 'Google Home Screen Control' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'Google Home Screen Control'
```

Inspect the plugin and logs:

```powershell
matterbridge.cmd --list
Get-Content "$HOME\.matterbridge\matterbridge.log" -Tail 100
Get-Content "$env:LOCALAPPDATA\GoogleHomeScreenControl\launcher.log" -Tail 100
```

Verify the network state Matter needs:

```powershell
Get-NetAdapterBinding   -Name 'Ethernet' -ComponentID ms_tcpip6
Get-NetConnectionProfile -InterfaceAlias 'Ethernet'
Get-NetIPAddress         -InterfaceAlias 'Ethernet' -AddressFamily IPv6
```

Run the five-second display test manually:

```powershell
$hostPath = Join-Path (npm.cmd root --global) `
    'matterbridge-google-home-screen-control\bin\ScreenControl.Host.exe'
& $hostPath --self-test
```

### Troubleshooting

- **Google can't find the device during pairing** — confirm the PC and Home Mini are on the same subnet, IPv6 is enabled on the interface, and the network category is `Private`. Re-run `Install.ps1 -ValidateOnly` to see the current state.
- **Device shows offline after a reboot** — the launcher waits for a preferred IPv6 address; give it a moment after sign-in, then check `launcher.log`.
- **Wrong adapter** — if your wired NIC isn't `Ethernet`, reinstall with the correct `-InterfaceAlias`.

## Uninstall

Remove the service, plugin, and firewall rules, restore the pre-install IPv6 / network category, and keep the Matter pairing data:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -Confirm:$false
```

Other options:

```powershell
.\Uninstall.ps1 -ValidateOnly                 # show the uninstall plan only
.\Uninstall.ps1 -RestoreNetwork:$false -Confirm:$false   # leave network settings as-is
.\Uninstall.ps1 -PurgeMatterData -Confirm:$false         # also delete all local Matter pairing data
```

> `-PurgeMatterData` affects **every** Matterbridge pairing for the current Windows user. Use it only if you are sure none are still in use.

## Security

- The admin front end binds to `127.0.0.1:8283` only — other LAN devices cannot open it.
- Firewall rules allow only Node.js to accept `LocalSubnet` UDP 5353/5540 on `Private` networks.
- No public ingress is created, and no Google password or OAuth token is stored.
- Matter pairing keys live in the current user's `$HOME\.matterbridge` and `$HOME\.mattercert`.

## Design notes

A few decisions that shape the implementation:

- **Local Matter instead of a cloud webhook.** A cloud bridge or VPS would add public attack surface, account coupling, and ongoing upkeep for a one-machine convenience. Home Mini already speaks Matter on the LAN, so the screens are modeled as a standard On/Off device.
- **Keep awake, switch only the display signal.** Letting Windows sleep can make it impossible to wake the display from the network. The system stays awake and only toggles monitor power.
- **Trust the OS, not the command.** Treating a command as the source of truth reports the wrong state after a manual wake, so the host monitors the real display state and reports it back. `GUID_CONSOLE_DISPLAY_STATE` is *not* used to gate the wake fallback because it can stay `true` after a monitor is off.
- **One ownership boundary.** Command execution stays in the plugin; the Matter attribute transition is owned by Matterbridge's OnOff behavior. The plugin does not write the command-owned attribute itself, which previously caused commands to fail after Windows had already acted.
- **A windowless launcher owns the process tree.** A .NET 8 `WinExe` launcher runs as the interactive scheduled task (no console window) and assigns PowerShell → Node → Matterbridge → host to a kill-on-close Job Object, giving Task Scheduler deterministic ownership for restart and cleanup.
- **Wait for IPv6, drop only session cache.** On resume, starting Matterbridge before IPv6 is ready — or loading a stale Matter session cache — can make Google Home briefly unreachable. The launcher waits for a preferred IPv6 address and clears only session/subscription caches, never the fabric or credentials.

## Project structure

```text
.
├── Install.ps1               # Repeatable build / network / firewall / scheduled-task install
├── Uninstall.ps1             # Uninstall and restore saved network settings
├── Start-Matterbridge.ps1    # Wait for network readiness, prune session cache, start Matterbridge
├── GoogleHomeScreenControl.sln
├── plugin/                   # Matterbridge DynamicPlatform plugin (On/Off Plug-In Unit)
│   └── src/
└── src/
    ├── ScreenControl.Host/       # Windows display control, wake lock, state monitor
    └── ScreenControl.Launcher/   # WinExe launcher owning the kill-on-close Job Object
```

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and build/type-check commands.

## License

[MIT](LICENSE) © Alone
