#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "VirtualNetworks" {
  BeforeAll {
    $flatSwitchName = 'eryph-e2e-flat-switch'
    $flatSwitch = Get-VMSwitch -Name $flatSwitchName -ErrorAction SilentlyContinue
    if (-not $flatSwitch) {
      $flatSwitch = New-VMSwitch -Name $flatSwitchName -SwitchType Internal
    }

    New-NetIPAddress -InterfaceAlias "vEthernet ($flatSwitchName)" -IPAddress 172.22.42.42 -PrefixLength 24
    
    $providersConfigBackup = eryph-zero.exe networks get
    
    # Keep the IP range of the default provider IP pool the same.
    # This way, developers can run the tests locally without running
    # issues with provider IPs which are in use.
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
- name: test-flat
  type: flat
  switch_name: $flatSwitchName
"@
    $providersConfig | eryph-zero.exe networks import --non-interactive
  }


  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
  }

  Describe "Project with multiple networks and providers" {
    BeforeEach {
      $projectNetworksConfig = @'
version: 1.0
project: default
networks:
# - name: default
#   provider: default
#   address: 10.0.100.0/28
#   subnets:
#   - name: default
#     ip_pools:
#     - name: default
#       first_ip: 10.0.100.8
#       last_ip: 10.0.100.15
#       next_ip: 10.0.100.12
- name: second
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
- name: test-flat-network
  provider: test-flat
'@
      Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force
    }

    It "Connects catlet to multiple virtual networks" {
      $catletConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
networks:
# - name: default
- name: second
  subnet_v4:
    name: second-subnet
    ip_pool: second-pool
"@
        
      $catlet = New-Catlet -Config $catletConfig
      Start-Catlet -Id $catlet.Id -Force
      
      $catletIps = Get-CatletIp -Id $catlet.Id
      # $catletIps | Should -HaveCount 2
      # $catletIps | Assert-Any { [System.Net.IPNetwork]::New("10.249.248.0", 22).Contains($_.IpAddress) }
      # $catletIps | Assert-Any { [System.Net.IPNetwork]::New("10.249.254.0", 24).Contains($_.IpAddress) }

      $firstSshSession = Connect-CatletIp -IpAddress $catletIps[0].IpAddress -WaitForCloudInit
      $firstSshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $firstSshSession
      $firstSshResponse.Output | Should -Be $catletName

      # $secondSshSession = Connect-CatletIp -IpAddress  $catletIps[0].IpAddress -WaitForCloudInit
      # $secondSshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $secondSshSession
      # $secondSshResponse.Output | Should -Be $catletName

      $catletIps = Get-CatletIp -Id $catlet.Id -Internal
      # $catletIps | Should -HaveCount 2
      # $catletIps | Assert-Any { $_.IpAddress -eq '10.0.100.12' }
      $catletIps | Assert-Any { $_.IpAddress -eq '10.0.101.12' } 
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
- name: second
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
- name: second
  adapter_name: eth0
  subnet_v4:
    name: second-subnet
    ip_pool: second-pool
- name: test-flat-network
  adapter_name: eth1
"@

      Update-Catlet -Id $catlet.Id -Config $updatedCatletConfig

      # $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
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
      $catletIps[0].IpAddress | Should -BeLike '10.249.254.*'

      
      $internalCatletIps = Get-CatletIp -Id $catlet.Id -Internal
      $internalCatletIps | Assert-Any { $_.IpAddress -eq '10.0.101.12' }
      # Currently, the inventory does not updated the reported IP addresses
      # quickly. Hence, we cannot assert the IP address of the flat network.
      # TODO Update this test after implementing https://github.com/eryph-org/eryph/issues/210
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }

  AfterAll {
    $providersConfigBackup | eryph-zero.exe networks import
    Remove-VMSwitch -Name $flatSwitchName -Force
  }
}
