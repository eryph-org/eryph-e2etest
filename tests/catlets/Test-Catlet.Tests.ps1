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

  Context "Test-Catlet" {

    It "Quickly validates catlet configuration and returns errors" {
      $config = @'
name: invalid$name
'@
      $result = Test-Catlet -Config $config -Quick

      $result.IsValid | Should -BeFalse
      $result.Errors | Should -HaveCount 1
      $result.Errors[0].Message | Should -BeLike "The catlet name contains invalid characters.*"
    }

    It "Expands configuration for new catlet" {
      $config = @"
name: $catletName
project: $($project.Name)
variables:
- name: userName
  required: true
fodder:
- name: add-user-greeting
  type: shellscript
  content: |
    #!/bin/bash
    echo 'Hello {{ userName }}!' >> hello-world.txt
- name: write-vm-id
  type: shellscript
  content: |
    #!/bin/bash
    echo '{{ vmId }}' >> hyperv-vm-id.txt
"@

      $result = Test-Catlet -Config $config -Variables @{ userName = "Eve" } -SkipVariablesPrompt

      $result | Should -Be @"
config_type: specification
project: $($project.Name)
name: $catletName
hostname: $catletName
environment: default
store: default
cpu:
  count: 1
memory:
  startup: 1024
network_adapters:
- name: eth0
networks:
- name: default
  adapter_name: eth0
variables:
- name: userName
  type: string
  value: Eve
  required: true
- name: catletId
  type: string
  value: '#catletId'
  secret: false
  required: false
- name: vmId
  type: string
  value: '#vmId'
  secret: false
  required: false
fodder:
- name: add-user-greeting
  type: shellscript
  content: |
    #!/bin/bash
    echo 'Hello Eve!' >> hello-world.txt
  secret: false
- name: write-vm-id
  type: shellscript
  content: |-
    #!/bin/bash
    echo '#vmId' >> hyperv-vm-id.txt
  secret: false

"@
    }

    It "Expands configuration for new catlet with only parent" {
      $result = Test-Catlet -Name $catletName -Parent 'dbosoft/e2etests-os/base' -SkipVariablesPrompt

      $result | Should -Be @"
config_type: specification
project: default
name: $catletName
hostname: $catletName
environment: default
store: default
parent: dbosoft/e2etests-os/base-0.1
cpu:
  count: 2
memory:
  startup: 512
drives:
- name: sda
  store: default
  source: gene:dbosoft/ubuntu-24.04/20250913:sda
  type: vhd
network_adapters:
- name: eth0
capabilities:
- name: secure_boot
  details:
  - template:MicrosoftUEFICertificateAuthority
networks:
- name: default
  adapter_name: eth0
variables:
- name: e2ePassword
  type: string
  value: '#REDACTED'
  secret: true
  required: true
- name: e2eUser
  type: string
  value: e2e
  required: true
- name: catletId
  type: string
  value: '#catletId'
  secret: false
  required: false
- name: vmId
  type: string
  value: '#vmId'
  secret: false
  required: false
fodder:
- name: add-user
  source: gene:dbosoft/e2etests-os/base-0.1:catlet
  type: cloud-config
  content: |-
    #REDACTED
  secret: true

"@

    }
  
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
