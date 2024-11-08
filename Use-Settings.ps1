#Requires -Version 7.4

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

$EryphSettings = Get-Content -Raw -Path (Join-Path $PSScriptRoot "settings.json") `
| ConvertFrom-Json -AsHashtable

if ($EryphSettings.EryphZeroPath) {
  $env:Path = "$($EryphSettings.EryphZeroPath);$($env:Path)"
}

if ($env:E2E_ERYPH_ZERO_PATH) {
  $env:Path = "$($env:E2E_ERYPH_ZERO_PATH);$($env:Path)"
}

if ($EryphSettings.EryphPackerPath) {
  $env:Path = "$($EryphSettings.EryphPackerPath);$($env:Path)"
}

if ($env:E2E_ERYPH_PACKER_PATH) {
  $env:Path = "$($env:E2E_ERYPH_PACKER_PATH);$($env:Path)"
}

if ($EryphSettings.ClientRuntimeModulePath) {
  $env:PSModulePath = "$($EryphSettings.ComputeClientModulePath);$($env:PSModulePath)"
}

if ($env:E2E_CLIENT_RUNTIME_MODULE_PATH) {
  $env:PSModulePath = "$($env:E2E_CLIENT_RUNTIME_MODULE_PATH);$($env:PSModulePath)"
}

if (-not (Get-Module -Name "Eryph.ClientRuntime.Configuration")) {
  Import-Module Eryph.ClientRuntime.Configuration 
}

if ($EryphSettings.ComputeClientModulePath) {
  $env:PSModulePath = "$($EryphSettings.ComputeClientModulePath);$($env:PSModulePath)"
}

if ($env:E2E_COMPUTE_CLIENT_MODULE_PATH) {
  $env:PSModulePath = "$($env:E2E_COMPUTE_CLIENT_MODULE_PATH);$($env:PSModulePath)"
}

if (-not (Get-Module -Name "Eryph.ComputeClient")) {
  Import-Module Eryph.ComputeClient 
}

if ($EryphSettings.IdentityClientModulePath) {
  $env:PSModulePath = "$($EryphSettings.IdentityClientModulePath);$($env:PSModulePath)"
}

if ($env:E2E_IDENTITY_CLIENT_MODULE_PATH) {
  $env:PSModulePath = "$($env:E2E_IDENTITY_CLIENT_MODULE_PATH);$($env:PSModulePath)"
}

if (-not (Get-Module -Name "Eryph.IdentityClient")) {
  Import-Module Eryph.IdentityClient
}
