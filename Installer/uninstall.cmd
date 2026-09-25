@echo off
setlocal

set "UNINSTALLER=%~dp0uninstall.ps1"

echo TytanXpsToPdf uninstall
echo.
echo Windows will ask for administrator permission.
echo C:XPS_OUT and C:PDF will be preserved.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%UNINSTALLER%') -Wait -PassThru; exit $p.ExitCode"

if errorlevel 1 (
    echo.
    echo Uninstallation failed. Press any key to close.
    pause >nul
    exit /b 1
)

echo.
echo Uninstallation completed successfully.
echo Press any key to close this window.
pause
