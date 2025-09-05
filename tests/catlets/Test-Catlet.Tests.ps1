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
name: $catletName
cpu:
  count: 1
memory:
  startup: 1024
networks:
- name: default
  adapter_name: eth0
variables:
- name: userName
  value: Eve
  required: true
- name: catletId
  type: String
  value: '#catletId'
  secret: false
  required: false
- name: vmId
  type: String
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
name: $catletName
parent: dbosoft/e2etests-os/base-0.1
cpu:
  count: 2
memory:
  startup: 512
drives:
- name: sda
  source: gene:dbosoft/ubuntu-24.04/20241217:sda
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
  value: '#REDACTED'
  secret: true
  required: true
- name: e2eUser
  value: e2e
  required: true
- name: catletId
  type: String
  value: '#catletId'
  secret: false
  required: false
- name: vmId
  type: String
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

    It "Expands configuration for existing catlet" {
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

      $catlet = New-Catlet -Config $config -Variables @{ userName = "Eve" } -SkipVariablesPrompt
      $vm =  Get-VM $catletName

      $result = Test-Catlet -Config $config -Id $catlet.Id

      $result | Should -Be @"
project: $($project.Name)
name: $catletName
cpu:
  count: 1
memory:
  startup: 1024
networks:
- name: default
  adapter_name: eth0
variables:
- name: userName
  value: Eve
  required: true
- name: catletId
  type: String
  value: $($catlet.Id)
  secret: false
  required: false
- name: vmId
  type: String
  value: $($vm.Id)
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
    echo '$($vm.Id)' >> hyperv-vm-id.txt
  secret: false

"@
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
