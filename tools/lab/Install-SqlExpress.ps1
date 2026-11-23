$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$installer = Join-Path $env:RUNNER_TEMP 'SQLEXPR_x64_ENU.exe'
$media = Join-Path $env:RUNNER_TEMP 'SqlExpress2022'
$url = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLEXPR_x64_ENU.exe'
Write-Host 'Downloading Microsoft SQL Server 2022 Express full installation media'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer
$expected = '2E61C8BBDE6021F9026C54AD9DB4BBB1227E68761D4C00A6A50A2C70FE7AFE05'
if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne $expected) { throw 'SQL Express checksum mismatch' }
$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw 'SQL Express installer signature is not valid'
}
$extract = Start-Process $installer -ArgumentList "/Q /x:`"$media`"" -Wait -PassThru
if ($extract.ExitCode -ne 0) { throw "SQL Express extraction failed: $($extract.ExitCode)" }
$admin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$arguments = @('/Q','/ACTION=Install','/FEATURES=SQLENGINE','/INSTANCENAME=SQLEXPRESS',
    '/INSTANCEID=SQLEXPRESS','/IACCEPTSQLSERVERLICENSETERMS','/SUPPRESSPRIVACYSTATEMENTNOTICE=True',
    '/UPDATEENABLED=False','/ADDCURRENTUSERASSQLADMIN=True',"/SQLSYSADMINACCOUNTS=`"$admin`"",
    '/SQLSVCACCOUNT="NT Service\MSSQL$SQLEXPRESS"','/SQLSVCSTARTUPTYPE=Automatic','/TCPENABLED=0','/NPENABLED=0')
Write-Host 'Installing SQLENGINE as a real SQLEXPRESS Windows service'
$setup = Start-Process "$media\setup.exe" -ArgumentList $arguments -Wait -PassThru
if ($setup.ExitCode -notin @(0,3010)) {
    $summary = 'C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt'
    if (Test-Path $summary) { Get-Content $summary }
    throw "SQL Express installation failed: $($setup.ExitCode)"
}
Set-Service 'MSSQL$SQLEXPRESS' -StartupType Automatic
Start-Service 'MSSQL$SQLEXPRESS'
(Get-Service 'MSSQL$SQLEXPRESS').WaitForStatus('Running',[TimeSpan]::FromSeconds(90))
Import-Module SqlServer
$deadline = (Get-Date).AddMinutes(2)
do {
    try {
        $proof = Invoke-Sqlcmd -ServerInstance 'lpc:.\SQLEXPRESS' -Database master -TrustServerCertificate `
            -ConnectionTimeout 5 -QueryTimeout 15 -AbortOnError -Query @"
SELECT SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('EngineEdition') AS EngineEdition,
SERVERPROPERTY('ProductVersion') AS ProductVersion, SERVERPROPERTY('IsLocalDB') AS IsLocalDB,
ORIGINAL_LOGIN() AS AdministrativeLogin, IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin;
"@
        break
    } catch {
        if ((Get-Date) -gt $deadline) { throw }
        Start-Sleep 3
    }
} while ($true)
$proof | Format-List
Get-Service 'MSSQL$SQLEXPRESS' | Format-Table Name,Status,StartType
if ($proof.EngineEdition -ne 4 -or $proof.IsLocalDB -ne 0 -or $proof.IsSysadmin -ne 1) {
    throw 'Expected a real SQL Express service, not LocalDB, and an administrative setup connection'
}
$proof | Select-Object Edition,EngineEdition,ProductVersion,IsLocalDB,AdministrativeLogin,IsSysadmin |
    ConvertTo-Json | Set-Content "$env:GITHUB_WORKSPACE\artifacts\deployment-evidence\sql-server.json"
