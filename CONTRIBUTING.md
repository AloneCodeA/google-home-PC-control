# Contributing

Thanks for your interest in improving **Google Home Screen Control**! Issues and pull requests are welcome.

## Development environment

- Windows 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Node.js 24.x](https://nodejs.org/)

The full runtime integration (Matter pairing, scheduled task, firewall, IPv6) only works end-to-end on Windows 11, but the code builds and type-checks without a paired device.

## Building

### .NET host and launcher

```powershell
dotnet build GoogleHomeScreenControl.sln --configuration Release
```

Publish a single-file executable the way the installer does:

```powershell
dotnet publish src/ScreenControl.Host/ScreenControl.Host.csproj `
    --configuration Release --runtime win-x64 --self-contained false `
    -p:PublishSingleFile=true -p:DebugType=None -p:DebugSymbols=false `
    --output .\bin
```

### Matterbridge plugin

```powershell
cd plugin
npm ci
npm run typecheck   # tsc --noEmit, strict
npm run build       # emits dist/
```

## End-to-end install

To exercise the full system on a Windows 11 machine, run the installer from an elevated PowerShell (see the [README](README.md#installation)). Use `-ValidateOnly` to preview without changing the system.

## Pull requests

- Keep changes focused and describe them clearly.
- Match the existing code style: C# `#nullable enable`, TypeScript `strict`, PowerShell `Set-StrictMode`.
- Make sure `dotnet build -c Release`, `npm run typecheck`, and `npm run build` all succeed before opening a PR.

## Reporting issues

Please include your Windows version, Node.js and .NET versions, the adapter name you installed with, and relevant lines from `matterbridge.log` / `launcher.log` (see [Diagnostics](README.md#diagnostics)).
