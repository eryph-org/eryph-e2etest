#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "Projects" {

  Context "Remove-EryphProject" {

    It "Removes project with many resources" {
      $project = New-TestProject
      $catletPrefix = New-CatletName
      $diskPrefix = "testdisk-$(Get-Date -Format 'yyyyMMddHHmmss')"

      for ($i = 10; $i -lt 30; $i = $i + 10) {
        New-CatletDisk -Name "$diskPrefix-$($i)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 1)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 2)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 3)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 4)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 5)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 6)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 7)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 8)" -Size 5 -ProjectName $project.Name -Location test
        New-CatletDisk -Name "$diskPrefix-$($i + 9)" -Size 5 -ProjectName $project.Name -Location test
        
        $config = @"
parent: dbosoft/e2etests-os/base
drives:
- name: '$diskPrefix-$($i)'
  location: test
- name: '$diskPrefix-$($i + 1)'
  location: test
- name: '$diskPrefix-$($i + 2)'
  location: test
- name: '$diskPrefix-$($i + 3)'
  location: test
- name: '$diskPrefix-$($i + 4)'
  location: test
- name: '$diskPrefix-$($i + 5)'
  location: test
- name: '$diskPrefix-$($i + 6)'
  location: test
- name: '$diskPrefix-$($i + 7)'
  location: test
- name: '$diskPrefix-$($i + 8)'
  location: test
- name: '$diskPrefix-$($i + 9)'
  location: test
"@
        New-Catlet -Name "$catletPrefix-$i" -ProjectName $project.Name -Config $config
      }

      Remove-EryphProject -Id $project.Id -Force
    }
    
  }

}
