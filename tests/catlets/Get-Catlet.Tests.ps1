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

    Context "Get-Catlet" {
    It "Returns the catlet configuration with capabilities" {
      $config = @'
capabilities:
- name: dynamic_memory
- name: nested_virtualization
- name: secure_boot
  details:
  - template:MicrosoftUEFICertificateAuthority
- name: tpm
'@

      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $expectedConfig = @"
version: 1.0
project: $($project.Name)
name: $catletName
location: *
cpu:
  count: 1
memory:
  startup: 1024
  minimum: 512
  maximum: 1048576
capabilities:
- name: nested_virtualization
- name: secure_boot
  details:
  - template:MicrosoftUEFICertificateAuthority
- name: dynamic_memory
- name: tpm

"@
      $catletConfig = Get-Catlet -Id $catlet.Id -Config
      $catletConfig | Should -BeLikeExactly $expectedConfig
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
