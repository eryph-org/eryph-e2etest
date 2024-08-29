#Requires -Version 7.4

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

Write-Output "Going to run eryph end-to-end tests"

Write-Output "Installing required Powershell modules..."
Install-Module -Name Pester -Force -Scope CurrentUser
Install-Module -Name Posh-SSH -Force -Scope CurrentUser
Install-Module -Name Eryph.ComputeClient -Force -Scope CurrentUser

. $PSScriptRoot/Use-Settings.ps1

Write-Output "The following settings are configured"
Write-Output "EryphZeroPath: $($EryphSettings.EryphZeroPath)"
Write-Output "EryphPackerPath: $($EryphSettings.EryphPackerPath)"
Write-Output "ComputeClientPath: $($EryphSettings.ComputeClientPath)"
Write-Output "LocalGenePoolPath: $($EryphSettings.LocalGenePoolPath)"
Write-Output "Path: $($Env:Path)"

Write-Output "Setting up local gene pool"
& $PSScriptRoot/Setup-LocalGenePool.ps1

Write-Output "Running tests..."
Invoke-Pester -Path $PSScriptRoot/tests -CI -TagFilter "UbuntuStarter"
