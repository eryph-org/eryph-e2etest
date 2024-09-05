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

function Setup-Gene {
  param(
    [Parameter(Mandatory = $true)]
    [string]
    $GeneSetTag
  )
  $PSNativeCommandUseErrorActionPreference = $true
  $ErrorActionPreference = 'Stop'

  $geneSetsPath = (Resolve-Path -Path (Join-Path $PSScriptRoot ".." "genesets")).Path
  $workPath = (Resolve-Path -Path (Join-Path $PSScriptRoot ".." ".work")).Path
  
  if ($GeneSetTag -eq "dbosoft/e2etests-nullos/0.1") {
    # Create an empty volume the nullos geneset on the fly.
    $null = New-Item -Path (Join-Path $workPath "dbosoft" "e2etests-nullos" "0.1") -ItemType Directory -Force
    $null = New-Item -Path (Join-Path $geneSetsPath "dbosoft" "e2etests-nullos" "0.1" ".pack") -ItemType Directory -Force
    Remove-Item -Path (Join-Path $workPath "dbosoft" "e2etests-nullos" "0.1" "sda.vhdx") -Force
    $null = New-VHD -Path (Join-Path $workPath "dbosoft" "e2etests-nullos" "0.1" "sda.vhdx") -SizeBytes 26843545600 -Dynamic

    $packable = @(@{
      fullPath = (Join-Path $workPath "dbosoft" "e2etests-nullos" "0.1" "sda.vhdx")
      fileName = "sda.vhdx"
      geneType = "Volume"
      geneName = "sda"
      extremeCompression = $true
    })
    Set-Content -Path (Join-Path $geneSetsPath "dbosoft" "e2etests-nullos" "0.1" ".pack" "packable.json") -Value (ConvertTo-Json $packable)
  }

  eryph-packer geneset-tag pack $GeneSetTag --workdir $geneSetsPath
  Remove-Item -Path (Join-Path $EryphSettings.LocalGenePoolPath $GeneSetTag) -Force -Recurse -ErrorAction SilentlyContinue
  Copy-Item -Path (Join-Path $geneSetsPath $GeneSetTag ".packed") `
    -Destination (Join-Path $EryphSettings.LocalGenePoolPath $GeneSetTag) `
    -Recurse
}

function Setup-GenePool {
  $PSNativeCommandUseErrorActionPreference = $true
  $ErrorActionPreference = 'Stop'

  $geneSetsPath = (Resolve-Path -Path (Join-Path $PSScriptRoot ".." "genesets")).Path

  # The max depth of 3 prevents the script from picking up manifests inside the .packed directories
  foreach ($manifestPath in (Get-ChildItem -Path $geneSetsPath -Filter "geneset-tag.json" -Depth 3 -Recurse)) {
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json -AsHashtable
    Setup-Gene -GeneSetTag $manifest.geneset
  }
}
