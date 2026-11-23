$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force "$env:GITHUB_WORKSPACE\artifacts\deployment-evidence" | Out-Null
$features = Install-WindowsFeature Web-Server,Web-Asp-Net45,Web-Mgmt-Tools -IncludeManagementTools
$features | Format-List
if (-not $features.Success -or $features.RestartNeeded -eq 'Yes') {
    throw 'IIS installation failed or requires a reboot'
}
Import-Module WebAdministration
$site = 'PartsUnlimitedLab'
$pool = 'PartsUnlimitedPool'
$destination = 'C:\sites\PartsUnlimited'
New-Item -ItemType Directory -Force $destination | Out-Null
if (-not (Test-Path "IIS:\AppPools\$pool")) { New-WebAppPool $pool | Out-Null }
Set-ItemProperty "IIS:\AppPools\$pool" managedRuntimeVersion 'v4.0'
Set-ItemProperty "IIS:\AppPools\$pool" managedPipelineMode 'Integrated'
Set-ItemProperty "IIS:\AppPools\$pool" processModel.identityType 4
Set-ItemProperty "IIS:\AppPools\$pool" processModel.loadUserProfile $true
if (-not (Test-Path "IIS:\Sites\$site")) {
    New-Website -Name $site -PhysicalPath $destination -ApplicationPool $pool -IPAddress '127.0.0.1' -Port 8080 | Out-Null
}
icacls.exe $destination /grant 'IIS AppPool\PartsUnlimitedPool:(OI)(CI)(RX)'
if ($LASTEXITCODE -ne 0) { throw 'IIS file permissions could not be set' }
Start-Service W3SVC
Get-WindowsFeature Web-Server,Web-Asp-Net45 | Format-Table Name,InstallState
Get-Website -Name $site | Format-List Name,State,PhysicalPath,ApplicationPool,Bindings
Get-Item "IIS:\AppPools\$pool" | Format-List Name,State,managedRuntimeVersion,managedPipelineMode
@{ Site=$site; Pool=$pool; Directory=$destination; Port=8080; Binding='127.0.0.1'; Temporary=$true } |
    ConvertTo-Json | Set-Content "$env:GITHUB_WORKSPACE\artifacts\deployment-evidence\iis.json"
