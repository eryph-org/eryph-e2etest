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
    $Password = (ConvertTo-SecureString "e2e" -AsPlainText -Force),

    [Parameter()]
    [switch]
    $WaitForCloudInit
  )
  
  $null = Start-Catlet -Id $CatletId -Force
  $catletIp = Get-CatletIp -Id $CatletId
  
  # Remove the existing known host entry to avoid host key verification
  # errors. We expect the host key to change as we just created a new catlet.
  $null = Remove-SSHTrustedHost -HostName $catletIp.IpAddress

  $timeout = New-TimeSpan -Minutes 10
  $start = Get-Date
  $credentials = [PSCredential]::New($Username, $Password)
  $sshSession = $null

  # Retry until the SSH session is established or the timeout is reached.
  # Depending on the state of the catlet and the network, a connection
  # attempt can either timeout or immediately fail.
  while (-not $sshSession) {
    try {
      $sshSession = New-SSHSession -ComputerName $catletIp.IpAddress -Credential $credentials -AcceptKey
    } catch {
      if (((Get-Date) - $start) -gt $timeout) {
        throw
      }
      Start-Sleep -Seconds 5
    }
  }

  if (-not $WaitForCloudInit) {
    return $sshSession
  }
  
  # Wait for cloud-init to finish. This is necessary as the SSH connection might already
  # succeed while cloud-init is still running. Additionally, this also ensures that
  # cloud-init did not fail.
  while ($true) {
    $result = Invoke-SSHCommand -Command "cloud-init status" -SSHSession $sshSession
    if (($result.Output -inotlike '*not started*') -and ($result.Output -inotlike '*running*')) {
      if (($result.Output -ilike '*degraded*') -or ($result.Output -ilike '*error*')) {
        throw "cloud-init reported an error: $($result.Output)"
      }
      return $sshSession
    }
    if (((Get-Date) - $start) -gt $timeout) {
      throw 'cloud-init did not finish within the timeout'
    }
    Start-Sleep -Seconds 5
  }
}

function New-TestProject {
  $projectName = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
  New-EryphProject -Name $projectName
}

function New-CatletName {
  "catlet-$(Get-Date -Format 'yyyyMMddHHmmss')"
}
