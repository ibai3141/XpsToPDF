param(
    [string]$Output = (Join-Path $PSScriptRoot "package"),
    [string]$GhostXpsSource = "C:\Users\Ibai\Downloads\ghostxps-10.08.0-win64\ghostxps-10.08.0-win64",
    [string]$AutoHotkeySource = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$AutoHotkey32Source = "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$publish = Join-Path $Output "service"
$ghostDestination = Join-Path $Output "GhostXPS"
$interceptorDestination = Join-Path $Output "SaveAsInterceptor"

Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Output, $ghostDestination, $interceptorDestination | Out-Null

dotnet publish (Join-Path $projectRoot "XpsToPdfService.csproj") `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $publish

if (-not (Test-Path -LiteralPath (Join-Path $GhostXpsSource "gxpswin64.exe"))) {
    throw "GhostXPS was not found at: $GhostXpsSource"
}
if (-not (Test-Path -LiteralPath $AutoHotkeySource)) {
    throw "AutoHotkey was not found at: $AutoHotkeySource"
}
if (-not (Test-Path -LiteralPath $AutoHotkey32Source)) {
    throw "32-bit AutoHotkey was not found at: $AutoHotkey32Source"
}

Copy-Item -Path (Join-Path $GhostXpsSource "*") -Destination $ghostDestination -Recurse -Force
Copy-Item -LiteralPath $AutoHotkeySource -Destination (Join-Path $interceptorDestination "AutoHotkey64.exe") -Force
Copy-Item -LiteralPath $AutoHotkey32Source -Destination (Join-Path $interceptorDestination "AutoHotkey32.exe") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "SaveAsInterceptor\saveas_xps.ahk") -Destination $interceptorDestination -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\install.ps1") -Destination $Output -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\uninstall.ps1") -Destination $Output -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "Installer\setup.cmd") -Destination $Output -Force

$settingsPath = Join-Path $publish "appsettings.json"
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$settings.XpsToPdf.GhostXpsPath = 'C:\Program Files\XpsToPdfService\GhostXPS\gxpswin64.exe'
$settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsPath -Encoding utf8

Write-Host "Package created at: $Output"
