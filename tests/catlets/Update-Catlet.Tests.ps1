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
  
    Context "Update-Catlet" {
    # When updating a catlet, the name and project must be specified
    # in the config. Otherwise, eryph assumes the default values and
    # moves and renames the catlet.

    It "Updates catlet when parent is not changed" {
      $config = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
cpu:
  count: 2
"@

      $catlet = New-Catlet -Config $config

      $updatedConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
cpu:
  count: 3
"@
      Update-Catlet -Id $catlet.Id -Config $updatedConfig

      $vm = Get-VM -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 3
    }

    It "Updates catlet even when required variables are not specified" {
      $config = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
memory:
  startup: 1024
variables:
- name: userName
  required: true
fodder: 
- name: add-user-greeting
  type: shellscript
  content: |
    #!/bin/bash
    echo 'Hello {{ userName }}!' >> hello-world.txt
"@

      $catlet = New-Catlet -Config $config -Variables @{ userName = "Eve" }

      $updateConfig = $config.Replace('startup: 1024', 'startup: 2048')

      Update-Catlet -Id $catlet.Id -Config $updateConfig

      $vm = Get-VM -Name $catletName
      $vm.MemoryStartup | Should -BeExactly 2048MB
    }

    It "Disables previously enabled capabilities" {
      $config = @"
name: $catletName
project: $($project.Name)
capabilities:
- name: dynamic_memory
- name: nested_virtualization
- name: secure_boot
  details:
  - template:MicrosoftUEFICertificateAuthority
- name: tpm
"@

      $catlet = New-Catlet -Config $config

      $vm = Get-VM -Name $catletName
      $vm.DynamicMemoryEnabled | Should -BeTrue

      $vmFirmware = Get-VMFirmware -VMName $catletName
      $vmFirmware.SecureBoot | Should -Be 'On'

      $vmSecurity = Get-VMSecurity -VMName $catletName
      $vmSecurity.TpmEnabled | Should -BeTrue

      $vmProcessor = Get-VMProcessor -VMName $catletName
      $vmProcessor.ExposeVirtualizationExtensions | Should -BeTrue

      $updateConfig = @"
name: $catletName
project: $($project.Name)
"@
      Update-Catlet -Id $catlet.Id -Config $updateConfig

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
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
cpu:
  count: 2
drives:
- name: sda
  size: 100
"@

      $catlet = New-Catlet -Config $config
      Checkpoint-VM -Name $catlet.Name

      $updatedConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
cpu:
  count: 3
drives:
- name: sda
  size: 150
"@
      Update-Catlet -Id $catlet.Id -Config $updatedConfig

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
