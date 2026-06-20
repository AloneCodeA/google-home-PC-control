# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-20

Initial public release.

### Added
- Local Matter control of all Windows 11 displays as a single `Computer Screen` On/Off device, voiced through Google Home Mini.
- Matterbridge 3.9.0 plugin that exposes the On/Off device and bridges to the Windows host over a JSON-Lines protocol.
- .NET 8 display-control host that toggles monitor power while keeping the PC awake, and reports the real display state back to Matter.
- Windowless .NET 8 launcher that owns the PowerShell → Node → Matterbridge → host process tree via a kill-on-close Job Object.
- Repeatable `Install.ps1` / `Uninstall.ps1` that configure IPv6 and a `Private`/`LocalSubnet` firewall, register a logon scheduled task, and restore saved network state on removal.
- `Start-Matterbridge.ps1` launcher that waits for IPv6 readiness and prunes only safe-to-rebuild Matter session caches on resume.

[1.0.0]: ../../releases/tag/v1.0.0
