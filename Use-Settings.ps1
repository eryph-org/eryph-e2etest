#Requires -Version 7.4

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

$EryphSettings = Get-Content -Raw -Path (Join-Path $PSScriptRoot "settings.json") `
| ConvertFrom-Json -AsHashtable

if ($EryphSettings.EryphZeroPath) {
  $env:Path = "$($EryphSettings.EryphZeroPath);$($env:Path)"
}

if ($env:E2E_ERYPH_ZERO_PATH) {
  $env:Path = "$($Env:E2E_ERYPH_ZERO_PATH);$($env:Path)"
}

if ($EryphSettings.EryphPackerPath) {
  $env:Path = "$($EryphSettings.EryphPackerPath);$($env:Path)"
}

if ($env:E2E_ERYPH_PACKER_PATH) {
  $env:Path = "$($Env:E2E_ERYPH_PACKER_PATH);$($env:Path)"
}

if ($EryphSettings.ComputeClientModulePath) {
  $env:PSModulePath = "$($EryphSettings.ComputeClientModulePath);$($env:PSModulePath)"
}

if ($env:E2E_COMPUTE_CLIENT_MODULE_PATH) {
  $env:PSModulePath = "$($Env:E2E_COMPUTE_CLIENT_MODULE_PATH);$($env:PSModulePath)"
}

if ($EryphSettings.ComputeClientPath) {
  if (-not (Get-module -Name "Eryph.ComputeClient.Commands")) {
    Remove-Module Eryph.ComputeClient -Force -ErrorAction SilentlyContinue
    Remove-Module (Join-Path $EryphSettings.ComputeClientPath "Eryph.ComputeClient.Commands.dll") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $EryphSettings.ComputeClientPath "Eryph.ComputeClient.Commands.dll") -Force
  }
}
elseif (-not (Get-Module -Name "Eryph.ComputeClient")) {
  Import-Module Eryph.ComputeClient 
}
