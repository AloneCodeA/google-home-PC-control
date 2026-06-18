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
        ($report.PlannedActions -contains 'Enable IPv6 on Ethernet') | Should Be $true
        ($report.PlannedActions -contains 'Set Ethernet network category to Private') | Should Be $true
        ($report.PlannedActions -contains 'Build and install the Matterbridge plugin package') | Should Be $true
        ($report.PlannedActions -contains 'Create the Matterbridge logon scheduled task') | Should Be $true
    }
}
