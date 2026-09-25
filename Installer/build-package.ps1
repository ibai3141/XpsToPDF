param(
    [string]$Output = (Join-Path $PSScriptRoot "package"),
    [string]$GhostXpsSource = "C:\Users\Ibai\Downloads\ghostxps-10.08.0-win64\ghostxps-10.08.0-win64",
    [string]$GhostXpsSource32 = "C:\Users\Ibai\Downloads\ghostxps-10.08.0-win32\ghostxps-10.08.0-win32",
    [string]$AutoHotkeySource = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$AutoHotkey32Source = "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$publish64 = Join-Path $Output "service-x64"
$publish32 = Join-Path $Output "service-x86"
$ghostDestination64 = Join-Path $Output "GhostXPS-x64"
$ghostDestination32 = Join-Path $Output "GhostXPS-x86"
$interceptorDestination = Join-Path $Output "SaveAsInterceptor"

Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Output, $ghostDestination64, $ghostDestination32, $interceptorDestination | Out-Null

dotnet publish (Join-Path $projectRoot "XpsToPdfService.csproj") `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $publish64

dotnet publish (Join-Path $projectRoot "XpsToPdfService.csproj") `
    -c Release -r win-x86 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $publish32

if (-not (Test-Path -LiteralPath (Join-Path $GhostXpsSource "gxpswin64.exe"))) {
    throw "GhostXPS was not found at: $GhostXpsSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $GhostXpsSource32 "gxpswin32.exe"))) {
    throw "32-bit GhostXPS was not found at: $GhostXpsSource32"
}
if (-not (Test-Path -LiteralPath $AutoHotkeySource)) {
    throw "AutoHotkey was not found at: $AutoHotkeySource"
}
if (-not (Test-Path -LiteralPath $AutoHotkey32Source)) {
    throw "32-bit AutoHotkey was not found at: $AutoHotkey32Source"
}

Copy-Item -Path (Join-Path $GhostXpsSource "*") -Destination $ghostDestination64 -Recurse -Force
Copy-Item -Path (Join-Path $GhostXpsSource32 "*") -Destination $ghostDestination32 -Recurse -Force
Copy-Item -LiteralPath $AutoHotkeySource -Destination (Join-Path $interceptorDestination "AutoHotkey64.exe") -Force
Copy-Item -LiteralPath $AutoHotkey32Source -Destination (Join-Path $interceptorDestination "AutoHotkey32.exe") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "SaveAsInterceptor\saveas_xps.ahk") -Destination $interceptorDestination -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\install.ps1") -Destination $Output -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\uninstall.ps1") -Destination $Output -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\uninstall.cmd") -Destination $Output -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\setup.cmd") -Destination $Output -Force

$settingsPath64 = Join-Path $publish64 "appsettings.json"
$settings64 = Get-Content -LiteralPath $settingsPath64 -Raw | ConvertFrom-Json
$settings64.XpsToPdf.GhostXpsPath = 'C:\Program Files\TytanXpsToPdf\GhostXPS\gxpswin64.exe'
$settings64 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsPath64 -Encoding utf8

$settingsPath32 = Join-Path $publish32 "appsettings.json"
$settings32 = Get-Content -LiteralPath $settingsPath32 -Raw | ConvertFrom-Json
$settings32.XpsToPdf.GhostXpsPath = 'C:\Program Files\TytanXpsToPdf\GhostXPS\gxpswin32.exe'
$settings32 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsPath32 -Encoding utf8

Write-Host "Package created at: $Output"
$zipPath = Join-Path $PSScriptRoot "TytanXpsToPdf-package.zip"
$zipStaging = Join-Path $env:TEMP ("TytanXpsToPdf-zip-" + [guid]::NewGuid().ToString("N"))
$zipRoot = Join-Path $zipStaging "TytanXpsToPdf"
New-Item -ItemType Directory -Force -Path $zipRoot | Out-Null
Copy-Item -Path (Join-Path $Output "*") -Destination $zipRoot -Recurse -Force
Compress-Archive -Path $zipRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
Remove-Item -LiteralPath $zipStaging -Recurse -Force
Write-Host "ZIP created at: $zipPath"
