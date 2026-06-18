[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = $PSScriptRoot
$PluginRoot = Join-Path $RepositoryRoot 'plugin'
$SolutionPath = Join-Path $RepositoryRoot 'GoogleHomeScreenControl.sln'
$HostProjectPath = Join-Path $RepositoryRoot 'src\ScreenControl.Host\ScreenControl.Host.csproj'
$HostOutputPath = Join-Path $PluginRoot 'bin'

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

if ($null -eq (Get-Command matterbridge.cmd -ErrorAction SilentlyContinue)) {
    throw 'Matterbridge is not installed globally. Run: npm install --global matterbridge@3.9.0'
}
if ($null -eq (Get-Module -ListAvailable -Name Pester)) {
    throw 'Pester is not installed. Run: Install-Module Pester -Scope CurrentUser'
}

Invoke-CheckedCommand -FilePath 'dotnet' -ArgumentList @(
    'test', $SolutionPath, '--configuration', 'Release', '--verbosity', 'minimal'
)
Invoke-CheckedCommand -FilePath 'dotnet' -ArgumentList @(
    'publish', $HostProjectPath, '--configuration', 'Release', '--runtime', 'win-x64',
    '--self-contained', 'false', '-p:PublishSingleFile=true', '-p:DebugType=None',
    '-p:DebugSymbols=false', '--output', $HostOutputPath
)

Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('ci', '--no-fund', '--no-audit') `
    -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @(
    'link', '--no-fund', '--no-audit', 'matterbridge'
) -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('test') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('run', 'typecheck') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('run', 'build') -WorkingDirectory $PluginRoot
Invoke-CheckedCommand -FilePath 'npm.cmd' -ArgumentList @('run', 'pack:check') -WorkingDirectory $PluginRoot

$pesterResult = Invoke-Pester -Script (Join-Path $RepositoryRoot 'tests\PowerShell') -PassThru
if ($pesterResult.FailedCount -gt 0) {
    throw "$($pesterResult.FailedCount) PowerShell test(s) failed."
}

$syntaxErrors = @()
foreach ($scriptName in @('Install.ps1', 'Uninstall.ps1', 'Test-All.ps1')) {
    $scriptPath = Join-Path $RepositoryRoot $scriptName
    $fileErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$null,
        [ref]$fileErrors
    ) | Out-Null
    $syntaxErrors += @($fileErrors)
}
if ($syntaxErrors.Count -gt 0) {
    throw ($syntaxErrors | Out-String)
}

[ordered]@{
    Verified = $true
    DotNetTests = 'passed'
    TypeScriptTests = 'passed'
    TypeScriptTypecheck = 'passed'
    PackageDryRun = 'passed'
    PowerShellTests = 'passed'
    PowerShellSyntax = 'passed'
} | ConvertTo-Json
