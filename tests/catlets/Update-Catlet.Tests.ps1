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
  
  Context "Update-Catlet" {
    # When updating a catlet, the name and project must be specified
    # in the config. Otherwise, eryph assumes the default values and
    # moves and renames the catlet.

    It "Updates catlet" {
      $config = @"
parent: dbosoft/e2etests-os/base
cpu:
  count: 2
memory:
  startup: 1024
drives:
- name: sda
  size: 100
"@

      $catlet = New-Catlet -Config $config -Name $catletName -ProjectName $project.Name
      
      $updateConfigYaml = Get-Catlet -Config -Id $catlet.Id
      $updateConfig = ConvertFrom-Yaml $updateConfigYaml
      $updateConfig.cpu.count = 3
      $updateConfig.memory.startup = 2048
      $updateConfig.drives[0].size = 150
      $updateConfigYaml = ConvertTo-Yaml $updateConfig

      Update-Catlet -Id $catlet.Id -Config $updateConfigYaml

      $vm = Get-VM -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 3
      $vm.MemoryStartup | Should -BeExactly 2048MB
      $vm.HardDrives | Should -HaveCount 1
      $vhd = Get-VHD -Path $vm.HardDrives[0].Path
      # Disk size should not change as the disks are skipped when a checkpoint exists
      $vhd.Size | Should -BeExactly 150GB
    }

    It "Disables previously enabled capabilities" {
      $config = @"
capabilities:
- name: dynamic_memory
- name: nested_virtualization
- name: secure_boot
  details:
  - template:MicrosoftUEFICertificateAuthority
- name: tpm
"@

      $catlet = New-Catlet -Config $config -Name $catletName -ProjectName $project.Name

      $vm = Get-VM -Name $catletName
      $vm.DynamicMemoryEnabled | Should -BeTrue

      $vmFirmware = Get-VMFirmware -VMName $catletName
      $vmFirmware.SecureBoot | Should -Be 'On'

      $vmSecurity = Get-VMSecurity -VMName $catletName
      $vmSecurity.TpmEnabled | Should -BeTrue

      $vmProcessor = Get-VMProcessor -VMName $catletName
      $vmProcessor.ExposeVirtualizationExtensions | Should -BeTrue

      $updateConfigYaml = Get-Catlet -Config -Id $catlet.Id
      $updateConfig = ConvertFrom-Yaml $updateConfigYaml
      $updateConfig.capabilities = $null
      # eryph should and will keep the dynamic memory enabled
      # when a minimum or maximum value is provided. When the
      # catlet was created, the Hyper-V default values were applied.
      $updateConfig.memory.minimum = $null
      $updateConfig.memory.maximum = $null
      $updateConfigYaml = ConvertTo-Yaml $updateConfig

      Update-Catlet -Id $catlet.Id -Config $updateConfigYaml

      $vm = Get-VM -Name $catletName
      $vm.DynamicMemoryEnabled | Should -BeFalse

      $vmFirmware = Get-VMFirmware -VMName $catletName
      $vmFirmware.SecureBoot | Should -Be 'Off'

      $vmSecurity = Get-VMSecurity -VMName $catletName
      $vmSecurity.TpmEnabled | Should -BeFalse

      $vmProcessor = Get-VMProcessor -VMName $catletName
      $vmProcessor.ExposeVirtualizationExtensions | Should -BeFalse
    }

    It "Updates catlet with checkpoint but does not change disks" {
      $config = @"
parent: dbosoft/e2etests-os/base
cpu:
  count: 2
drives:
- name: sda
  size: 100
"@

      $catlet = New-Catlet -Config $config -Name $catletName -ProjectName $project.Name
      Checkpoint-VM -Name $catlet.Name

      $updateConfigYaml = Get-Catlet -Config -Id $catlet.Id
      $updateConfig = ConvertFrom-Yaml $updateConfigYaml
      $updateConfig.cpu.count = 3
      $updateConfig.drives[0].size = 150
      $updateConfigYaml = ConvertTo-Yaml $updateConfig

      Update-Catlet -Id $catlet.Id -Config $updateConfigYaml

      $vm = Get-VM -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 3
      $vm.HardDrives | Should -HaveCount 1
      $vhd = Get-VHD -Path $vm.HardDrives[0].Path
      # Disk size should not change as the disks are skipped when a checkpoint exists
      $vhd.Size | Should -BeExactly 100GB
    }
    
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
