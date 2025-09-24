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
    # The powershell-yaml cmdlet must be invoked before the ComputeClient cmdlets
    # to avoid a type conflict with YamlDotNet.
    ConvertFrom-Yaml ""
    
    $project = New-TestProject
    $catletName = New-CatletName
  }

  Context "Inventory" {
    It "Updates inventory when catlet is changed in Hyper-V" {
      $config = @"
parent: dbosoft/e2etests-os/base
cpu:
  count: 1
memory:
  startup: 1024
"@
      $catlet = New-Catlet -Config $config -Name $catletName -ProjectName $project.Name

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

    It "Updates inventory when catlet is removed in Hyper-V" {
      $config = @"
parent: dbosoft/e2etests-os/base
cpu:
  count: 1
memory:
  startup: 1024
"@
      $catlet = New-Catlet -Config $config -Name $catletName -ProjectName $project.Name

      $vm = Get-Vm -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 1
      $vm.MemoryStartup | Should -BeExactly 1024MB

      Remove-VM -Name $catletName -Force

      Wait-Assert {
        $updatedCatlet = Get-Catlet -Id $catlet.Id
        $updatedCatlet.Status | Should -Be Missing
      }
    }


    It "Removes VM hardware which has been removed from the config" {
      $config = @"
parent: dbosoft/e2etests-os/base
drives:
- name: sda
- name: sdb
  size: 50
"@
      $catlet = New-Catlet -Config $config -Name $catletName -ProjectName $project.Name

      $vm = Get-VM -Name $catletName
      $vm.HardDrives | Should -HaveCount 2
      $vm.HardDrives | Assert-Any { $_.Path.EndsWith('\sda_g1.vhdx') }
      $vm.HardDrives | Assert-Any { $_.Path.EndsWith('\sdb.vhdx') }
      $vm.NetworkAdapters | Should -HaveCount 1
      $vm.NetworkAdapters | Assert-Any { $_.Name -eq 'eth0' }

      $updateConfigYaml = Get-Catlet -Config -Id $catlet.Id
      $updateConfig = ConvertFrom-Yaml $updateConfigYaml
      $updateConfig.drives | Should -HaveCount 2
      $updateConfig.drives = @($updateConfig.drives | Select-Object -First 1)
      # Remove the default network which should also remove the network adapter.
      $updateConfig.networks = $null
      $updateConfigYaml = ConvertTo-Yaml $updateConfig

      Update-Catlet -Id $catlet.Id -Config $updateConfigYaml

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
