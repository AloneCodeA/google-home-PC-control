[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [bool]$RestoreNetwork = $true,

    [Parameter()]
    [switch]$PurgeMatterData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'Google Home Screen Control'
$PluginName = 'matterbridge-google-home-screen-control'
$MdnsFirewallRule = 'Google Home Screen Control - mDNS'
$MatterFirewallRule = 'Google Home Screen Control - Matter'
$StateRoot = Join-Path $env:LOCALAPPDATA 'GoogleHomeScreenControl'
$StatePath = Join-Path $StateRoot 'install-state.json'
$LauncherExecutablePath = Join-Path $StateRoot 'ScreenControl.Launcher.exe'
$LauncherScriptPath = Join-Path $StateRoot 'Start-Matterbridge.ps1'
$LegacyLauncherHostPath = Join-Path $StateRoot 'Start-Matterbridge.vbs'
$LauncherLogPath = Join-Path $StateRoot 'launcher.log'
$MatterbridgeDataPath = Join-Path $HOME '.matterbridge'
$MatterCertificatePath = Join-Path $HOME '.mattercert'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ToleratedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [string[]]$ArgumentList = @()
    )

    $command = Get-Command $FilePath -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return
    }

    & $command.Source @ArgumentList 2>$null | Out-Null
}

$stateExists = Test-Path -LiteralPath $StatePath
$plannedActions = @(
    'Stop and remove the Matterbridge logon scheduled task'
    'Disable and unregister the Computer Screen plugin'
    'Remove the Matterbridge plugin package'
    'Remove the local Matterbridge launcher and its log'
    'Remove the dedicated firewall rules'
)
if ($RestoreNetwork) {
    $plannedActions += 'Restore the saved IPv6 and network category settings'
}
if ($PurgeMatterData) {
    $plannedActions += 'Delete Matter commissioning data'
}
else {
    $plannedActions += 'Preserve Matter commissioning data'
}

$report = [ordered]@{
    PluginName = $PluginName
    TaskName = $TaskName
    StatePath = $StatePath
    StateFound = $stateExists
    RestoreNetwork = $RestoreNetwork
    PurgeMatterData = [bool]$PurgeMatterData
    IsAdministrator = Test-IsAdministrator
    PlannedActions = $plannedActions
}
if ($ValidateOnly) {
    $report | ConvertTo-Json -Depth 5
    return
}

if (-not $report.IsAdministrator) {
    throw 'Run Uninstall.ps1 from an elevated PowerShell window.'
}
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Uninstall Google Home Screen Control')) {
    return
}

$scheduledTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $scheduledTask) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    $stopDeadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $runningScreenControlProcesses = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -eq 'ScreenControl.Launcher.exe' -or
            ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Start-Matterbridge.ps1*') -or
            ($_.Name -eq 'node.exe' -and $_.CommandLine -like '*node_modules\matterbridge\bin\matterbridge.js*') -or
            $_.Name -eq 'ScreenControl.Host.exe'
        })
        if ($runningScreenControlProcesses.Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $stopDeadline)

    if ($runningScreenControlProcesses.Count -gt 0) {
        throw 'The screen-control process tree did not stop within 15 seconds.'
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Invoke-ToleratedCommand -FilePath 'matterbridge.cmd' -ArgumentList @('--disable', $PluginName)
Invoke-ToleratedCommand -FilePath 'matterbridge.cmd' -ArgumentList @('--remove', $PluginName)
Invoke-ToleratedCommand -FilePath 'npm.cmd' -ArgumentList @(
    'uninstall', '--global', $PluginName, '--no-fund', '--no-audit'
)

Remove-NetFirewallRule -DisplayName $MdnsFirewallRule -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName $MatterFirewallRule -ErrorAction SilentlyContinue

if ($RestoreNetwork -and $stateExists) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    $adapter = Get-NetAdapter -Name $state.InterfaceAlias -ErrorAction SilentlyContinue
    if ($null -ne $adapter) {
        if ([bool]$state.OriginalIpv6Enabled) {
            Enable-NetAdapterBinding -Name $state.InterfaceAlias -ComponentID ms_tcpip6 | Out-Null
        }
        else {
            Disable-NetAdapterBinding -Name $state.InterfaceAlias -ComponentID ms_tcpip6 | Out-Null
        }

        Set-NetConnectionProfile -InterfaceAlias $state.InterfaceAlias `
            -NetworkCategory $state.OriginalNetworkCategory
    }
}

if ($PurgeMatterData) {
    Remove-Item -LiteralPath $MatterbridgeDataPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $MatterCertificatePath -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $LauncherExecutablePath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $LauncherScriptPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $LegacyLauncherHostPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $LauncherLogPath -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $StateRoot) {
    $remainingState = Get-ChildItem -LiteralPath $StateRoot -Force -ErrorAction SilentlyContinue
    if ($null -eq $remainingState) {
        Remove-Item -LiteralPath $StateRoot -Force
    }
}

[ordered]@{
    Uninstalled = $true
    NetworkRestored = $RestoreNetwork -and $stateExists
    MatterDataPurged = [bool]$PurgeMatterData
    MatterDataPreserved = -not [bool]$PurgeMatterData
} | ConvertTo-Json -Depth 5
