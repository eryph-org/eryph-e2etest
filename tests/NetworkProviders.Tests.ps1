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
    # $loopbackAdapterName = 'eryph-e2e-loopback'
    # $loopbackAdapter = Get-NetAdapter -Name $loopbackAdapterName -ErrorAction SilentlyContinue
    # if (-not $loopbackAdapter) {
    #   throw "Loopback adapter $loopbackAdapterName not found. The end-to-end tests require a loopback adapter."
    # }
    # $loopbackAdapterIpAddress = "172.22.42.5"
    # $loopbackAdapterIp = Get-NetIPAddress -IPAddress $loopbackAdapterIpAddress -InterfaceAlias $loopbackAdapterName -ErrorAction SilentlyContinue
    # if (-not $loopbackAdapterIp) {
    #   New-NetIPAddress -InterfaceAlias $loopbackAdapterName -IPAddress $loopbackAdapterIpAddress -PrefixLength 24
    # }

    $flatSwitchName = 'eryph-e2e-flat-switch'
    $flatSwitch = Get-VMSwitch -Name $flatSwitchName -ErrorAction SilentlyContinue
    if (-not $flatSwitch) {
      $flatSwitch = New-VMSwitch -Name $flatSwitchName -SwitchType Internal
    }

    New-NetIPAddress -InterfaceAlias "vEthernet ($flatSwitchName)" -IPAddress 172.22.42.42 -PrefixLength 24
    
    $providersConfigBackup = eryph-zero.exe networks get
    
    $providersConfig = @"
network_providers:
- name: default
  type: nat_overlay
  bridge_name: br-nat
  subnets: 
  - name: default
    network: 10.249.248.0/22
    gateway: 10.249.248.1
    ip_pools:
    - name: default
      first_ip: 10.249.248.10
      next_ip: 10.249.248.10
      last_ip: 10.249.251.241
# - name: test-overlay
#   type: overlay
#   bridge_name: br-pif
#   adapters:
#   - eryph-e2e-loopback
#   subnets: 
#   - name: default
#     network: 172.22.42.0/24
#     gateway: 172.22.42.1
#     ip_pools:
#     - name: default
#       first_ip: 172.22.42.10
#       next_ip: 172.22.42.10
#       last_ip: 172.22.42.100
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
- name: second
  provider: default
  address: 10.0.101.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.101.8
      last_ip: 10.0.101.15
      next_ip: 10.0.101.12
# - name: test-overlay-network
#   provider: test-overlay
#   address: 10.0.101.0/28
#   subnets:
#   - name: default
#     ip_pools:
#     - name: default
#       first_ip: 10.0.101.8
#       last_ip: 10.0.101.15
#       next_ip: 10.0.101.12
- name: test-flat-network
  provider: test-flat
'@
      Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force
    }

    It "Changes network provider of catlet from overlay to flat" {
      $catletConfig = @'
name: default
parent: dbosoft/e2etests-os/base
cpu: 1
memory: 512
networks:
- name: default
'@
  
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $catletConfig

      $updatedCatletConfig = @'
name: default
parent: dbosoft/e2etests-os/base
cpu: 1
memory: 512
networks:
- name: test-flat-network
'@

      Update-Catlet -Id $catlet.Id -Config $updatedCatletConfig
    }

    It "Connects catlet to all networks" {
      $catletConfig = @'
name: default
parent: dbosoft/e2etests-os/base
cpu: 1
memory: 512
network_adapters:
- name: eth0
# - name: eth1
- name: eth2
networks:
- name: default
  adapter_name: eth0
# - name: test-overlay-network
#   adapter_name: eth1
- name: test-flat-network
  adapter_name: eth2
fodder:
- name: set-static-ip
  type: cloud-config
  content:
    network:
      config: disabled
    write_files:
    - path: /etc/systemd/network/10-static-eth2.network
      content: |
        [Match]
        Name=eth2
        [Network]
        Address=172.22.43.43/24
        Gateway=172.22.43.1
        DNS=8.8.8.8
'@
  
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $catletConfig
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
    }
  
    It "Connects catlet to flat network after the catlet has been started" {
      # Eryph does not support static IP assignments yet. Hence, we cannot
      # configure the flat network before the first boot. The catlet would
      # hand for an extended period of time waiting for DHCP response which
      # will not arrive as the flat network does not have a DHCP server.

      $catletConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
network_adapters:
- name: eth0
networks:
- name: default
  adapter_name: eth0
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
- name: default
  adapter_name: eth0
- name: test-flat-network
  adapter_name: eth1
"@

      # Disconnect the SSH session before updating the catlet's network configuration.
      # The update will shortly disconnect the netwwork which woul cause the SSH session
      # to fail with an error.
      # TODO investigate if it is expected that the network disconnects
      Remove-SSHSession $sshSession
      
      Update-Catlet -Id $catlet.Id -Config $updatedCatletConfig

      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      # TODO this currently fails as the network breaks after the catlet update
      $sshResponse = Invoke-SSHCommand -Command 'sudo ip link set eth1 up' -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      $sshResponse = Invoke-SSHCommand -Command 'sudo ip addr add 172.22.42.43/24 dev eth1' -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      $flatSshSession = Connect-Ssh -ComputerName '172.22.42.43'
      $flatSshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $flatSshSession
      $flatSshResponse.Output | Should -Be $catletName

      # TODO Verify that get-catlet/get-catletip returns correct reported IPs for flat networks
    }

  }



  AfterEach {
    #Remove-EryphProject -Id $project.Id -Force
  }

  AfterAll {
    #$providersConfigBackup | eryph-zero.exe networks import
    #Remove-VMSwitch -Name $flatSwitchName -Force
  }
}
