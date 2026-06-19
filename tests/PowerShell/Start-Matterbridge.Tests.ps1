$ErrorActionPreference = 'Stop'

Describe 'Start-Matterbridge.ps1 session preparation' {
    It 'removes only restart-sensitive Matter session caches' {
        $repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $launcherScript = Join-Path $repositoryRoot 'Start-Matterbridge.ps1'

        if (-not (Test-Path -LiteralPath $launcherScript)) {
            $false | Should Be $true
            return
        }

        $null = . $launcherScript -ValidateOnly

        $matterStorageRoot = Join-Path $TestDrive 'Matterbridge'
        New-Item -ItemType Directory -Path $matterStorageRoot -Force | Out-Null
        $resumptionPath = Join-Path $matterStorageRoot 'sessions.resumptionRecords'
        $subscriptionPath = Join-Path $matterStorageRoot 'root.subscriptions.subscriptions'
        $fabricPath = Join-Path $matterStorageRoot 'fabrics.fabrics'
        Set-Content -LiteralPath $resumptionPath -Value 'session-cache'
        Set-Content -LiteralPath $subscriptionPath -Value 'subscription-cache'
        Set-Content -LiteralPath $fabricPath -Value 'paired-fabric'

        $removed = @(Remove-MatterSessionCache -MatterStorageRoot $matterStorageRoot)

        ($removed -contains $resumptionPath) | Should Be $true
        ($removed -contains $subscriptionPath) | Should Be $true
        (Test-Path -LiteralPath $resumptionPath) | Should Be $false
        (Test-Path -LiteralPath $subscriptionPath) | Should Be $false
        (Test-Path -LiteralPath $fabricPath) | Should Be $true
        (Get-Content -LiteralPath $fabricPath -Raw).Trim() | Should Be 'paired-fabric'
    }

    It 'reports a clear timeout when the requested network interface never becomes ready' {
        $repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $launcherScript = Join-Path $repositoryRoot 'Start-Matterbridge.ps1'
        $powerShellExecutable = (Get-Command powershell.exe -ErrorAction Stop).Source
        $originalLocalAppData = $env:LOCALAPPDATA
        $errorMessage = $null

        try {
            $env:LOCALAPPDATA = $TestDrive
            & $launcherScript `
                -InterfaceAlias 'Missing-Matter-Test-Interface' `
                -NodeExecutable $powerShellExecutable `
                -MatterbridgeScript $launcherScript `
                -NetworkTimeoutSeconds 5
        }
        catch {
            $errorMessage = $_.Exception.Message
        }
        finally {
            $env:LOCALAPPDATA = $originalLocalAppData
        }

        $errorMessage | Should Match "did not obtain a preferred IPv6 address within 5 seconds"
    }

    It 'terminates an assigned child process when the launcher job handle closes' {
        $repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $launcherScript = Join-Path $repositoryRoot 'Start-Matterbridge.ps1'
        $null = . $launcherScript -ValidateOnly
        $initializerExists = $null -ne (Get-Command Initialize-KillOnCloseJobType -ErrorAction SilentlyContinue)

        $initializerExists | Should Be $true
        if (-not $initializerExists) {
            return
        }

        Initialize-KillOnCloseJobType
        $powerShellExecutable = (Get-Command powershell.exe -ErrorAction Stop).Source
        $childProcess = Start-Process -FilePath $powerShellExecutable `
            -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') `
            -WindowStyle Hidden -PassThru
        $job = [GoogleHomeScreenControl.KillOnCloseJob]::new()

        try {
            $job.Assign($childProcess)
            $job.Dispose()
            $exited = $childProcess.WaitForExit(5000)
        }
        finally {
            $job.Dispose()
            if (-not $childProcess.HasExited) {
                Stop-Process -Id $childProcess.Id -Force -ErrorAction SilentlyContinue
            }
            $childProcess.Dispose()
        }

        $exited | Should Be $true
    }
}
