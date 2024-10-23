#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
}

Describe "GenePool" {

  BeforeEach {
    Setup-GenePool
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
- source: gene:dbosoft/e2etests-fodder/0.1:greet-architecture
'@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $genes = Get-CatletGene
      $catletGene = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'catlet' -and $_.Architecture -eq 'any' }
      $catletGene | Should -Not -BeNullOrEmpty
      $fodderGene1 = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' -and $_.Architecture -eq 'any' }
      $fodderGene1 | Should -Not -BeNullOrEmpty
      $fodderGene2 = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-architecture' -and $_.Architecture -eq 'hyperv/amd64' }
      $fodderGene2 | Should -Not -BeNullOrEmpty
      $volumeGene = $genes | Where-Object { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' -and $_.Architecture -eq 'any' }
      $volumeGene | Should -Not -BeNullOrEmpty

      # Catlet genes can always be removed as they are not needed after the catlet has been created.
      Remove-CatletGene -Id $catletGene.Id -Force
      { Remove-CatletGene -Id $fodderGene1.Id -Force } |
        Should -Throw "*The gene fodder gene:dbosoft/e2etests-fodder/0.1:greet-user (any) is in use.*"
      { Remove-CatletGene -Id $fodderGene2.Id -Force } |
        Should -Throw "*The gene fodder gene:dbosoft/e2etests-fodder/0.1:greet-architecture (hyperv/amd64) is in use.*"
      { Remove-CatletGene -Id $volumeGene.Id -Force } |
        Should -Throw "*The gene volume gene:dbosoft/e2etests-nullos/0.1:sda (any) is in use.*"
      
      $genes = Get-CatletGene
      $genes | Assert-All { $_.GeneSet -ine 'dbosoft/e2etests-nullos/0.1' -or $_.Name -ine 'catlet' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' -and $_.Architecture -eq 'any' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-architecture' -and $_.Architecture -eq 'hyperv/amd64' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' -and $_.Architecture -eq 'any' }
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'catlet.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'greet-user.json') | Should -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'hyperv' 'amd64' 'greet-architecture.json') | Should -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'volumes' 'sda.vhdx') | Should -Exist

      Remove-Catlet -Id $catlet.Id -Force

      Remove-CatletGene -Id $fodderGene1.Id -Force
      Remove-CatletGene -Id $fodderGene2.Id -Force
      Remove-CatletGene -Id $volumeGene.Id -Force

      $genes = Get-CatletGene
      $genes | Assert-All { $_.GeneSet -ine 'dbosoft/e2etests-nullos/0.1' }
      $genes | Assert-All { -not ($_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' -and $_.Architecture -eq 'any') }
      $genes | Assert-All { -not ($_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-architecture' -and $_.Architecture -eq 'hyperv/amd64') }
      $genes | Assert-All { -not ($_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' -and $_.Architecture -eq 'any') }
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'catlet.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'greet-user.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'hyperv' 'amd64' 'greet-architecture.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'volumes' 'sda.vhdx') | Should -Not -Exist
    }

    It "Cleans up only unused genes" {
      $config = @'
parent: dbosoft/e2etests-nullos/0.1

fodder:
- source: gene:dbosoft/e2etests-fodder/0.1:greet-user
  variables:
  - name: userName
    value: Andy Astronaut
- source: gene:dbosoft/e2etests-fodder/0.1:greet-architecture
'@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $genes = Get-CatletGene
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'catlet' -and $_.Architecture -eq 'any' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' -and $_.Architecture -eq 'any' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-architecture' -and $_.Architecture -eq 'hyperv/amd64' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' -and $_.Architecture -eq 'any' }

      Remove-CatletGene -Unused -Force
      
      # Catlet genes can always be cleaned up as they are not needed after the catlet has been created.
      $genes = Get-CatletGene
      $genes | Assert-All { $_.GeneSet -ine 'dbosoft/e2etests-nullos/0.1' -or $_.Name -ine 'catlet' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' -and $_.Architecture -eq 'any' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-architecture' -and $_.Architecture -eq 'hyperv/amd64' }
      $genes | Assert-Any { $_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' -and $_.Architecture -eq 'any' }
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'catlet.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'greet-user.json') | Should -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'hyperv' 'amd64' 'greet-architecture.json') | Should -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'volumes' 'sda.vhdx') | Should -Exist

      Remove-Catlet -Id $catlet.Id -Force
      Remove-CatletGene -Unused -Force

      $genes = Get-CatletGene
      $genes | Assert-All { $_.GeneSet -ine 'dbosoft/e2etests-nullos/0.1' }
      $genes | Assert-All { -not ($_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-user' -and $_.Architecture -eq 'any') }
      $genes | Assert-All { -not ($_.GeneSet -eq 'dbosoft/e2etests-fodder/0.1' -and $_.Name -eq 'greet-architecture' -and $_.Architecture -eq 'hyperv/amd64') }
      $genes | Assert-All { -not ($_.GeneSet -eq 'dbosoft/e2etests-nullos/0.1' -and $_.Name -eq 'sda' -and $_.Architecture -eq 'any') }
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'catlet.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'greet-user.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-fodder' '0.1' 'fodder' 'hyperv' 'amd64' 'greet-architecture.json') | Should -Not -Exist
      (Join-Path $EryphSettings.LocalGenePoolPath 'dbosoft' 'e2etests-nullos' '0.1' 'volumes' 'sda.vhdx') | Should -Not -Exist
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
