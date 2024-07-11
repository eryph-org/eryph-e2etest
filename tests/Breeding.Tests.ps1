BeforeAll {
    . $PSScriptRoot/../Use-Settings.ps1

    function Connect-Catlet {
        param(
            [Parameter(Mandatory=$true)]
            [string]
            $CatletName
        )

        $catlet = Get-Catlet | Where-Object Name -eq $CatletName
        $null = Start-Catlet -Id $catlet.Id -Force
        $catletIp = Get-CatletIp -Id $catlet.Id
        
        Start-Sleep -Seconds 5
        
        $cred = [PSCredential]::New("e2e", (ConvertTo-SecureString "e2e" -AsPlainText -Force))
        
        return New-SSHSession -ComputerName $catletIp.IpAddress -Credential $cred -AcceptKey
    }
}

Describe "Breeding and feeding of catlets" {

    BeforeEach {
        $projectName = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
        $project = New-EryphProject -Name $projectName
        $catletName = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    }

    Context "New-Catlet" {

        It "Creates catlet with parameterized fodder" {
            $config = @'
parent: dbosoft/e2etests-os/base

variables:
- name: userName
  value: Eve E2E

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
'@
                    
            New-Catlet -Name $catletName -ProjectName $projectName -Config $config -SkipVariablesPrompt
            $sshSession = Connect-Catlet -CatletName $catletName
            $helloWorldResponse = Invoke-SSHCommand -Command "cat /hello-world.txt" -SSHSession $sshSession
            $helloWorldResponse.Output | Should -Be "Hello Eve E2E!"

            $vm = Get-VM -Name $catletName
            $vmIdResponse = Invoke-SSHCommand -Command "cat /hyperv-vm-id.txt" -SSHSession $sshSession
            $vmIdResponse.Output | Should -Be $vm.Id
        }
    }

    AfterEach {
        Remove-EryphProject -Id $project.Id
    }
}
