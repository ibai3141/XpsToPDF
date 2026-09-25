$ErrorActionPreference = "Stop"

$installRoot = Join-Path ${env:ProgramFiles} "XpsToPdfService"
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
$startupLauncher = Join-Path $startupFolder "XpsToPdfService-AutoHotkey.cmd"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this installer from an elevated PowerShell window."
}

New-Item -ItemType Directory -Force -Path $installRoot, "$installRoot\SaveAsInterceptor", "C:\XPS_OUT", "C:\PDF" | Out-Null
& sc.exe stop XpsToPdfService 2>$null | Out-Null
Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey32 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Copy-Item -Path (Join-Path $PSScriptRoot "service\*") -Destination $installRoot -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "GhostXPS") -Destination $installRoot -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "SaveAsInterceptor\*") -Destination "$installRoot\SaveAsInterceptor" -Recurse -Force

& sc.exe delete XpsToPdfService 2>$null | Out-Null
& sc.exe create XpsToPdfService binPath= "`"$serviceTarget`"" start= delayed-auto DisplayName= "XPS to PDF Service" | Out-Null
& sc.exe description XpsToPdfService "Converts Microsoft XPS Document Writer output to PDF." | Out-Null
& sc.exe failure XpsToPdfService reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
& sc.exe failureflag XpsToPdfService 1 | Out-Null

$launcherContent = "@echo off`r`nstart `"`" `"$ahkTarget`" `"$scriptTarget`"`r`n"
[IO.File]::WriteAllText($startupLauncher, $launcherContent, [Text.Encoding]::ASCII)

& sc.exe start XpsToPdfService | Out-Null
Start-Sleep -Seconds 2
$service = Get-Service -Name XpsToPdfService -ErrorAction Stop
if ($service.Status -ne "Running") {
    throw "The XpsToPdfService service was installed but did not start. Open Services and check XpsToPdfService."
}

Start-Process -FilePath $ahkTarget -ArgumentList "`"$scriptTarget`""
if (-not (Test-Path -LiteralPath $startupLauncher)) {
    throw "The AutoHotkey startup launcher could not be created: $startupLauncher"
}
Write-Host "XpsToPdfService installed successfully."
