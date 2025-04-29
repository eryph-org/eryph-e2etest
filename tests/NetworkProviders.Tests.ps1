#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "NetworkProviders" {
  BeforeAll {
    $flatSwitchName = 'eryph-e2etests-flat-switch'
    $flatSwitch = Get-VMSwitch -Name $flatSwitchName -ErrorAction SilentlyContinue
    if (-not $flatSwitch) {
      $flatSwitch = New-VMSwitch -Name $flatSwitchName -SwitchType Internal
    }

    $flatSwitchIpAddress = Get-NetIPAddress -InterfaceAlias "vEthernet (eryph-e2e-flat-switch)" -IPAddress 172.22.42.42 -ErrorAction SilentlyContinue
    if (-not $flatSwitchIpAddress) {
      New-NetIPAddress -InterfaceAlias "vEthernet ($flatSwitchName)" -IPAddress 172.22.42.42 -PrefixLength 24
    }
    
    $providersConfigBackup = eryph-zero.exe networks get
    
    # The provider config is subject to certain limitations:
    # - The IP range of the default provider should match the range
    #   in the default configuration. Otherwise, developers might run
    #   into issues when running the tests locally. Eryph would block
    #   changes to the IP range if any IPs which are in use are removed
    #   from the range.
    # - NAT overlay providers only support a single subnet which must
    #   be named 'default'.
    $providersConfig = @"
network_providers:
- name: default
  type: nat_overlay
  bridge_name: br-nat
  subnets: 
  - name: default
    network: 10.249.248.0/21
    gateway: 10.249.248.1
    ip_pools:
    - name: default
      first_ip: 10.249.248.10
      next_ip: 10.249.248.10
      last_ip: 10.249.251.241
    - name: second-provider-pool
      first_ip: 10.249.254.10
      next_ip: 10.249.254.10
      last_ip: 10.249.254.241
- name: second-nat-provider
  type: nat_overlay
  bridge_name: br-second-nat
  subnets: 
  - name: default
    network: 10.250.0.0/24
    gateway: 10.250.0.1
    ip_pools:
    - name: default
      first_ip: 10.250.0.10
      next_ip: 10.250.0.10
      last_ip: 10.250.0.240
- name: flat-provider
  type: flat
  switch_name: $flatSwitchName
"@
    $providersConfig | eryph-zero.exe networks import --non-interactive
  }

  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
  }

  It "Can change provider of existing network" {
    $projectNetworksConfig = @'
version: 1.0
project: default
networks:
- name: default
  provider: default
  address: 10.0.100.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.100.8
      last_ip: 10.0.100.15
      next_ip: 10.0.100.12
'@
    
    Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force

    $networks = Get-VNetwork -ProjectName $project.Name
    $networks | Should -HaveCount 1
    $networks[0].Name | Should -Be 'default'
    $networks[0].Environment | Should -Be 'default'
    $networks[0].ProviderName | Should -Be 'default'
    $networks[0].IpNetwork | Should -Be '10.0.100.0/28'

    $updatedProjectNetworksConfig = @'
version: 1.0
project: default
networks:
- name: default
  provider: second-nat-provider
  address: 10.0.100.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.100.8
      last_ip: 10.0.100.15
'@

    Set-VNetwork -ProjectName $project.Name -Config $updatedProjectNetworksConfig -Force
    
    $updatedNetworks = Get-VNetwork -ProjectName $project.Name
    $updatedNetworks | Should -HaveCount 1
    $updatedNetworks[0].Name | Should -Be 'default'
    $updatedNetworks[0].Environment | Should -Be 'default'
    $updatedNetworks[0].ProviderName | Should -Be 'second-nat-provider'
    $updatedNetworks[0].IpNetwork | Should -Be '10.0.100.0/28'
  }

  Describe "Project with multiple networks using different overlay providers" {
    BeforeEach {
      $projectNetworksConfig = @'
version: 1.0
project: default
networks:
- name: default
  provider:
    name: default
    subnet: default
    ip_pool: default
  address: 10.0.100.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.100.8
      last_ip: 10.0.100.15
      next_ip: 10.0.100.12
- name: second
  provider:
    name: second-nat-provider
    subnet: default
    ip_pool: default
  address: 10.0.101.0/28
  subnets:
  - name: second-subnet
    ip_pools:
    - name: second-pool
      first_ip: 10.0.101.8
      last_ip: 10.0.101.15
      next_ip: 10.0.101.12
- name: flat-network
  provider: flat-provider
'@
      Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force
    }

    It "Connects two catlets to each other and the outside world" {
      $catletConfig = @"
parent: dbosoft/e2etests-os/base
networks:
- name: default
- name: second
  subnet_v4:
    name: second-subnet
    ip_pool: second-pool
"@

      $firstCatlet = New-Catlet -Config $catletConfig -Name "$($catletName)-1" -ProjectName $project.Name
      $secondCatlet = New-Catlet -Config $catletConfig -Name "$($catletName)-2" -ProjectName $project.Name

      Start-Catlet -Id $firstCatlet.Id -Force
      Start-Catlet -Id $secondCatlet.Id -Force

      $firstCatletIps = Get-CatletIp -Id $firstCatlet.Id
      $firstCatletIps | Should -HaveCount 2

      $secondCatletIps = Get-CatletIp -Id $secondCatlet.Id -Internal
      $secondCatletIps | Should -HaveCount 2

      $sshSession = Connect-CatletIp -IpAddress $firstCatletIps[0].IpAddress -WaitForCloudInit -Timeout (New-TimeSpan -Minutes 2)
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-1"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[1].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      Remove-SSHSession -SSHSession $sshSession

      $sshSession = Connect-CatletIp -IpAddress $firstCatletIps[1].IpAddress -WaitForCloudInit -Timeout (New-TimeSpan -Minutes 2)
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-1"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[1].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
    }
  }

  Describe "Project with overlay network and flat network" {
    BeforeEach {
      $projectNetworksConfig = @'
version: 1.0
project: default
networks:
- name: second-network
  provider:
    name: default
    subnet: default
    ip_pool: second-provider-pool
  address: 10.0.101.0/28
  subnets:
  - name: second-subnet
    ip_pools:
    - name: second-pool
      first_ip: 10.0.101.8
      last_ip: 10.0.101.15
      next_ip: 10.0.101.12
- name: flat-network
  provider: flat-provider
'@
      
      Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force
    }

    It "Returns the correct network configuration" {
      $networks = Get-VNetwork -ProjectName $project.Name
      $networks | Should -HaveCount 2

      $overlayNetworks = $networks | Where-Object { $_.Name -eq 'second-network' }	
      $overlayNetworks | Should -HaveCount 1
      $overlayNetworks[0].Name | Should -Be 'second-network'
      $overlayNetworks[0].Environment | Should -Be 'default'
      $overlayNetworks[0].ProviderName | Should -Be 'default'
      $overlayNetworks[0].IpNetwork | Should -Be '10.0.101.0/28'

      $flatNetworks = $networks | Where-Object { $_.Name -eq 'flat-network' }	
      $flatNetworks | Should -HaveCount 1
      $flatNetworks[0].Name | Should -Be 'flat-network'
      $flatNetworks[0].Environment | Should -Be 'default'
      $flatNetworks[0].ProviderName | Should -Be 'flat-provider'
      $flatNetworks[0].IpNetwork | Should -BeNullOrEmpty
    }
  
    It "Connects catlet to flat network after the catlet has been started" {
      # Eryph does not support static IP assignments yet. Hence, we cannot
      # configure the flat network before the first boot. The catlet would
      # hang for an extended period of time while waiting for a DHCP response
      # which will not arrive as the flat network does not have a DHCP server.

      $catletConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
network_adapters:
- name: eth0
networks:
- name: second-network
  adapter_name: eth0
  subnet_v4:
    name: second-subnet
    ip_pool: second-pool
"@
  
      $catlet = New-Catlet -Config $catletConfig
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
  
      $updatedCatletConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
network_adapters:
- name: eth0
- name: eth1
networks:
- name: second-network
  adapter_name: eth0
  subnet_v4:
    name: second-subnet
    ip_pool: second-pool
- name: flat-network
  adapter_name: eth1
"@

      Update-Catlet -Id $catlet.Id -Config $updatedCatletConfig

      $networkAdapters = Get-VMNetworkAdapter -VMName $catletName
      $networkAdapters | Should -HaveCount 2
      $networkAdapters | Assert-All { $_.MacAddressSpoofing -eq $false }

      $sshResponse = Invoke-SSHCommand -Command 'sudo ip link set eth1 up' -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      $sshResponse = Invoke-SSHCommand -Command 'sudo ip addr add 172.22.42.43/24 dev eth1' -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      $flatSshSession = Connect-CatletIp -IpAddress '172.22.42.43'
      $flatSshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $flatSshSession
      $flatSshResponse.Output | Should -Be $catletName

      $catletIps = Get-CatletIp -Id $catlet.Id
      # We only expect 1 IP address as flat networks do not have floating IPs.
      $catletIps | Should -HaveCount 1
      ([System.Net.IPNetwork]'10.249.254.0/24').Contains($catletIps[0].IpAddress) | Should -BeTrue

      Wait-Assert {
        $internalCatletIps = Get-CatletIp -Id $catlet.Id -Internal
        $internalCatletIps | Should -HaveCount 2
        $internalCatletIps | Assert-Any { $_.IpAddress -eq '10.0.101.12' }
        $internalCatletIps | Assert-Any { $_.IpAddress -eq '172.22.42.43' }
      }
    }

    It "Enables MAC address spoofing on flat networks" {
      $catletConfig = @"
parent: dbosoft/e2etests-os/base
network_adapters:
- name: eth0
  mac_address_spoofing: true
networks:
- name: flat-network
  adapter_name: eth0
"@
        
      $catlet = New-Catlet -Config $catletConfig -Name $catletName -ProjectName $project.Name

      $networkAdapters = Get-VMNetworkAdapter -VMName $catletName
      $networkAdapters | Should -HaveCount 1
      $networkAdapters[0].Name | Should -Be 'eth0'
      $networkAdapters[0].MacAddressSpoofing | Should -Be $true
    }
  }

  Describe "Project with with mutliple providers and multiple networks per provider" {
    BeforeEach {
      $projectNetworksConfig = @'
version: 1.0
project: default
networks:
- name: default
  provider:
    name: default
    subnet: default
    ip_pool: default
  address: 10.0.100.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.100.8
      last_ip: 10.0.100.15
      next_ip: 10.0.100.12
- name: second
  provider:
    name: default
    subnet: default
    ip_pool: default
  address: 10.0.101.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.101.8
      last_ip: 10.0.101.15
      next_ip: 10.0.101.12
- name: third
  provider:
    name: second-nat-provider
    subnet: default
    ip_pool: default
  address: 10.0.102.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.102.8
      last_ip: 10.0.102.15
      next_ip: 10.0.102.12
'@
      Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force
    }

    It "Routes east-west traffic between project networks" {
      $firstCatletConfig =  @"
parent: dbosoft/e2etests-os/base
networks:
- name: default
"@
      $firstCatlet = New-Catlet -Config $firstCatletConfig -Name "$($catletName)-1" -ProjectName $project.Name
      
      $secondCatletConfig =  @"
parent: dbosoft/e2etests-os/base
networks:
- name: second
"@
      $secondCatlet = New-Catlet -Config $secondCatletConfig -Name "$($catletName)-2" -ProjectName $project.Name

      $thirdCatletConfig =  @"
parent: dbosoft/e2etests-os/base
networks:
- name: third
"@
      $thirdCatlet = New-Catlet -Config $thirdCatletConfig -Name "$($catletName)-3" -ProjectName $project.Name

      # Start all catlets
      Start-Catlet -Id $firstCatlet.Id -Force
      Start-Catlet -Id $secondCatlet.Id -Force
      Start-Catlet -Id $thirdCatlet.Id -Force

      # Check that all catlets have started and completed the cloud-init initialization
      $sshSession = Connect-Catlet -CatletId $firstCatlet.Id -WaitForCloudInit
      Remove-SSHSession -SSHSession $sshSession
      
      $sshSession = Connect-Catlet -CatletId $secondCatlet.Id -WaitForCloudInit
      Remove-SSHSession -SSHSession $sshSession
      
      $sshSession = Connect-Catlet -CatletId $thirdCatlet.Id -WaitForCloudInit
      Remove-SSHSession -SSHSession $sshSession

      # Get the IP addresses of the catlets
      $firstCatletIps = Get-CatletIp -Id $firstCatlet.Id -Internal
      $firstCatletIps | Should -HaveCount 1
      $firstCatletIps[0].IpAddress | Should -Be '10.0.100.12'
      
      $secondCatletIps = Get-CatletIp -Id $secondCatlet.Id -Internal
      $secondCatletIps | Should -HaveCount 1
      $secondCatletIps[0].IpAddress | Should -Be '10.0.101.12'

      $thirdCatletIps = Get-CatletIp -Id $thirdCatlet.Id -Internal
      $thirdCatletIps | Should -HaveCount 1
      $thirdCatletIps[0].IpAddress | Should -Be '10.0.102.12'

      # Check the connectivity between the catlets
      $sshSession = Connect-Catlet -CatletId $firstCatlet.Id -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-1"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($thirdCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      Remove-SSHSession -SSHSession $sshSession

      $sshSession = Connect-Catlet -CatletId $secondCatlet.Id -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-2"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($firstCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($thirdCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      Remove-SSHSession -SSHSession $sshSession

      $sshSession = Connect-Catlet -CatletId $thirdCatlet.Id -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-3"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($firstCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }

  AfterAll {
    $providersConfigBackup | eryph-zero.exe networks import --non-interactive
    Remove-VMSwitch -Name $flatSwitchName -Force
  }
}
