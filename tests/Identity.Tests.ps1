#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
}

Describe "Identity" {
  BeforeEach {
    $clientName = "client-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $client = New-EryphClient -Name $clientName -AllowedScopes "compute:read"
    $project = New-TestProject
  }

  It "Allows a client to authenticate with a shared secret" {
    $null = Add-EryphProjectMemberRole -ProjectName $project.Name -MemberId $client.Id -Role Reader
    
    # Grab the identity endpoint from the configuration as the
    # eryph-zero service picks a free port at random.
    $identityProvider = (Get-EryphClientCredentials -SystemClient -Configuration zero).IdentityProvider
    $tokenUrl = [System.Uri]"$identityProvider/connect/token"

    $clientWithSecret = New-EryphClientKey -Id $client.Id -SharedKey

    $tokenResponse = Invoke-RestMethod "$identityProvider/connect/token" `
      -Method Post `
      -Body @{
        grant_type = "client_credentials"
        client_id = $clientWithSecret.Id
        client_secret = $clientWithSecret.Key
        scope = "compute:read"
      } `
      -ContentType "application/x-www-form-urlencoded"

    $accessToken = $tokenResponse.access_token
    $accessToken | Should -Not -BeNullOrEmpty

    $computeUrl = "$($tokenUrl.Scheme)://$($tokenUrl.Host):$($tokenUrl.Port)/compute/v1/projects"
    $computeResponse = Invoke-RestMethod $computeUrl `
      -Method Get `
      -Authentication Bearer `
      -Token (ConvertTo-SecureString -String $accessToken -AsPlainText -Force)
    
    $computeResponse | Should -Not -BeNullOrEmpty
    $computeResponse.value | Should -HaveCount 1
    $computeResponse.value[0].id | Should -Be $project.Id
  }

  Context "Get-EryphAccessToken" {
    It "Returns an access token" {
      $accessToken = Get-EryphAccessToken -Scopes "compute:write"

      $accessToken.Scopes | Should -Be "compute:write"
    }
  }

  AfterEach {
    Remove-EryphClient -Id $client.Id
    Remove-EryphProject -Id $project.Id -Force
  }
}
