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

    # Without the additional processing, Powershell introduces random
    # linebreaks as the string longer than the console is wide.
    $egsSshKey = (egs-tool get-ssh-key | Out-String -Stream) -join ''
    if ($LASTEXITCODE -ne 0) {
      throw 'Could not get SSH key for guest services. Have you initialized the guest services?'
    }
  }

  It "Can connect to a Linux guest" {
    $config = @"
name: default
parent: dbosoft/e2etests-os/base
fodder:
- source: gene:dbosoft/guest-services/next:linux-install
  variables:
  - name: downloadUrl
    value: 'https://artprodsu6weu.artifacts.visualstudio.com/A6eb69317-c955-4114-8558-b46413ccedea/59a3608a-9bed-4cb4-9467-6efaaa3cbef5/_apis/artifact/cGlwZWxpbmVhcnRpZmFjdDovL2Rib3NvZnQvcHJvamVjdElkLzU5YTM2MDhhLTliZWQtNGNiNC05NDY3LTZlZmFhYTNjYmVmNS9idWlsZElkLzU2MTUvYXJ0aWZhY3ROYW1lL2Vnc18wLjEuMC1jaS45X2xpbnV4X2FtZDY0LnRhci5neg2/content?format=file&subPath=%2Fegs_0.1.0-ci.9_linux_amd64.tar.gz'
  - name: sshPublicKey
    value: '$egsSshKey'
"@

    $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
    Start-Catlet -Id $catlet.Id -Force
    
    egs-tool update-ssh-config

    while ((egs-tool get-status $catlet.VmId) -ne 'available' ) {
      Start-Sleep -Seconds 2
    }

    $result = &ssh "$($catlet.Name).$($project.Name).eryph.alt" 'hostname'
    $result | Should -Be $catletName
  }


  It "Can connect to a Windows guest" {
    $config = @"
name: default
parent: dbosoft/winsrv2022-standard/starter
fodder:
- source: gene:dbosoft/guest-services/next:win-install
  variables:
  - name: downloadUrl
    value: 'https://artprodsu6weu.artifacts.visualstudio.com/A6eb69317-c955-4114-8558-b46413ccedea/59a3608a-9bed-4cb4-9467-6efaaa3cbef5/_apis/artifact/cGlwZWxpbmVhcnRpZmFjdDovL2Rib3NvZnQvcHJvamVjdElkLzU5YTM2MDhhLTliZWQtNGNiNC05NDY3LTZlZmFhYTNjYmVmNS9idWlsZElkLzU2MTUvYXJ0aWZhY3ROYW1lL2Vnc18wLjEuMC1jaS45X3dpbmRvd3NfYW1kNjQuemlw0/content?format=file&subPath=%2Fegs_0.1.0-ci.9_windows_amd64.zip'
  - name: sshPublicKey
    value: '$egsSshKey'
"@
    $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt
    Start-Catlet -Id $catlet.Id -Force
    
    egs-tool update-ssh-config

    while ((egs-tool get-status $catlet.VmId) -ne 'available' ) {
      Start-Sleep -Seconds 2
    }

    $result = &ssh -q "$($catlet.Name).$($project.Name).eryph.alt" 'hostname'
    $result | Should -Be $catletName
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
