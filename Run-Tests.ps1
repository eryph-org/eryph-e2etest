#Requires -Version 7.4

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

Write-Output "Going to run eryph end-to-end tests"

Write-Output "Installing required Powershell modules..."
Install-Module -Name Pester -Force -Scope CurrentUser
Install-Module -Name Assert -Force -Scope CurrentUser
Install-Module -Name Posh-SSH -Force -Scope CurrentUser
Install-Module -Name Eryph.ComputeClient -Force -Scope CurrentUser

. $PSScriptRoot/Use-Settings.ps1

Write-Output "The following settings are configured"
Write-Output "EryphZeroPath: $($EryphSettings.EryphZeroPath)"
Write-Output "E2E_ERYPH_ZERO_PATH: $($env:E2E_ERYPH_ZERO_PATH)"
Write-Output "EryphPackerPath: $($EryphSettings.EryphPackerPath)"
Write-Output "E2E_ERYPH_PACKER_PATH: $($env:E2E_ERYPH_PACKER_PATH)"
Write-Output "ComputeClientPath: $($EryphSettings.ComputeClientPath)"
Write-Output "ComputeClientModulePath: $($EryphSettings.ComputeClientModulePath)"
Write-Output "E2E_COMPUTE_CLIENT_MODULE_PATH: $($env:E2E_COMPUTE_CLIENT_MODULE_PATH)"
Write-Output "LocalGenePoolPath: $($EryphSettings.LocalGenePoolPath)"
Write-Output "Path: $($Env:Path)"

Write-Output "The following compute client is used"
Get-Module -Name Eryph.ComputeClient | Format-List
Get-Module -Name Eryph.ComputeClient.Commands | Format-List

Write-Output "Setting up local gene pool..."
& $PSScriptRoot/Setup-LocalGenePool.ps1

Write-Output "Running tests..."
$pesterConfig = New-PesterConfiguration
$pesterConfig.Output.Verbosity = 'Detailed'
$pesterConfig.Run.Exit = $True
$pesterConfig.Run.Path = "$PSScriptRoot/tests"
$pesterConfig.TestResult.Enabled = $True
Invoke-Pester -Configuration $pesterConfig
