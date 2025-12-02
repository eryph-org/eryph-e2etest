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
  
  Context "Remove-CatletSpecification" {

    It "Removes catlet specification which is not deployed" {
      $config = @"
name: $specificationName
"@
                    
      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config
      $versions = Get-CatletSpecificationVersion -SpecificationId $specification.Id
      $versions | Should -HaveCount 1

      Remove-CatletSpecification -Id $specification.Id -Force
      $specifications = Get-CatletSpecification -ProjectName $project.Name
      $specifications | Should -HaveCount 0
    }

    It "Removes catlet specification which is deployed" {
      $config = @"
name: $specificationName
"@

      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config
      $versions = Get-CatletSpecificationVersion -SpecificationId $specification.Id
      $versions | Should -HaveCount 1

      Deploy-Catlet -SpecificationId $specification.Id -SpecificationVersionId $specification.Latest.Id

      Remove-CatletSpecification -Id $specification.Id -RemoveCatlet -Force
      $specifications = Get-CatletSpecification -ProjectName $project.Name
      $specifications | Should -HaveCount 0
    }

    It "Does not remove catlet specification which is deployed" {
      $config = @"
name: $specificationName
"@

      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config
      $versions = Get-CatletSpecificationVersion -SpecificationId $specification.Id
      $versions | Should -HaveCount 1

      Deploy-Catlet -SpecificationId $specification.Id -SpecificationVersionId $specification.Latest.Id

      { Remove-CatletSpecification -Id $specification.Id -Force } | Should -Throw '*The catlet specification is deployed as a catlet.*'
      $specifications = Get-CatletSpecification -ProjectName $project.Name
      $specifications | Should -HaveCount 1
      $specifications[0].Id | Should -Be $specification.Id
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
