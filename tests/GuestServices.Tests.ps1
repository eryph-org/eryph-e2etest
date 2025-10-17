#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "GuestServices" {

  # The tests for the guest services use a local copy of the ISO to install
  # the guest services. This means that we are not testing the actual genes
  # for installing the guest services. On the other hand, it allows us to
  # select the version of the guest services when running the tests.

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
drives:
- name: egsiso
  source: $($EryphSettings.EgsIsoPath)
  type: dvd
fodder:
- source: gene:dbosoft/e2etests-egs:linux-install
  variables:
  - name: sshPublicKey
    value: '$egsSshKey'
"@

    $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
    Start-Catlet -Id $catlet.Id -Force
    
    egs-tool update-ssh-config

    Wait-Assert -Timeout (New-TimeSpan -Minutes 10) {
      egs-tool get-status $catlet.VmId | Should -Be 'available'
      $data = egs-tool get-data --json $catlet.VmId | ConvertFrom-Json -AsHashtable
      $data.guest.'eryph:guest-services:version' | Should -Be $EryphSettings.EgsVersion
    }

    $result = &ssh -q "$($catlet.Name).$($project.Name).eryph.alt" 'hostname'
    $result | Should -Be $catletName
  }

  It "Can connect to a Windows guest" {
    $config = @"
name: default
parent: dbosoft/winsrv2022-standard/starter
drives:
- name: egsiso
  source: $($EryphSettings.EgsIsoPath)
  type: dvd
fodder:
- source: gene:dbosoft/e2etests-egs:win-install
  variables:
  - name: sshPublicKey
    value: '$egsSshKey'
"@
    $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
    Start-Catlet -Id $catlet.Id -Force
    
    egs-tool update-ssh-config

    Wait-Assert -Timeout (New-TimeSpan -Minutes 10) {
      egs-tool get-status $catlet.VmId | Should -Be 'available'
      $data = egs-tool get-data --json $catlet.VmId | ConvertFrom-Json -AsHashtable
      $data.guest.'eryph:guest-services:version' | Should -Be $EryphSettings.EgsVersion
    }

    $result = &ssh -q "$($catlet.Name).$($project.Name).eryph.alt" 'hostname'
    $result | Should -Be $catletName
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
