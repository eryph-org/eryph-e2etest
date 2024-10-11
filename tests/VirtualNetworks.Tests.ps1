#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "VirtualNetworks" {
  BeforeEach {
    $project = New-TestProject
  }

  Context "Set-VNetwork" {
    It "Configures the network" {
      $networkConfig = @'
version: 1.0
project: default
networks:
- name: test-network
  address: 10.0.100.0/28
  subnets:
  - name: test-subnet
    ip_pools:
    - name: test-pool
      first_ip: 10.0.100.8
      last_ip: 10.0.100.15
      next_ip: 10.0.100.12
'@
      Set-VNetwork -ProjectName $project.Name -Config $networkConfig -Force

      $catletConfig = @'
parent: dbosoft/e2etests-os/base
networks:
- name: test-network
  subnet_v4:
    name: test-subnet
    ip_pool: test-pool
'@
      $catlet = New-Catlet -ProjectName $project.Name -Config $catletConfig
      
      # TODO validate catlet
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
