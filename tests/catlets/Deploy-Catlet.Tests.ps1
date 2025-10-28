#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../../Use-Settings.ps1
  . $PSScriptRoot/../Helpers.ps1
  Setup-GenePool
}

Describe "Catlets" {

  BeforeEach {
    $project = New-TestProject
    $specificationName = New-CatletSpecificationName
  }
  
  Context "Deploy-Catlet" {
    It "Deploys catlet with parameterized fodder" {
      $config = @"
name: $specificationName
parent: dbosoft/e2etests-os/base
variables:
- name: userName
fodder: 
- name: add-user-greeting
  type: shellscript
  content: |
    #!/bin/bash
    echo 'Hello {{ userName }}!' >> hello-world.txt
- name: write-vm-id
  type: shellscript
  content: |
    #!/bin/bash
    echo '{{ vmId }}' >> hyperv-vm-id.txt
"@
                    
      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config

      $catlet = Deploy-Catlet -SpecificationId $specification.Id -SpecificationVersionId $specification.Latest.Id -Variables @{ username = "Eve E2E" }
      
      $catlet = Get-Catlet -Id $catlet.Id
      $catlet.Project.Id | Should -Be $project.Id
      $catlet.Name | Should -Be $specificationName
      $catlet.Specification.SpecificationId | Should -Be $specification.Id
      $catlet.Specification.SpecificationVersionId | Should -be $specification.Latest.Id

      $specification = Get-CatletSpecification -Id $specification.Id
      $specification.CatletId | Should -Be $catlet.Id
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be "Hello Eve E2E!"

      $vm = Get-VM -Name $specificationName
      $vmIdResponse = Invoke-SSHCommand -Command "cat /hyperv-vm-id.txt" -SSHSession $sshSession
      $vmIdResponse.Output | Should -Be $vm.Id
    }

    It "Redeploys existing catlet" {
      $config = @"
name: $specificationName
parent: dbosoft/e2etests-os/base
"@
                    
      $specification = New-CatletSpecification -Comment 'first version' -ProjectName $project.Name -Config $config

      $firstCatlet = Deploy-Catlet -SpecificationId $specification.Id -SpecificationVersionId $specification.Latest.Id -Variables @{ username = "Eve E2E" }
      
      $firstCatlet.Specification.SpecificationId | Should -Be $specification.Id
      $firstCatlet.Specification.SpecificationVersionId | Should -be $specification.Latest.Id

      $specification = Get-CatletSpecification -Id $specification.Id
      $specification.CatletId | Should -Be $firstCatlet.Id
      
      $secondCatlet = Deploy-Catlet -SpecificationId $specification.Id -SpecificationVersionId $specification.Latest.Id -Redeploy -Force

      $secondCatlet.Specification.SpecificationId | Should -Be $specification.Id
      $secondCatlet.Specification.SpecificationVersionId | Should -be $specification.Latest.Id

      $secondcatlet.Id | Should -Not -Be $firstCatlet.Id

      $specification = Get-CatletSpecification -Id $specification.Id
      $specification.CatletId | Should -Be $secondCatlet.Id
      
      $catlets = Get-Catlet -ProjectName $project.Name
      $catlets | Should -HaveCount 1
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
