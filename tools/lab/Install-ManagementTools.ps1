param([switch]$InstallSsms)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module SqlServer
Get-Module SqlServer | Format-List Name,Version,ModuleBase
if ($InstallSsms) {
    $installer = Join-Path $env:RUNNER_TEMP 'vs_SSMS.exe'
    Invoke-WebRequest -UseBasicParsing 'https://aka.ms/ssms/22/release/vs_SSMS.exe' -OutFile $installer
    $signature = Get-AuthenticodeSignature $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw 'SSMS installer signature validation failed'
    }
    Write-Host 'Installing SQL Server Management Studio 22 in unattended mode'
    $process = Start-Process $installer -ArgumentList '--quiet --wait --norestart --installPath C:\SSMS --addProductLang en-US' -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "SSMS installation failed: $($process.ExitCode)" }
    $ssms = 'C:\SSMS\Common7\IDE\Ssms.exe'
    if (-not (Test-Path $ssms)) { throw 'Installed Ssms.exe was not found' }
    $version = (Get-Item $ssms).VersionInfo.ProductVersion
    Write-Host "SSMS installed: $ssms; version: $version; setup exit: $($process.ExitCode)"
    @{ Installed=$true; Executable=$ssms; Version=$version; InstallerExitCode=$process.ExitCode; InteractiveGuiUsed=$false } |
        ConvertTo-Json | Set-Content "$env:GITHUB_WORKSPACE\artifacts\deployment-evidence\ssms.json"
}
Invoke-Sqlcmd -ServerInstance 'lpc:.\SQLEXPRESS' -Database master -TrustServerCertificate `
    -Query "SELECT @@SERVERNAME AS ServerName, SERVERPROPERTY('Edition') AS Edition, name, state_desc FROM sys.databases;" `
    -AbortOnError | Format-Table
$response = Invoke-WebRequest 'http://127.0.0.1:8080/' -UseBasicParsing -TimeoutSec 90
if ($response.StatusCode -ne 200) { throw 'IIS website unavailable after management-tool setup' }
Write-Host "SQL management ready; IIS website still responds with HTTP $($response.StatusCode)"
