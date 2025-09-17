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

    It "Returns the catlet configuration" {
      $config = @"
name: $catletName
"@

      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config

      $expectedConfig = @"
config_type: instance
project: $($project.Name)
name: $catletName
location: *
hostname: $catletName
environment: default
store: default
cpu:
  count: 1
memory:
  startup: 1024
network_adapters:
- name: eth0
  mac_address: d2:ab:*
networks:
- name: default
  adapter_name: eth0
  subnet_v4:
    name: default
    ip_pool: default

"@
      $catletConfig = Get-Catlet -Id $catlet.Id -Config
      $catletConfig | Should -BeLikeExactly $expectedConfig
    }
    
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
config_type: instance
project: $($project.Name)
name: $catletName
location: *
hostname: $catletName
environment: default
store: default
cpu:
  count: 1
memory:
  startup: 1024
  minimum: 512
  maximum: 1048576
network_adapters:
- name: eth0
  mac_address: d2:ab:*
capabilities:
- name: dynamic_memory
- name: nested_virtualization
- name: secure_boot
  details:
  - template:MicrosoftUEFICertificateAuthority
- name: tpm
networks:
- name: default
  adapter_name: eth0
  subnet_v4:
    name: default
    ip_pool: default

"@
      $catletConfig = Get-Catlet -Id $catlet.Id -Config
      $catletConfig | Should -BeLikeExactly $expectedConfig
    }

  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
