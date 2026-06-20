[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InterfaceAlias = 'Ethernet',

    [Parameter()]
    [string]$NodeExecutable,

    [Parameter()]
    [string]$MatterbridgeScript,

    [Parameter()]
    [ValidateRange(5, 600)]
    [int]$NetworkTimeoutSeconds = 120,

    [Parameter()]
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateRoot = Join-Path $env:LOCALAPPDATA 'GoogleHomeScreenControl'
$LauncherLogPath = Join-Path $StateRoot 'launcher.log'
$MatterStorageRoot = Join-Path $HOME '.matterbridge\matterstorage\Matterbridge'

function Write-LauncherLog {
    <#
    .SYNOPSIS
    Writes a timestamped Matterbridge launcher diagnostic message.

    .DESCRIPTION
    Appends one UTF-8 line to the launcher log under the application state
    directory. The function creates the state directory when required.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
    Add-Content -LiteralPath $LauncherLogPath -Value "[$timestamp] $Message" -Encoding UTF8
}

function Test-MatterNetworkReady {
    <#
    .SYNOPSIS
    Determines whether the configured Matter network interface is ready.

    .DESCRIPTION
    Returns true only when the adapter is up, IPv6 is enabled, and Windows has
    assigned at least one preferred IPv6 address to the interface.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetworkInterfaceAlias
    )

    $adapter = Get-NetAdapter -Name $NetworkInterfaceAlias -ErrorAction SilentlyContinue
    if ($null -eq $adapter -or $adapter.Status -ne 'Up') {
        return $false
    }

    $ipv6Binding = Get-NetAdapterBinding -Name $NetworkInterfaceAlias `
        -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    if ($null -eq $ipv6Binding -or -not $ipv6Binding.Enabled) {
        return $false
    }

    $preferredIpv6Address = Get-NetIPAddress -InterfaceAlias $NetworkInterfaceAlias `
        -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.AddressState -eq 'Preferred' } |
        Select-Object -First 1
    return $null -ne $preferredIpv6Address
}

function Remove-MatterSessionCache {
    <#
    .SYNOPSIS
    Removes restart-sensitive Matter session cache files.

    .DESCRIPTION
    Deletes only resumption and subscription cache files beneath the supplied
    Matter storage root. Fabric and commissioning data are deliberately kept.
    The full-path boundary check prevents deletion outside the storage root.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$MatterStorageRoot
    )

    $fullStorageRoot = [System.IO.Path]::GetFullPath($MatterStorageRoot)
    $storagePrefix = $fullStorageRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($fileName in @('sessions.resumptionRecords', 'root.subscriptions.subscriptions')) {
        $cachePath = [System.IO.Path]::GetFullPath((Join-Path $fullStorageRoot $fileName))
        if (-not $cachePath.StartsWith($storagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Matter session cache path escaped its storage root: $cachePath"
        }

        if (Test-Path -LiteralPath $cachePath) {
            Remove-Item -LiteralPath $cachePath -Force
            Write-Output $cachePath
        }
    }
}

if ($ValidateOnly) {
    [ordered]@{
        InterfaceAlias = $InterfaceAlias
        NetworkTimeoutSeconds = $NetworkTimeoutSeconds
        MatterStorageRoot = $MatterStorageRoot
        SessionCacheFiles = @(
            'sessions.resumptionRecords'
            'root.subscriptions.subscriptions'
        )
        FabricFilesPreserved = $true
    } | ConvertTo-Json -Depth 4
    return
}

if ([string]::IsNullOrWhiteSpace($NodeExecutable) -or -not (Test-Path -LiteralPath $NodeExecutable)) {
    throw "Node.js executable was not found: $NodeExecutable"
}
if ([string]::IsNullOrWhiteSpace($MatterbridgeScript) -or -not (Test-Path -LiteralPath $MatterbridgeScript)) {
    throw "Matterbridge entry point was not found: $MatterbridgeScript"
}

Write-LauncherLog "Waiting for interface '$InterfaceAlias' and a preferred IPv6 address."
$networkDeadline = [DateTime]::UtcNow.AddSeconds($NetworkTimeoutSeconds)
$networkReady = $false
do {
    if (Test-MatterNetworkReady -NetworkInterfaceAlias $InterfaceAlias) {
        $networkReady = $true
        break
    }

    Start-Sleep -Seconds 1
} while ([DateTime]::UtcNow -lt $networkDeadline)

if (-not $networkReady) {
    Write-LauncherLog "Network readiness timed out after $NetworkTimeoutSeconds seconds."
    throw "Interface '$InterfaceAlias' did not obtain a preferred IPv6 address within $NetworkTimeoutSeconds seconds."
}

$removedCacheFiles = @(Remove-MatterSessionCache -MatterStorageRoot $MatterStorageRoot)
Write-LauncherLog "Network is ready. Removed $($removedCacheFiles.Count) stale Matter session cache file(s)."

$matterbridgeArguments = @(
    "`"$MatterbridgeScript`""
    '--nosudo'
    '--mdnsinterface'
    "`"$InterfaceAlias`""
    '--frontend'
    '8283'
    '--bind'
    '127.0.0.1'
    '--fixed_delay'
    '1'
    '--filelogger'
    '--no-ansi'
)

Write-LauncherLog 'Starting Matterbridge.'
$matterbridgeProcess = $null
try {
    $matterbridgeProcess = Start-Process -FilePath $NodeExecutable `
        -ArgumentList $matterbridgeArguments -WindowStyle Hidden -PassThru
    $matterbridgeProcess.WaitForExit()
    $matterbridgeExitCode = $matterbridgeProcess.ExitCode
}
catch {
    if ($null -ne $matterbridgeProcess -and -not $matterbridgeProcess.HasExited) {
        Stop-Process -Id $matterbridgeProcess.Id -Force -ErrorAction SilentlyContinue
    }
    throw
}
finally {
    if ($null -ne $matterbridgeProcess) {
        $matterbridgeProcess.Dispose()
    }
}

Write-LauncherLog "Matterbridge exited with code $matterbridgeExitCode."
exit $matterbridgeExitCode
