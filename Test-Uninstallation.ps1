# This script tests the uninstallation of eryph-zero. These tests are run
# separately for sequencing reasons. Also, we do want to accidentally uninstall
# eryph on a developer's machine.
#Requires -Version 7.4
#Requires -Module Pester

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

Write-Output "Testing the uninstallation of eryph-zero..."

# Verify that the expected data exists before uninstalling eryph-zero.
"C:\ProgramData\eryph" | Should -Exist
"C:\ProgramData\openvswitch" | Should -Exist

$service = Get-Service -Name "*eryph*"
$service | Should -HaveCount 1

$driver = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -ilike "*dbo_ovse*" }
$driver | Should -HaveCount 1

Write-Output "Uninstalling eryph-zero..."
$output = & "C:\Program Files\eryph\zero\bin\eryph-zero.exe" uninstall --delete-app-data

Write-Output $output
# Verify that the uninstaller has not logged any warnings.
$output | Should -Not -BeLike "*WRN]*"

# Verify that the data no longer exist after uninstalling eryph-zero.
"C:\ProgramData\eryph" | Should -Not -Exist
"C:\ProgramData\openvswitch" | Should -Not -Exist

$service = Get-Service -Name "*eryph*"
$service | Should -HaveCount 0

$driver = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -ilike "*dbo_ovse*" }
$driver | Should -HaveCount 0
