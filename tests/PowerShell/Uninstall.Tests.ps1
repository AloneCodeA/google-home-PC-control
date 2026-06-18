$ErrorActionPreference = 'Stop'

Describe 'Uninstall.ps1 validation' {
    It 'returns an auditable removal and restoration plan without changing the system' {
        $repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $uninstallScript = Join-Path $repositoryRoot 'Uninstall.ps1'

        $json = & $uninstallScript -ValidateOnly
        $report = $json | ConvertFrom-Json

        $report.PluginName | Should Be 'matterbridge-google-home-screen-control'
        $report.TaskName | Should Be 'Google Home Screen Control'
        $report.RestoreNetwork | Should Be $true
        $report.PurgeMatterData | Should Be $false
        ($report.PlannedActions -contains 'Stop and remove the Matterbridge logon scheduled task') | Should Be $true
        ($report.PlannedActions -contains 'Remove the Matterbridge plugin package') | Should Be $true
        ($report.PlannedActions -contains 'Remove the dedicated firewall rules') | Should Be $true
        ($report.PlannedActions -contains 'Restore the saved IPv6 and network category settings') | Should Be $true
        ($report.PlannedActions -contains 'Preserve Matter commissioning data') | Should Be $true
    }
}
