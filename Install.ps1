[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InterfaceAlias = 'Ethernet',

    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [switch]$SkipSelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'Google Home Screen Control'
$PluginName = 'matterbridge-google-home-screen-control'
$MatterbridgeVersion = '3.9.0'
$MdnsFirewallRule = 'Google Home Screen Control - mDNS'
$MatterFirewallRule = 'Google Home Screen Control - Matter'
$RepositoryRoot = $PSScriptRoot
$PluginRoot = Join-Path $RepositoryRoot 'plugin'
$ArtifactsRoot = Join-Path $RepositoryRoot 'artifacts'
$StateRoot = Join-Path $env:LOCALAPPDATA 'GoogleHomeScreenControl'
$StatePath = Join-Path $StateRoot 'install-state.json'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [string[]]$ArgumentList = @(),

        [Parameter()]
        [string]$WorkingDirectory = $RepositoryRoot
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($ArgumentList -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Get-ValidationReport {
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $nodeVersion = (& node --version 2>$null | Select-Object -First 1)
    $dotnetRuntimes = (& dotnet --list-runtimes 2>$null) -join "`n"
    $adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
    $profile = Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias -ErrorAction SilentlyContinue
    $ipv6Binding = Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

    return [ordered]@{
        InterfaceAlias = $InterfaceAlias
        OperatingSystem = $operatingSystem.Caption
        OperatingSystemSupported = $operatingSystem.Caption -like '*Windows 11*'
        NodeVersion = $nodeVersion
        NodeVersionSupported = $nodeVersion -match '^v24\.'
        DotNet8RuntimeAvailable = $dotnetRuntimes -match 'Microsoft\.NETCore\.App 8\.'
        AdapterFound = $null -ne $adapter
        AdapterUp = $null -ne $adapter -and $adapter.Status -eq 'Up'
        CurrentIpv6Enabled = $null -ne $ipv6Binding -and $ipv6Binding.Enabled
        CurrentNetworkCategory = if ($null -ne $profile) { [string]$profile.NetworkCategory } else { $null }
        IsAdministrator = Test-IsAdministrator
        PlannedActions = @(
            "Enable IPv6 on $InterfaceAlias"
            "Set $InterfaceAlias network category to Private"
            'Create Private/LocalSubnet mDNS and Matter firewall rules'
            'Build and install the Matterbridge plugin package'
            'Register and enable the Computer Screen plugin'
            'Create the Matterbridge logon scheduled task'
            'Start Matterbridge for the current interactive user'
            'Run the five-second display self-test'
        )
    }
}

$report = Get-ValidationReport
if ($ValidateOnly) {
    $report | ConvertTo-Json -Depth 5
    return
}

$failedChecks = @()
if (-not $report.OperatingSystemSupported) { $failedChecks += 'Windows 11 is required.' }
if (-not $report.NodeVersionSupported) { $failedChecks += 'Node.js 24.x is required.' }
if (-not $report.DotNet8RuntimeAvailable) { $failedChecks += '.NET 8 runtime is required.' }
if (-not $report.AdapterFound) { $failedChecks += "Network adapter '$InterfaceAlias' was not found." }
if (-not $report.AdapterUp) { $failedChecks += "Network adapter '$InterfaceAlias' is not up." }
if (-not $report.IsAdministrator) { $failedChecks += 'Run Install.ps1 from an elevated PowerShell window.' }
if ($failedChecks.Count -gt 0) {
    throw ($failedChecks -join [Environment]::NewLine)
}

if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install Google Home Screen Control')) {
    return
}

New-Item -ItemType Directory -Force -Path $StateRoot, $ArtifactsRoot | Out-Null
$existingProfile = Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias
$existingIpv6Binding = Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6
if (-not (Test-Path -LiteralPath $StatePath)) {
    $installState = [ordered]@{
        InterfaceAlias = $InterfaceAlias
        OriginalIpv6Enabled = [bool]$existingIpv6Binding.Enabled
        OriginalNetworkCategory = [string]$existingProfile.NetworkCategory
        InstalledAtUtc = [DateTime]::UtcNow.ToString('O')
        TaskName = $TaskName
        FirewallRules = @($MdnsFirewallRule, $MatterFirewallRule)
    }
    $installState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

if (-not $existingIpv6Binding.Enabled) {
    Enable-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6 | Out-Null
}
if ($existingProfile.NetworkCategory -ne 'Private') {
    Set-NetConnectionProfile -InterfaceAlias $InterfaceAlias -NetworkCategory Private
}

$nodeExecutable = (Get-Command node.exe -ErrorAction Stop).Source
Remove-NetFirewallRule -DisplayName $MdnsFirewallRule -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName $MatterFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $MdnsFirewallRule -Direction Inbound -Action Allow `
    -Program $nodeExecutable -Protocol UDP -LocalPort 5353 -RemoteAddress LocalSubnet `
    -Profile Private | Out-Null
New-NetFirewallRule -DisplayName $MatterFirewallRule -Direction Inbound -Action Allow `
    -Program $nodeExecutable -Protocol UDP -LocalPort 5540 -RemoteAddress LocalSubnet `
    -Profile Private | Out-Null

Invoke-CheckedCommand -FilePath 'dotnet' -ArgumentList @(
    'test', (Join-Path $RepositoryRoot 'GoogleHomeScreenControl.sln'),
    '--configuration', 'Release', '--verbosity', 'minimal'
)
Invoke-CheckedCommand -FilePath 'dotnet' -ArgumentList @(
    'publish', (Join-Path $RepositoryRoot 'src\ScreenControl.Host\ScreenControl.Host.csproj'),
    '--configuration', 'Release', '--runtime', 'win-x64', '--self-contained', 'false',
    '-p:PublishSingleFile=true', '-p:DebugType=None', '-p:DebugSymbols=false',
    '--output', (Join-Path $PluginRoot 'bin')
)

Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @(
    'install', '--global', "matterbridge@$MatterbridgeVersion", '--omit=dev', '--no-fund', '--no-audit'
)
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('ci', '--no-fund', '--no-audit') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('link', '--no-fund', '--no-audit', 'matterbridge') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('test') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('run', 'typecheck') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('run', 'build') -WorkingDirectory $PluginRoot

Get-ChildItem -LiteralPath $ArtifactsRoot -Filter "$PluginName-*.tgz" -ErrorAction SilentlyContinue | Remove-Item -Force
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @(
    'pack', '--pack-destination', $ArtifactsRoot
) -WorkingDirectory $PluginRoot
$packagePath = Get-ChildItem -LiteralPath $ArtifactsRoot -Filter "$PluginName-*.tgz" |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($packagePath)) {
    throw 'The Matterbridge plugin package was not created.'
}

Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @(
    'install', '--global', $packagePath, '--omit=dev', '--no-fund', '--no-audit'
)
& matterbridge.cmd --remove $PluginName 2>$null | Out-Null
Invoke-CheckedCommand -FilePath 'matterbridge.cmd' -ArgumentList @('--add', $PluginName)
Invoke-CheckedCommand -FilePath 'matterbridge.cmd' -ArgumentList @('--enable', $PluginName)

$matterbridgeCommand = (Get-Command matterbridge.cmd -ErrorAction Stop).Source
$matterbridgeScript = Join-Path (Split-Path $matterbridgeCommand -Parent) 'node_modules\matterbridge\bin\matterbridge.js'
if (-not (Test-Path -LiteralPath $matterbridgeScript)) {
    throw "Matterbridge entry point was not found: $matterbridgeScript"
}

$taskArguments = @(
    "`"$matterbridgeScript`""
    '--nosudo'
    '--mdnsinterface'
    "`"$InterfaceAlias`""
    '--frontend'
    '8283'
    '--bind'
    '127.0.0.1'
    '--fixed_delay'
    '0'
    '--filelogger'
    '--no-ansi'
) -join ' '
$taskAction = New-ScheduledTaskAction -Execute $nodeExecutable -Argument $taskArguments -WorkingDirectory $HOME
$taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$taskTrigger.Delay = 'PT30S'
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger `
    -Settings $taskSettings -Principal $taskPrincipal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

if (-not $SkipSelfTest) {
    $hostExecutable = Join-Path $PluginRoot 'bin\ScreenControl.Host.exe'
    Invoke-CheckedCommand -FilePath $hostExecutable -ArgumentList @('--self-test')
}

[ordered]@{
    Installed = $true
    PluginName = $PluginName
    MatterbridgeVersion = $MatterbridgeVersion
    TaskName = $TaskName
    FrontendUrl = 'http://127.0.0.1:8283/'
    StatePath = $StatePath
    PackagePath = $packagePath
} | ConvertTo-Json -Depth 5
