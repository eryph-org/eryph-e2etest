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

  Context "Stop-Catlet" {

    It "Stops VM process if Hyper-V cannot stop the VM" {
      # The config defines a systemd unit that takes 5 minutes to stop
      # and hence blocks the shutdown of the VM. This also blocks all
      # status changes in Hyper-V.
      $config = @'
parent: dbosoft/e2etests-os/base
fodder:
- name: systemd-unit
  type: cloud-config
  content: |
    write_files:
      - path: /usr/local/bin/delay-stop
        permissions: '0755'
        content: |
          #!/bin/bash
          for i in {1..300}; do
            sleep 1
            echo "Stopping..."
          done
          echo "Stopped."
      - path: /etc/systemd/system/delay.service
        content: |
          [Unit]
          Description=Custom delay
          After=multi-user.target

          [Service]
          RemainAfterExit=yes
          ExecStop=/usr/local/bin/delay-stop
          TimeoutSec=300

          [Install]
          WantedBy=multi-user.target
- name: enable-service
  type: shellscript
  content: |
    #!/bin/bash
    systemctl daemon-reload
    systemctl enable delay.service
    systemctl start delay.service
'@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config -SkipVariablesPrompt

      Connect-Catlet -CatletId $catlet.Id -WaitForCloudInit
      $vm = Get-VM -Name $catletName

      # The Stop-VM command will block as the VM is not shutting down.
      # Hence, we run it as a job.
      $job = Stop-VM -VM $vm -Force -AsJob
      Start-Sleep 5s
      $job.State | Should -Be Running
      
      # Normal attempts to stop the catlet should now fail.
      { Stop-VM -VM $vm -TurnOff } | Should -Throw
      { Stop-Catlet -Id $catlet.Id -Force -Mode Hard } | Should -Throw

      Stop-Catlet -Id $catlet.Id -Force -Mode Kill
      
      $catlet = Get-Catlet -Id $catlet.Id
      $catlet.Status | Should -Be Stopped
    
      $vm = Get-VM -Name $catletName
      $vm.State | Should -Be Off 
    }
    
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
