#Requires -Version 7.4
#Requires -Module Posh-SSH

function Connect-Catlet {
  param(
    [Parameter(Mandatory = $true)]
    [guid]
    $CatletId,

    [Parameter()]
    [string]
    $Username = "e2e",

    [Parameter()]
    [securestring]
    $Password = (ConvertTo-SecureString "e2e" -AsPlainText -Force)
  )
  
  $null = Start-Catlet -Id $CatletId -Force
  $catletIp = Get-CatletIp -Id $CatletId
  
  $timeout = New-TimeSpan -Minutes 10
  $start = Get-Date
  $credentials = [PSCredential]::New($Username, $Password)

  # Retry until the SSH session is established or the timeout is reached.
  # Depending on the state of the catlet and the network, a connection
  # attempt can either timeout or immediately fail.
  while ($true) {
    try {
      return New-SSHSession -ComputerName $catletIp.IpAddress -Credential $credentials -AcceptKey -Force
    } catch {
      if (((Get-Date) - $start) -gt $timeout) {
        throw
      }
      Start-Sleep -Seconds 5
    }
  }
}

function New-TestProject {
  $projectName = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
  New-EryphProject -Name $projectName
}

function New-CatletName {
  "catlet-$(Get-Date -Format 'yyyyMMddHHmmss')"
}
