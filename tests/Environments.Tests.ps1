#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
#Requires -Module powershell-yaml
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "Environments" {
  BeforeAll {
    $secondEnvironmentName = "e2tests-2"
    
    $agentSettingsBackup = eryph-zero.exe agentsettings get

    $agentSettings = ConvertFrom-Yaml ($agentSettingsBackup -join "`n")
    $environments = $agentSettings['environments'] ?? @()
    $environment = ($environments | Where-Object { $_.name -eq $secondEnvironmentName } | Select-Object -First 1)
    if (-not $environment) {
      $environment = @{
        name = $secondEnvironmentName
      }
      $environments += $environment
    }
    $environment.defaults = @{
      vms = $EryphSettings.SecondVmStorePath
      volumes = $EryphSettings.SecondDiskStorePath
    }
    $agentSettings.environments = $environments
    $yaml = ConvertTo-Yaml $agentSettings
    $yaml | eryph-zero.exe agentsettings import --non-interactive
  }

  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
  }

  Describe "Project with different network per environment" {

    BeforeEach {
      $projectNetworksConfig = @"
version: 1.0
project: default
networks:
- name: default
  address: 10.0.100.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.100.8
      last_ip: 10.0.100.15
      next_ip: 10.0.100.12
- name: default
  environment: $secondEnvironmentName
  address: 10.0.101.0/28
  subnets:
  - name: default
    ip_pools:
    - name: default
      first_ip: 10.0.101.8
      last_ip: 10.0.101.15
      next_ip: 10.0.101.12
"@
      Set-VNetwork -ProjectName $project.Name -Config $projectNetworksConfig -Force
    }

    It "Routes east-west traffic between environment networks of project" {
      $firstCatletConfig =  @"
parent: dbosoft/e2etests-os/base
networks:
- name: default
"@
      $firstCatlet = New-Catlet -Config $firstCatletConfig -Name "$($catletName)-1" -ProjectName $project.Name
      
      $secondCatletConfig =  @"
parent: dbosoft/e2etests-os/base
environment: $secondEnvironmentName
networks:
- name: default
"@
      $secondCatlet = New-Catlet -Config $secondCatletConfig -Name "$($catletName)-2" -ProjectName $project.Name

      # Start all catlets
      Start-Catlet -Id $firstCatlet.Id -Force
      Start-Catlet -Id $secondCatlet.Id -Force

      # Check that all catlets have started and completed the cloud-init initialization
      $sshSession = Connect-Catlet -CatletId $firstCatlet.Id -WaitForCloudInit
      Remove-SSHSession -SSHSession $sshSession
      
      $sshSession = Connect-Catlet -CatletId $secondCatlet.Id -WaitForCloudInit
      Remove-SSHSession -SSHSession $sshSession

      # Get the IP addresses of the catlets
      $firstCatletIps = Get-CatletIp -Id $firstCatlet.Id -Internal
      $firstCatletIps | Should -HaveCount 1
      $firstCatletIps[0].IpAddress | Should -Be '10.0.100.12'
      
      $secondCatletIps = Get-CatletIp -Id $secondCatlet.Id -Internal
      $secondCatletIps | Should -HaveCount 1
      $secondCatletIps[0].IpAddress | Should -Be '10.0.101.12'

      # Check the connectivity between the catlets
      $sshSession = Connect-Catlet -CatletId $firstCatlet.Id -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-1"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($secondCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0

      Remove-SSHSession -SSHSession $sshSession

      $sshSession = Connect-Catlet -CatletId $secondCatlet.Id -WaitForCloudInit
      $sshResponse = Invoke-SSHCommand -Command 'hostname' -SSHSession $sshSession
      $sshResponse.Output | Should -Be "$($catletName)-2"
      $sshResponse = Invoke-SSHCommand -Command "ping -c 1 -W 1 $($firstCatletIps[0].IpAddress)" -SSHSession $sshSession
      $sshResponse.ExitStatus  | Should -Be 0
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }

  AfterAll {
    $agentSettingsBackup | eryph-zero.exe agentsettings import --non-interactive
  }
}
