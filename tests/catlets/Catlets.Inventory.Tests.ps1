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
    $catletName = New-CatletName
  }

    Context "Inventory" {
    It "Updates inventory when catlet is changed in Hyper-V" {
      $config = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
cpu:
  count: 1
memory:
  startup: 1024
"@
      $catlet = New-Catlet -Config $config

      $vm = Get-Vm -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 1
      $vm.MemoryStartup | Should -BeExactly 1024MB

      Set-VM -Name $catletName -ProcessorCount 3 -MemoryStartupBytes 2048MB

      Wait-Assert {
        $catletConfig = Get-Catlet -Id $catlet.Id -Config
        $catletConfig | Should -Match 'cpu:\s+count: 3'
        $catletConfig | Should -Match 'memory:\s+startup: 2048'
      }
    }

    It "Removes VM hardware which has been removed from the config" {
      $config = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
drives:
- name: sda
- name: sdb
  size: 50
"@
      $catlet = New-Catlet -Config $config

      $vm = Get-VM -Name $catletName
      $vm.HardDrives | Should -HaveCount 2
      $vm.HardDrives | Assert-Any { $_.Path.EndsWith('\sda_g1.vhdx') }
      $vm.HardDrives | Assert-Any { $_.Path.EndsWith('\sdb.vhdx') }
      $vm.NetworkAdapters | Should -HaveCount 1
      $vm.NetworkAdapters | Assert-Any { $_.Name -eq 'eth0' }

      # Remove the default network which should also remove the network adapter.
      $updateConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
drives:
- name: sda
networks:
- name: default
  mutation: remove
"@

      Update-Catlet -Id $catlet.Id -Config $updateConfig

      $vm = Get-VM -Name $catletName
      $vm.HardDrives | Should -HaveCount 1
      $vm.HardDrives | Assert-Any { $_.Path.EndsWith('\sda_g1.vhdx') }
      $vm.NetworkAdapters | Should -HaveCount 0
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
