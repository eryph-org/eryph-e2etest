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
    $catletName = New-CatletName
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

      $projectNetworks = Get-VNetwork -ProjectName $project.Name
      $projectNetworks | Should -HaveCount 1
      $projectNetworks[0].Name | Should -Be 'test-network'
      $projectNetworks[0].Environment | Should -Be 'default'
      $projectNetworks[0].IpNetwork | Should -Be '10.0.100.0/28'

      $catletConfig = @'
parent: dbosoft/e2etests-os/base
networks:
- name: test-network
  subnet_v4:
    name: test-subnet
    ip_pool: test-pool
'@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $catletConfig
      $catlet.Networks | Should -HaveCount 1
      $catlet.Networks[0].Name | Should -Be 'test-network'
      $catlet.Networks[0].IpV4Addresses | Should -HaveCount 1
      $catlet.Networks[0].IpV4Addresses | Should -Be '10.0.100.12'
      $catlet.Networks[0].IpV4Subnets | Should -HaveCount 1
      $catlet.Networks[0].IpV4Subnets[0] | Should -Be '10.0.100.0/28'

      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command "ip addr" -SSHSession $sshSession
      $sshResponse.Output | Assert-Any { $_ -ilike '*inet 10.0.100.12/28*' }
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
