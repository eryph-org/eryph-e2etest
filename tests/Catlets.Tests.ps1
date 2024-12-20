#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "Catlets" {

  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
  }
  
  Context "New-Catlet" {

    It "Creates catlet without config" {
      $config = @'
name: catlet
'@
      New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $vm = Get-VM -Name $catletName

      $vm.DynamicMemoryEnabled | Should -BeTrue
      $vm.MemoryStartup | Should -BeExactly 1024MB
      $vm.MemoryMinimum | Should -BeExactly 512MB
      $vm.MemoryMaximum | Should -BeExactly 1TB
    }

    It "Creates properly configured catlet without parent" {
      $config = @'
cpu:
  count: 3
memory:
  startup: 1024
  minimum: 256
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

      New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $vm = Get-VM -Name $catletName

      $vm.ProcessorCount | Should -BeExactly 3

      $vm.DynamicMemoryEnabled | Should -BeTrue
      $vm.MemoryStartup | Should -BeExactly 1024MB
      $vm.MemoryMinimum | Should -BeExactly 256MB
      $vm.MemoryMaximum | Should -BeExactly 2048MB

      $vm.HardDrives | Should -HaveCount 1
      $vm.HardDrives[0].Path | Should -BeLike "*\p_$($project.Name)\*\sda.vhdx"
      $vhd = Get-VHD -Path $vm.HardDrives[0].Path
      $vhd.Size | Should -BeExactly 50GB

      $vm.NetworkAdapters | Should -HaveCount 1
      $vm.NetworkAdapters[0].Name | Should -BeExactly 'public'
      $vm.NetworkAdapters[0].SwitchName | Should -BeExactly 'eryph_overlay'
    }

    It "Creates catlet without dynamic memory" {
      $config = @'
memory:
  startup: 1024
capabilities:
- name: dynamic_memory
  details: ['disabled']
'@

      New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $vm = Get-VM -Name $catletName

      $vm.DynamicMemoryEnabled | Should -BeFalse
      $vm.MemoryStartup | Should -BeExactly 1024MB
    }

    It "Creates catlet when only the parent is provided" {
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Parent 'dbosoft/e2etests-os/base'

      $configFromServer = Get-Catlet -Id $catlet.Id -Config

      $configFromServer | Should -Not -BeNullOrEmpty
    }

    It "Creates catlet with shorthand configuration" {
      $config = @'
name: default
parent: dbosoft/e2etests-os/base
cpu: 1
memory: 512
capabilities:
- nested_virtualization
fodder:
- name: add-file
  type: cloud-config
  content:
    write_files:
    - path: /cloud-init-test.txt
      content: |
        cloud-init says hello!
'@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $vm = Get-VM -Name $catletName
      $vm.ProcessorCount | Should -BeExactly 1
      $vm.MemoryStartup | Should -BeExactly 512MB

      $vmProcessor = Get-VMProcessor -VM $vm
      $vmProcessor.ExposeVirtualizationExtensions | Should -BeTrue

      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /cloud-init-test.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be "cloud-init says hello!"
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
                    
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
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
                  
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be "Hello Andy Astronaut!"

      $configFromServer = Get-Catlet -Id $catlet.Id -Config
      $configFromServer | Should -BeLike "*parent: dbosoft/e2etests-os/base-0.1*"
      $configFromServer | Should -BeLike "*source: gene:dbosoft/e2etests-fodder/0.1:greet-user*"
    }

    It "Creates catlet with many fodder genes" {
      $config = @'
parent: dbosoft/e2etests-os/base
fodder: 
- source: gene:dbosoft/e2etests-fodder:greet-default-users
- source: gene:dbosoft/e2etests-fodder:greet-user
  variables:
  - name: userName
    value: Andy Astronaut
- source: gene:dbosoft/e2etests-fodder:greet-planet
- source: gene:dbosoft/e2etests-fodder:greet-solar-system
- source: gene:dbosoft/e2etests-fodder:greet-architecture
'@
                  
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be @(
        'Hello Alice!'
        'Hello Bob!'
        'Hello Eve!'
        'Hello Andy Astronaut!'
        'Hello inhabitants of planet earth!'
        'Hello inhabitants of the sol system!'
        'Using architecture hyperv/amd64.'
      )
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
                    
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
      $helloWorldResponse.Output | Should -Be @(
        "Hello inhabitants of planet Mars!"
        "Hello Andy Astronaut!"
      )
    }

    It "Creates catlet based on ubuntu starter" -Tag "UbuntuStarter" {
      $config = @'
parent: dbosoft/ubuntu-22.04/starter
memory:
  startup: 1024
variables:
- name: password
  required: true
  secret: true
fodder: 
- source: gene:dbosoft/starter-food:linux-starter
  variables: 
  - name: password
    value: '{{ password }}'
'@

      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -Variables @{ password = "myPassword" }

      $sshSession = Connect-Catlet -CatletId $catlet.Id -Username admin -Password (ConvertTo-SecureString "myPassword" -AsPlainText -Force) -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command "cat /etc/lsb-release" -SSHSession $sshSession
      $sshResponse.Output | Assert-Any { $_ -ilike '*Ubuntu*' }
    }

    It "Creates catlet with separately created disk" {
      $diskName = "testdisk-$(Get-Date -Format 'yyyyMMddHHmmss')"
      $disk = New-CatletDisk -Name $diskName -Size 5 -ProjectName $project.Name -Location test

      $config = @"
parent: dbosoft/e2etests-os/base
drives:
- name: '$diskName'
  location: test
"@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $vm = Get-VM -Name $catletName

      $vm.HardDrives | Should -HaveCount 2
      $vm.HardDrives | Assert-Any { $_.Path -ieq $disk.Path }

      # Remove the catlet and check if the separately created disk is still there
      Remove-Catlet -Id $catlet.Id -Force

      $catletDisks = Get-CatletDisk -ProjectName $project.Name
      $catletDisks | Should -HaveCount 1
      $catletDisks | Assert-Any { $_.Id -eq $disk.Id }
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
                    
      { New-Catlet -Name $catletName -ProjectName $project.Name -Config $config } |
        Should -Throw "*The gene set 'dbosoft/e2etests-fodder' is used with different tags ('0.2', '0.1')*"
    }
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
  }

  Context "Networking" {
    It "Connects two catlets in the same project" {
      $firstConfig = @'
parent: dbosoft/e2etests-os/base
hostname: first
'@
      $secondConfig = @'
parent: dbosoft/e2etests-os/base
hostname: second
'@

      $firstCatlet = New-Catlet -Name "$catletName-first" -ProjectName $project.Name -Config $firstConfig
      Start-Catlet -Id $firstCatlet.Id -Force

      $secondCatlet = New-Catlet -Name "$catletName-second" -ProjectName $project.Name -Config $secondConfig
      Start-Catlet -Id $secondCatlet.Id -Force

      $firstSshSession = Connect-Catlet -CatletId $firstCatlet.Id -WaitForCloudInit
      $secondSshSession = Connect-Catlet -CatletId $secondCatlet.Id -WaitForCloudInit

      $firstSshResponse = Invoke-SSHCommand -Command 'ping -c 1 -W 1 second.home.arpa' -SSHSession $firstSshSession
      $firstSshResponse.ExitStatus  | Should -Be 0

      $secondSshResponse = Invoke-SSHCommand -Command 'ping -c 1 -W 1 first.home.arpa' -SSHSession $secondSshSession
      $secondSshResponse.ExitStatus  | Should -Be 0
    }

    It "Gracefully handles manually assigned IP address" {
      $catletConfig = @'
parent: dbosoft/e2etests-os/base
'@

      $catlet = New-Catlet -Name "$catletName" -ProjectName $project.Name -Config $catletConfig
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
    
      $sshResponse = Invoke-SSHCommand -Command 'sudo ip addr add 172.22.42.43/24 dev eth0' -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      Wait-Assert {
        $internalCatletIps = Get-CatletIp -Id $catlet.Id -Internal
        $internalCatletIps | Should -HaveCount 2
        $internalCatletIps | Assert-Any { $_.IpAddress -eq '10.0.0.100' }
        $internalCatletIps | Assert-Any { $_.IpAddress -eq '172.22.42.43' }
      }
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
