#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "GenePool" {

  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
  }

  Describe "Remove-Gene" {
    It "Removes only unused genes" {
      $config = @'
parent: dbosoft/e2etests-nullos/0.1

fodder:
- source: gene:dbosoft/e2etests-fodder/0.1:greet-user
  variables:
  - name: userName
    value: Andy Astronaut
'@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $genes = Get-CatletGene
      $catletGene = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'catlet' }
      $catletGEne | Should -Not -BeNullOrEmpty
      $fodderGene = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' }
      $fodderGene | Should -Not -BeNullOrEmpty
      $volumeGene = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' }
      $volumeGene | Should -Not -BeNullOrEmpty

      # Catlet genes can always be removed as they are not needed after the catlet has been created.
      Remove-CatletGene -Id $catletGene.Id -Force
      (Join-Path EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'catlet.json') | Should -Not -Exist
      
      { Remove-CatletGene -Id $fodderGene.Id -Force } |
        Should -Throw "*The gene gene:dbosoft/e2etests-fodder/0.1:greet-user is in use.*"
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'greet-user.json') | Should -Exist
      { Remove-CatletGene -Id $volumeGene.Id -Force } |
        Should -Throw "*The gene gene:dbosoft/e2etests-nullos/0.1:sda is in use.*"
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'volumes' 'sda.vhdx') | Should -Exist

      Remove-Catlet -Id $catlet.Id -Force

      Remove-CatletGene -Id $fodderGene.Id -Force
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'greet-user.json') | Should -Not -Exist
      Remove-CatletGene -Id $volumeGene.Id -Force
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'volumes' 'sda.vhdx') | Should -Not -Exist

      $genes = Get-CatletGene
      $genes | Assert-All { $_.GeneSet -ine 'dbosoft/e2etests-nullos/0.1' }
      $genes | Assert-All { $_.GeneSet -ine 'dbosoft/e2etests-fodder/0.1' -or $_.Name -ine 'greet-user' }
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id
  }
}
