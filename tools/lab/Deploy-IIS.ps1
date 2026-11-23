param([Parameter(Mandatory=$true)][string]$PublishDirectory)
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration
Import-Module SqlServer
$destination = 'C:\sites\PartsUnlimited'
if (-not (Test-Path "$PublishDirectory\bin\PartsUnlimited.dll")) { throw 'Compiled website artifact is missing' }
Copy-Item "$PublishDirectory\*" $destination -Recurse -Force
$connection = 'Server=lpc:.\SQLEXPRESS;Database=PartsUnlimitedWebsite;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;'
$configPath = Join-Path $destination 'Web.config'
[xml]$config = Get-Content $configPath -Raw
$entry = $config.configuration.connectionStrings.add | Where-Object name -eq 'DefaultConnectionString'
$entry.connectionString = $connection
$adminPassword = 'Lab-Aa1!' + [Guid]::NewGuid().ToString('N')
Write-Output "::add-mask::$adminPassword"
($config.configuration.appSettings.add | Where-Object key -eq 'Authentication.Administrator.Password').value = $adminPassword
($config.configuration.appSettings.add | Where-Object key -eq 'Keys:ApplicationInsights:InstrumentationKey').value = ''
$config.Save($configPath)

$bootstrap = Join-Path $env:RUNNER_TEMP 'database-bootstrap'
New-Item -ItemType Directory -Force $bootstrap | Out-Null
Copy-Item "$destination\bin\*.dll" $bootstrap
$executable = Join-Path $bootstrap 'InitializeDatabase.exe'
$bin = Join-Path $destination 'bin'
$compiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $compiler /nologo /target:exe "/out:$executable" `
    "/reference:$bin\PartsUnlimited.dll" "/reference:$bin\EntityFramework.dll" `
    "/reference:$bin\Microsoft.AspNet.Identity.EntityFramework.dll" `
    "/reference:$bin\Microsoft.AspNet.Identity.Core.dll" /reference:System.Core.dll /reference:System.Data.dll `
    "$env:GITHUB_WORKSPACE\tools\lab\Initialize-Database.cs"
if ($LASTEXITCODE -ne 0) { throw 'Database bootstrap compilation failed' }
[xml]$bootstrapConfig = '<configuration><configSections><section name="entityFramework" type="System.Data.Entity.Internal.ConfigFile.EntityFrameworkSection, EntityFramework" /></configSections><connectionStrings><add name="DefaultConnectionString" providerName="System.Data.SqlClient" /></connectionStrings><entityFramework><providers><provider invariantName="System.Data.SqlClient" type="System.Data.Entity.SqlServer.SqlProviderServices, EntityFramework.SqlServer" /></providers></entityFramework></configuration>'
$bootstrapConfig.configuration.connectionStrings.add.SetAttribute('connectionString',$connection)
$runtime = $bootstrapConfig.ImportNode($config.configuration.runtime,$true)
$bootstrapConfig.configuration.AppendChild($runtime) | Out-Null
$bootstrapConfig.Save("$executable.config")
& $executable
if ($LASTEXITCODE -ne 0) { throw 'Original application database initialization failed' }

Invoke-Sqlcmd -ServerInstance 'lpc:.\SQLEXPRESS' -Database master -TrustServerCertificate -AbortOnError -Query @"
IF SUSER_ID(N'IIS APPPOOL\PartsUnlimitedPool') IS NULL
    CREATE LOGIN [IIS APPPOOL\PartsUnlimitedPool] FROM WINDOWS;
USE [PartsUnlimitedWebsite];
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\PartsUnlimitedPool') IS NULL
    CREATE USER [IIS APPPOOL\PartsUnlimitedPool] FOR LOGIN [IIS APPPOOL\PartsUnlimitedPool] WITH DEFAULT_SCHEMA=[dbo];
ALTER ROLE [db_owner] ADD MEMBER [IIS APPPOOL\PartsUnlimitedPool];
"@
if ((Get-WebAppPoolState 'PartsUnlimitedPool').Value -ne 'Started') { Start-WebAppPool 'PartsUnlimitedPool' }
if ((Get-WebsiteState 'PartsUnlimitedLab').Value -ne 'Started') { Start-Website 'PartsUnlimitedLab' }
$url = 'http://localhost:8080/'
$deadline = (Get-Date).AddMinutes(3)
do {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 90
        if ($response.StatusCode -eq 200) { break }
    } catch {
        if ((Get-Date) -gt $deadline) { throw }
        Write-Host 'Waiting for ASP.NET application startup'
        Start-Sleep 5
    }
} while ($true)
$proof = Invoke-Sqlcmd -ServerInstance 'lpc:.\SQLEXPRESS' -Database PartsUnlimitedWebsite -TrustServerCertificate -AbortOnError -Query @"
SELECT DB_NAME() AS DatabaseName,
 (SELECT COUNT(*) FROM dbo.Products) AS Products,
 (SELECT COUNT(*) FROM dbo.Categories) AS Categories,
 (SELECT COUNT(*) FROM dbo.AspNetUsers) AS Users,
 (SELECT COUNT(*) FROM sys.tables) AS Tables;
"@
$proof | Format-List
Invoke-Sqlcmd -ServerInstance 'lpc:.\SQLEXPRESS' -Database PartsUnlimitedWebsite -TrustServerCertificate -AbortOnError `
    -Query 'SELECT name AS ApplicationTable FROM sys.tables ORDER BY name;' | Format-Table
if ($proof.Products -ne 18 -or $proof.Categories -ne 5 -or $proof.Users -lt 1) { throw 'Database-backed application verification failed' }
$proof | Select-Object DatabaseName,Products,Categories,Users,Tables |
    ConvertTo-Json | Set-Content "$env:GITHUB_WORKSPACE\artifacts\deployment-evidence\database.json"
@{ Url=$url; HttpStatus=[int]$response.StatusCode; Commit=$env:GITHUB_SHA; Temporary=$true } |
    ConvertTo-Json | Set-Content "$env:GITHUB_WORKSPACE\artifacts\deployment-evidence\http.json"
Write-Host "Deployed original PartsUnlimited to IIS: HTTP $($response.StatusCode) at $url; real SQL Express database verified"
