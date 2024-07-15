#Requires -Version 7.4
#Requires -Module Pester
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
}

Describe "Catlets" {

  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
  }
  
  Context "New-Catlet" {

    It "Creates properly configured catlet without parent" {
      $config = @'
cpu:
  count: 3
memory:
  startup: 1024
  minimum: 512
  maximum: 2048
drives:
- name: sda
  size: 50
networks:
- name: default
  adapter_name: public
network_adapters:
- name: public
'@

      New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt

      $vm = Get-VM -Name $catletName

      $vm.ProcessorCount | Should -BeExactly 3

      $vm.MemoryStartup | Should -BeExactly (1024 * 1024 * 1024)
      $vm.MemoryMinimum | Should -BeExactly (512 * 1024 * 1024)
      # $vm.MemoryMaximum | Should -BeExactly (2048*1024*1024)

      $vm.HardDrives | Should -HaveCount 1
      $vhd = Get-VHD -Path $vm.HardDrives[0].Path
      $vhd.Size | Should -BeExactly (50 * 1024 * 1024 * 1024)

      $vm.NetworkAdapters | Should -HaveCount 1
      $vm.NetworkAdapters[0].Name | Should -BeExactly 'public'
      $vm.NetworkAdapters[0].SwitchName | Should -BeExactly 'eryph_overlay'
    }

    It "Creates catlet when only the parent is provided" {
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Parent 'dbosoft/e2etests-os/base' -SkipVariablesPrompt

      $vm = Get-VM -Name $catletName

      $configFromServer = Get-Catlet -Id $catlet.Id -Config

      $configFromServer | Should -Not -BeNullOrEmpty
    }

    It "Creates catlet with parameterized fodder" {
      $config = @'
parent: dbosoft/e2etests-os/base
variables:
- name: userName
  value: Eve E2E
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
'@
                    
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be "Hello Eve E2E!"

      $vm = Get-VM -Name $catletName
      $vmIdResponse = Invoke-SSHCommand -Command "cat /hyperv-vm-id.txt" -SSHSession $sshSession
      $vmIdResponse.Output | Should -Be $vm.Id
    }

    It "Creates catlet with parameterized gene fodder" {
      $config = @'
parent: dbosoft/e2etests-os/base
fodder: 
- source: gene:dbosoft/e2etests-fodder:greet-user
  variables:
  - name: userName
    value: Andy Astronaut
'@
                  
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be "Hello Andy Astronaut!"

      $configFromServer = Get-Catlet -Id $catlet.Id -Config
      $configFromServer | Should -BeLike "*parent: dbosoft/e2etests-os/base-0.1*"
      $configFromServer | Should -BeLike "*source: gene:dbosoft/e2etests-fodder/0.1:greet-user*"
    }


    It "Creates catlet with parameterized fodder in parent" {
      $config = @'
parent: dbosoft/e2etests-os/greet-mars-0.2

variables:
- name: userName
  value: Eve E2E

fodder:
- source: gene:dbosoft/e2etests-fodder/0.2:greet-user
  variables:
  - name: userName
    value: Andy Astronaut
- source: gene:dbosoft/e2etests-fodder/0.2:greet-default-users
  remove: true
'@
                    
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be @(
        "Hello inhabitents of planet Mars!"
        "Hello Andy Astronaut!"
      )
    }

    It "Fails when parent and child use different tags of the same gene set" {
      $config = @'
parent: dbosoft/e2etests-os/greet-mars-0.2

variables:
- name: userName
  value: Eve E2E

fodder:
- source: gene:dbosoft/e2etests-fodder/0.1:greet-user
  variables:
  - name: userName
    value: Andy Astronaut
'@
                    
      { New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt } |
        Should -Throw "*The gene set 'dbosoft/e2etests-fodder' is used with different tags ('0.2', '0.1')*"
    }
  }

  Describe "Update-Catlet" {
    It "Updates catlet when parent is not changed" {
      $config = @'
parent: dbosoft/e2etests-os/base
cpu:
  count: 2
'@

      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt

      $updatedConfig = @'
parent: dbosoft/e2etests-os/base
cpu:
  count: 3
'@
      Update-Catlet -Id $catlet.Id -Config $updatedConfig -SkipVariablesPrompt

      $vm = Get-VM -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 3
    }
  }

  AfterEach {
    #Remove-EryphProject -Id $project.Id
  }
}
