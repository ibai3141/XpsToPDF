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

& sc.exe stop TytanXpsToPdf 2>$null | Out-Null
Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process AutoHotkey32 -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
& sc.exe delete TytanXpsToPdf 2>$null | Out-Null
Remove-Item -LiteralPath $startupLauncher -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue

# Also clean installations created with the previous service name.
& sc.exe stop XpsToPdfService 2>$null | Out-Null
Get-Process XpsToPdfService -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
& sc.exe delete XpsToPdfService 2>$null | Out-Null
Remove-Item -LiteralPath (Join-Path ${env:ProgramFiles} "XpsToPdfService") -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "TytanXpsToPdf uninstalled. C:\XPS_OUT and C:\PDF were preserved."
