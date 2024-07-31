#Requires -Version 7.4

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/Use-Settings.ps1

function Setup-Gene {
  param(
    [Parameter(Mandatory = $true)]
    [string]
    $GeneSetTag
  )
  eryph-packer geneset-tag pack $GeneSetTag --workdir (Join-Path $PSScriptRoot "genesets")
  Remove-Item -Path (Join-Path $EryphSettings.LocalGenePoolPath $GeneSetTag) -Force -Recurse -ErrorAction SilentlyContinue
  Copy-Item -Path (Join-Path $PSScriptRoot "genesets" $GeneSetTag ".packed") `
    -Destination (Join-Path $EryphSettings.LocalGenePoolPath $GeneSetTag) `
    -Recurse
}

foreach ($manifestPath in (Get-ChildItem -Path (Join-Path $PSScriptRoot "genesets") -Filter "geneset-tag.json" -Recurse)) {
  $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json -AsHashtable
  Setup-Gene -GeneSetTag $manifest.geneset
}
