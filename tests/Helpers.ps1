#Requires -Version 7.4
#Requires -Module Posh-SSH

function Connect-Catlet {
  param(
    [Parameter(Mandatory = $true)]
    [guid]
    $CatletId,

    [Parameter()]
    [string]
    $Username = 'e2e',

    [Parameter()]
    [securestring]
    $Password = (ConvertTo-SecureString 'e2e' -AsPlainText -Force),

    [Parameter()]
    [switch]
    $WaitForCloudInit
  )

  $PSNativeCommandUseErrorActionPreference = $true
  $ErrorActionPreference = 'Stop'

  $null = Start-Catlet -Id $CatletId -Force
  $catletIp = Get-CatletIp -Id $CatletId

  Connect-CatletIp -IpAddress $catletIp[0].IpAddress -Username $Username -Password $Password -WaitForCloudInit:$WaitForCloudInit
}

function Connect-CatletIp {
  param(
    [Parameter(Mandatory = $true)]
    [string]
    $IpAddress,

    [Parameter()]
    [string]
    $Username = 'e2e',

    [Parameter()]
    [securestring]
    $Password = (ConvertTo-SecureString 'e2e' -AsPlainText -Force),

    [Parameter()]
    [timespan]
    $Timeout = (New-TimeSpan -Minutes 10),

    [Parameter()]
    [switch]
    $WaitForCloudInit
  )

  $PSNativeCommandUseErrorActionPreference = $true
  $ErrorActionPreference = 'Stop'
  $InformationPreference = 'Continue'
  
  $cutOff = (Get-Date).Add($Timeout)

  # Remove the existing known host entry to avoid host key verification
  # errors. We expect the host key to change as we just created a new catlet.
  $null = Remove-SSHTrustedHost -HostName $IpAddress

  $credentials = [PSCredential]::New($Username, $Password)
  $sshSession = $null

  # Retry until the SSH session is established or the timeout is reached.
  # Depending on the state of the catlet and the network, a connection
  # attempt can either timeout or immediately fail.
  while (-not $sshSession) {
    try {
      $sshSession = New-SSHSession -ComputerName $IpAddress -Credential $credentials -AcceptKey
    } catch {
      Write-Information "Failed to establish SSH session: $($_)"
      if ((Get-Date) -gt $cutOff) {
        throw 'Failed to establish an SSH session within the timeout'
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
    $response = Invoke-SSHCommand -Command 'cloud-init status --format json' -SSHSession $sshSession
    $json = $response.Output -join ' '
    $result = ConvertFrom-Json $json -AsHashtable
    $extendedStatus = $result['extended_status']
    if (($extendedStatus -inotlike '*not started*') -and ($extendedStatus -inotlike '*running*')) {
      if (($extendedStatus -ilike '*degraded*') -or ($extendedStatus -ilike '*error*')) {
        throw "cloud-init reported an error: $extendedStatus. Output: $json"
      }
      break
    }
    if ((Get-Date) -gt $cutOff) {
      throw "cloud-init did not finish within the timeout and still reports: $extendedStatus. Output: $json"
    }
    Start-Sleep -Seconds 5
  }

  # Verify that our cloud-init config is valid.
  $schemaResult = Invoke-SSHCommand -Command "sudo cloud-init schema --system" -SSHSession $sshSession
  if ($schemaResult.ExitStatus -ne 0) {
    throw "cloud-init reports that the config is invalid:  $($schemaResult.Output)"
  }

  return $sshSession
}

function Wait-Assert {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [scriptblock]
    $Assertion,

    [Parameter()]
    [timespan]
    $Timeout = (New-TimeSpan -Minutes 1),

    [Parameter()]
    [timespan]
    $Interval = (New-TimeSpan -Seconds 5)
  )

  $PSNativeCommandUseErrorActionPreference = $true
  $ErrorActionPreference = 'Stop'

  $cutOff = (Get-Date).Add($Timeout)

  while ($true) {
    try {
      & $Assertion
      return
    } catch {
      if ((Get-Date) -gt $cutOff) {
        throw
      }
    }
    Start-Sleep -Seconds $Interval.TotalSeconds
  }
}

function New-TestProject {
  $projectName = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
  New-EryphProject -Name $projectName
}

function New-CatletName {
  "clt$(Get-Date -Format 'yyMMddHHmmss')"
}

function Setup-Gene {
  param(
    [Parameter(Mandatory = $true)]
    [string]
    $GeneSetTag
  )

  $PSNativeCommandUseErrorActionPreference = $true
  $ErrorActionPreference = 'Stop'

  $parentFolder = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
  $geneSetsPath = Join-Path $parentFolder "genesets"
  $workPath = Join-Path $parentFolder ".work"
  
  if ($GeneSetTag -eq "dbosoft/e2etests-nullos/0.1") {
    # Create an empty volume the nullos geneset on the fly.
    $null = New-Item -Path (Join-Path $workPath "dbosoft" "e2etests-nullos" "0.1") -ItemType Directory -Force
    $null = New-Item -Path (Join-Path $geneSetsPath "dbosoft" "e2etests-nullos" "0.1" ".pack") -ItemType Directory -Force
    Remove-Item -Path (Join-Path $workPath "dbosoft" "e2etests-nullos" "0.1" "sda.vhdx") -Force -ErrorAction SilentlyContinue
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
