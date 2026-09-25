$ErrorActionPreference = "Stop"

$operatingSystem = Get-CimInstance Win32_OperatingSystem
if ([version]$operatingSystem.Version -lt [version]"10.0") {
    throw "This installer requires Windows 10 or later. Windows 7 and Windows 8.1 are not supported by the .NET 9 service."
}

$installRoot = Join-Path ${env:ProgramFiles} "TytanXpsToPdf"
$is64Bit = [Environment]::Is64BitOperatingSystem
$packageArchitecture = if ($is64Bit) { "x64" } else { "x86" }
$serviceSource = Join-Path $PSScriptRoot "service-$packageArchitecture"
$ghostSource = Join-Path $PSScriptRoot "GhostXPS-$packageArchitecture"
$serviceTarget = Join-Path $installRoot "XpsToPdfService.exe"
$scriptTarget = Join-Path $installRoot "SaveAsInterceptor\saveas_xps.ahk"
$architecture = $env:PROCESSOR_ARCHITEW6432
if ([string]::IsNullOrWhiteSpace($architecture)) {
    $architecture = $env:PROCESSOR_ARCHITECTURE
}
$ahkExecutable = if ($architecture -eq "AMD64") { "AutoHotkey64.exe" } else { "AutoHotkey32.exe" }
$ahkTarget = Join-Path $installRoot "SaveAsInterceptor\$ahkExecutable"
$interactiveAccount = (Get-CimInstance Win32_ComputerSystem).UserName
if ([string]::IsNullOrWhiteSpace($interactiveAccount)) {
    $interactiveUser = $env:USERNAME
    $interactiveProfile = $env:USERPROFILE
}
else {
    $interactiveUser = $interactiveAccount.Split('\')[-1]
    $interactiveProfile = (Get-CimInstance Win32_UserProfile |
        Where-Object { $_.LocalPath -and $_.LocalPath -like "C:\Users\$interactiveUser" }).LocalPath
}
if ([string]::IsNullOrWhiteSpace($interactiveProfile)) {
    throw "The profile for interactive user '$interactiveUser' was not found."
}
$startupFolder = Join-Path $interactiveProfile "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
$startupLauncher = Join-Path $startupFolder "TytanXpsToPdf-AutoHotkey.cmd"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this installer from an elevated PowerShell window."
}

if (-not (Test-Path -LiteralPath $serviceSource)) {
    throw "The package does not contain the service for $packageArchitecture Windows."
}
if (-not (Test-Path -LiteralPath $ghostSource)) {
    throw "The package does not contain GhostXPS for $packageArchitecture Windows."
}

New-Item -ItemType Directory -Force -Path $installRoot, "$installRoot\SaveAsInterceptor", "$installRoot\GhostXPS", "C:\XPS_OUT", "C:\PDF" | Out-Null

# Remove the previous service/folder name during upgrades.
& sc.exe stop XpsToPdfService 2>$null | Out-Null
Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
& sc.exe delete XpsToPdfService 2>$null | Out-Null
Remove-Item -LiteralPath (Join-Path ${env:ProgramFiles} "XpsToPdfService") -Recurse -Force -ErrorAction SilentlyContinue

& sc.exe stop TytanXpsToPdf 2>$null | Out-Null
Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey32 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Copy-Item -Path (Join-Path $serviceSource "*") -Destination $installRoot -Recurse -Force
Copy-Item -Path (Join-Path $ghostSource "*") -Destination "$installRoot\GhostXPS" -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "SaveAsInterceptor\*") -Destination "$installRoot\SaveAsInterceptor" -Recurse -Force

& sc.exe delete TytanXpsToPdf 2>$null | Out-Null
& sc.exe create TytanXpsToPdf binPath= "`"$serviceTarget`"" start= delayed-auto DisplayName= "Tytan XPS to PDF Service" | Out-Null
& sc.exe description TytanXpsToPdf "Converts Microsoft XPS Document Writer output to PDF for Tytan SQL." | Out-Null
& sc.exe failure TytanXpsToPdf reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
& sc.exe failureflag TytanXpsToPdf 1 | Out-Null

$launcherContent = "@echo off`r`nstart `"`" `"$ahkTarget`" `"$scriptTarget`"`r`n"
[IO.File]::WriteAllText($startupLauncher, $launcherContent, [Text.Encoding]::ASCII)

& sc.exe start TytanXpsToPdf | Out-Null
$serviceRunning = $false
for ($attempt = 1; $attempt -le 15; $attempt++) {
    Start-Sleep -Seconds 1
    $service = Get-Service -Name TytanXpsToPdf -ErrorAction Stop
    if ($service.Status -eq "Running") {
        $serviceRunning = $true
        break
    }
}
if (-not $serviceRunning) {
    throw "The TytanXpsToPdf service was installed but did not start. Open Services and check TytanXpsToPdf."
}

Start-Process -FilePath $ahkTarget -ArgumentList "`"$scriptTarget`""
if (-not (Test-Path -LiteralPath $startupLauncher)) {
    throw "The AutoHotkey startup launcher could not be created: $startupLauncher"
}
Write-Host "TytanXpsToPdf installed successfully."
