#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "GuestServices" {

  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName

    $egsSshKey = egs-tool get-ssh-key
    if ($LASTEXITCODE -ne 0) {
      throw 'Could not get SSH key for guest services. Have you initialized the guest services?'
    }
  }

  It "Can connect to a Linux guest" {
    $config = @"
name: default
parent: dbosoft/e2etests-os/base
fodder:
- source: gene:dbosoft/powershell/1.0:linux-install
- source: gene:dbosoft/guest-services/next:linux-install
  variables:
  - name: sshPublicKey
    value: '$egsSshKey'
"@
    $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
    Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit

    egs-tool update-ssh-config

    $session = New-PSSession -HostName "eryph-$catletName"

    $hostName = Invoke-Command -Session $session -ScriptBlock { [System.Net.Dns]::GetHostName() }
    $hostName | Should -Be $catletName
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
