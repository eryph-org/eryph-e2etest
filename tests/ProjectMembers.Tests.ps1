#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
}

Describe "ProjectMembers" {
  BeforeEach {
    $clientName = "client-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $client = New-EryphClient -Name $clientName -AllowedScopes "compute:read"
    $project = New-TestProject
  }

  It "Add and removes a project member" {
    $role = Add-EryphProjectMemberRole -ProjectName $project.Name -MemberId $client.Id -Role Reader

    $roles = Get-EryphProjectMemberRole -ProjectName $project.Name
    $roles | Should -HaveCount 1
    $roles[0].Id | Should -Be $role.Id
    $roles[0].MemberId | Should -Be $client.Id
    $roles[0].RoleName | Should -Be "Reader"
    $roles[0].Project.Id | Should -Be $project.Id
    $roles[0].Project.TenantId | Should -Be $project.TenantId
    $roles[0].Project.Name | Should -Be $project.Name

    Remove-EryphProjectMemberRole -ProjectName $project.Name -Id $role.Id

    $roles = Get-EryphProjectMemberRole -ProjectName $project.Name
    $roles | Should -HaveCount 0
  }

  AfterEach {
    Remove-EryphClient -Id $client.Id
    Remove-EryphProject -Id $project.Id -Force
  }
}
