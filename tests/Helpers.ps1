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
    
  Start-Sleep -Seconds 5
    
  $credentials = [PSCredential]::New($Username, $Password)
    
  return New-SSHSession -ComputerName $catletIp.IpAddress -Credential $credentials -AcceptKey -Force -ConnectionTimeout 60
}

function New-TestProject {
  $projectName = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
  New-EryphProject -Name $projectName
}

function New-CatletName {
  "catlet-$(Get-Date -Format 'yyyyMMddHHmmss')"
}
