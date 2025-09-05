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

  Context "Networking" {

    It "Connects two catlets in the same project" {
      # This test uses a special base catlet which is still based on Ubuntu 22.04.
      # The DNS resolution for local hostnames is broken with Ubuntu 24.04. OVN
      # provides DNS by intercepting the DNS requests for hosts which are part
      # of an OVN network. This no longer works as Ubuntu 24.04 uses edns0 which
      # is not supported by OVN.

      $firstConfig = @'
parent: dbosoft/e2etests-os22/base
hostname: first
'@
      $secondConfig = @'
parent: dbosoft/e2etests-os22/base
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
    
    It "Connects new network adapter while catlet is running" {
      $networkConfig = @'
version: 1.0
networks:
- name: default
  address: 10.0.0.0/24
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.0.100
      last_ip: 10.0.0.240
- name: second-network
  address: 10.0.1.0/24
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.1.100
      last_ip: 10.0.1.240
'@
      Set-VNetwork -ProjectName $project.Name -Config $networkConfig -Force

      $config = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
networks:
- name: default
"@

      $catlet = New-Catlet -Config $config
      $sshSession = Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit

      $updatedConfig = @"
name: $catletName
project: $($project.Name)
parent: dbosoft/e2etests-os/base
networks:
- name: default
- name: second-network
"@
      Update-Catlet -Id $catlet.Id -Config $updatedConfig
      
      $sshResponse = Invoke-SSHCommand -Command 'sudo dhcpcd --oneshot --debug --timeout 60 --waitip=4 eth1 2>&1' -SSHSession $sshSession
      $sshResponse.ExitStatus | Should -Be 0
      $sshResponse.Output -join "`n" | Should -BeLike "*adding IP address 10.0.1.100/24*"

      $sshResponse = Invoke-SSHCommand -Command 'ip address show' -SSHSession $sshSession
      $sshResponse.ExitStatus | Should -Be 0
      $sshResponse.Output | Assert-Any { $_ -ilike '*inet 10.0.0.100/24*' }
      $sshResponse.Output | Assert-Any { $_ -ilike '*inet 10.0.1.100/24*' }

      # We cannot connect via SSH to the second IP address as the NAT is
      # broken for the second network. Linux uses the weak host model for
      # IP which means that a response is not necessarily
      # sent on the same interface as the request was received.
      # At some point, this test should use multiple network providers.
    }
    
  }
  
  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
