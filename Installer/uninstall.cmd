@echo off
setlocal

set "UNINSTALLER=%~dp0uninstall.ps1"
set "TYTAN_UNINSTALLER=%UNINSTALLER%"

echo TytanXpsToPdf uninstall
echo.
echo Windows will ask for administrator permission.
echo C:\XPS_OUT and C:\PDF will be preserved.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',('-File ' + [char]34 + $env:TYTAN_UNINSTALLER + [char]34)) -Wait -PassThru; exit $p.ExitCode"
set "UNINSTALL_EXIT=%ERRORLEVEL%"

if not "%UNINSTALL_EXIT%"=="0" (
    rem PowerShell may report a host code after the files were removed.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Service -Name 'TytanXpsToPdf' -ErrorAction SilentlyContinue; if (-not $s -and -not (Test-Path 'C:\Program Files\TytanXpsToPdf')) { exit 0 } else { exit 1 }"
    if not errorlevel 1 goto uninstallation_success
    echo.
    echo Uninstallation failed. Press any key to close.
    pause >nul
    exit /b 1
)

:uninstallation_success
echo.
echo Uninstallation completed successfully.
echo Press any key to close this window.
pause
