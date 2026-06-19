$ErrorActionPreference = 'Stop'

Describe 'Install.ps1 validation' {
    It 'returns an auditable plan without changing the system' {
        $repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $installScript = Join-Path $repositoryRoot 'Install.ps1'

        $json = & $installScript -ValidateOnly -InterfaceAlias 'Ethernet'
        $report = $json | ConvertFrom-Json

        $report.InterfaceAlias | Should Be 'Ethernet'
        $report.OperatingSystemSupported | Should Be $true
        $report.NodeVersionSupported | Should Be $true
        $report.DotNet8RuntimeAvailable | Should Be $true
        $report.AdapterFound | Should Be $true
        $report.AdapterUp | Should Be $true
        $report.InterfaceMatchesSavedState | Should Be $true
        ($report.PlannedActions -contains 'Enable IPv6 on Ethernet') | Should Be $true
        ($report.PlannedActions -contains 'Set Ethernet network category to Private') | Should Be $true
        ($report.PlannedActions -contains 'Build and install the Matterbridge plugin package') | Should Be $true
        ($report.PlannedActions -contains 'Create the Matterbridge logon scheduled task') | Should Be $true

        $scriptText = Get-Content -LiteralPath $installScript -Raw
        $scriptText | Should Match 'Start-Matterbridge\.ps1'
        $scriptText | Should Match "'-WindowStyle'\s*'Hidden'"
        $scriptText | Should Not Match 'WScript\.Shell'
        $scriptText | Should Match '-RunOnlyIfNetworkAvailable'
        $scriptText | Should Match "Delay\s*=\s*'PT5S'"
        $scriptText | Should Match 'automaticStartDeadline'
        $scriptText.Contains("if (`$registeredTask.State -ne 'Running')") | Should Be $true

        $launcherText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Start-Matterbridge.ps1') -Raw
        $launcherText | Should Match "'--fixed_delay'\s*'1'"
    }
}
