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

function Initialize-KillOnCloseJobType {
    $existingType = [System.Management.Automation.PSTypeName]'GoogleHomeScreenControl.KillOnCloseJob'
    if ($null -ne $existingType.Type) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace GoogleHomeScreenControl
{
    public sealed class KillOnCloseJob : IDisposable
    {
        private const uint JobObjectLimitKillOnJobClose = 0x00002000;
        private IntPtr handle;

        public KillOnCloseJob()
        {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed.");
            }

            var information = new JobObjectExtendedLimitInformation();
            information.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
            int informationLength = Marshal.SizeOf(typeof(JobObjectExtendedLimitInformation));
            IntPtr informationPointer = Marshal.AllocHGlobal(informationLength);

            try
            {
                Marshal.StructureToPtr(information, informationPointer, false);
                if (!SetInformationJobObject(handle, 9, informationPointer, (uint)informationLength))
                {
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "SetInformationJobObject failed."
                    );
                }
            }
            catch
            {
                Dispose();
                throw;
            }
            finally
            {
                Marshal.FreeHGlobal(informationPointer);
            }
        }

        public void Assign(Process process)
        {
            if (process == null)
            {
                throw new ArgumentNullException("process");
            }
            if (handle == IntPtr.Zero)
            {
                throw new ObjectDisposedException("KillOnCloseJob");
            }
            if (!AssignProcessToJobObject(handle, process.Handle))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "AssignProcessToJobObject failed."
                );
            }
        }

        public void Dispose()
        {
            if (handle == IntPtr.Zero)
            {
                return;
            }

            CloseHandle(handle);
            handle = IntPtr.Zero;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JobObjectBasicLimitInformation
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JobObjectExtendedLimitInformation
        {
            public JobObjectBasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr securityAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
'@
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
Initialize-KillOnCloseJobType
$killOnCloseJob = [GoogleHomeScreenControl.KillOnCloseJob]::new()
$matterbridgeProcess = $null
try {
    $matterbridgeProcess = Start-Process -FilePath $NodeExecutable `
        -ArgumentList $matterbridgeArguments -WindowStyle Hidden -PassThru
    $killOnCloseJob.Assign($matterbridgeProcess)
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
    $killOnCloseJob.Dispose()
    if ($null -ne $matterbridgeProcess) {
        $matterbridgeProcess.Dispose()
    }
}

Write-LauncherLog "Matterbridge exited with code $matterbridgeExitCode."
exit $matterbridgeExitCode
