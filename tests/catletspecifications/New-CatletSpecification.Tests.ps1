#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../../Use-Settings.ps1
  . $PSScriptRoot/../Helpers.ps1
  Setup-GenePool
}

Describe "Catlet-Specifications" {

  BeforeEach {
    $project = New-TestProject
    $specificationName = New-CatletSpecificationName
  }
  
  Context "New-CatletSpecification" {
    It "Creates catlet specification with JSON config" {
      $config = @"
{
  "name": "$specificationName",
  "parent": "dbosoft/e2etests-os/base",
  "variables": [
    {
      "name": "userName"
    }
  ],
  "fodder": [
    {
      "source": "gene:dbosoft/e2etests-fodder:greet-solar-system"
    }
  ]
}
"@
                    
      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config
      $versions = Get-CatletSpecificationVersion -SpecificationId $specification.Id
      $versions | Should -HaveCount 1
      $latestVersion = Get-CatletSpecificationVersion -SpecificationId $specification.Id -Id $versions[0].Id
      $latestVersion.Comment | Should -Be 'first version'
      $latestVersion.Configuration.ContentType | Should -Be 'application/yaml'
      $latestVersion.Configuration.Content | Should -be $config.ReplaceLineEndings("`n")
      $latestVersion.Variants | Should -HaveCount 1
      $latestVersion.Variants[0].Architecture | Should -Be 'hyperv/amd64'
      $latestVersion.Variants[0].PinnedGenes | Should -HaveCount 2
      $latestVersion.Variants[0].PinnedGenes[0].GeneSet | Should -Be 'dbosoft/e2etests-os/base-0.1'
      $latestVersion.Variants[0].PinnedGenes[0].Name | Should -Be 'catlet'
      $latestVersion.Variants[0].PinnedGenes[1].GeneSet | Should -Be 'dbosoft/ubuntu-24.04/20250913'
      $latestVersion.Variants[0].PinnedGenes[1].Name | Should -Be 'sda'
      $latestVersion.Variants[0].PinnedGenes[2].GeneSet | Should -Be 'dbosoft/e2etests-fodder/0.1'
      $latestVersion.Variants[0].PinnedGenes[2].Name | Should -Be 'greet-solar-system'
    }

    It "Creates catlet specification with YAML config" {
      $config = @"
name: $specificationName
parent: dbosoft/e2etests-os/base
variables:
- name: userName
fodder:
- source: gene:dbosoft/e2etests-fodder:greet-solar-system
"@
                    
      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config
      $versions = Get-CatletSpecificationVersion -SpecificationId $specification.Id
      $versions | Should -HaveCount 1
      $latestVersion = Get-CatletSpecificationVersion -SpecificationId $specification.Id -Id $versions[0].Id
      $latestVersion.Comment | Should -Be 'first version'
      $latestVersion.Configuration.ContentType | Should -Be 'application/yaml'
      $latestVersion.Configuration.Content | Should -be $config.ReplaceLineEndings("`n")
      $latestVersion.Variants | Should -HaveCount 1
      $latestVersion.Variants[0].Architecture | Should -Be 'hyperv/amd64'
      $latestVersion.Variants[0].PinnedGenes | Should -HaveCount 2
      $latestVersion.Variants[0].PinnedGenes[0].GeneSet | Should -Be 'dbosoft/e2etests-os/base-0.1'
      $latestVersion.Variants[0].PinnedGenes[0].Name | Should -Be 'catlet'
      $latestVersion.Variants[0].PinnedGenes[1].GeneSet | Should -Be 'dbosoft/ubuntu-24.04/20250913'
      $latestVersion.Variants[0].PinnedGenes[1].Name | Should -Be 'sda'
      $latestVersion.Variants[0].PinnedGenes[2].GeneSet | Should -Be 'dbosoft/e2etests-fodder/0.1'
      $latestVersion.Variants[0].PinnedGenes[2].Name | Should -Be 'greet-solar-system'
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
