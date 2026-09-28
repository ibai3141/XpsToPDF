$ErrorActionPreference = "Stop"
$installRoot = Join-Path ${env:ProgramFiles} "TytanXpsToPdf"
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
$startupLauncher = Join-Path $interactiveProfile "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\TytanXpsToPdf-AutoHotkey.cmd"

try {
    Stop-Service -Name TytanXpsToPdf -Force -ErrorAction SilentlyContinue
}
catch {
    # The service may already be stopped or absent.
}

# Wait until the service releases its executable and configuration files.
for ($attempt = 1; $attempt -le 15; $attempt++) {
    $service = Get-Service -Name TytanXpsToPdf -ErrorAction SilentlyContinue
    if ($null -eq $service -or $service.Status -eq "Stopped") {
        break
    }
    Start-Sleep -Seconds 1
}

Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey32 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
& sc.exe delete TytanXpsToPdf 2>$null | Out-Null
Remove-Item -LiteralPath $startupLauncher -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $PSScriptRoot ".install-success") -Force -ErrorAction SilentlyContinue

for ($attempt = 1; $attempt -le 10; $attempt++) {
    if (-not (Test-Path -LiteralPath $installRoot)) {
        break
    }
    Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $installRoot) {
        Start-Sleep -Milliseconds 500
    }
}

# Also clean installations created with the previous service name.
& sc.exe stop XpsToPdfService 2>$null | Out-Null
Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
& sc.exe delete XpsToPdfService 2>$null | Out-Null
$legacyRoot = Join-Path ${env:ProgramFiles} "XpsToPdfService"
for ($attempt = 1; $attempt -le 10; $attempt++) {
    if (-not (Test-Path -LiteralPath $legacyRoot)) {
        break
    }
    Remove-Item -LiteralPath $legacyRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $legacyRoot) {
        Start-Sleep -Milliseconds 500
    }
}

if (Test-Path -LiteralPath $installRoot) {
    throw "The service was stopped, but the installation folder could not be removed: $installRoot"
}

Write-Host "TytanXpsToPdf uninstalled. C:\XPS_OUT and C:\PDF were preserved."
