@echo off
setlocal

set "INSTALLER=%~dp0install.ps1"

echo XpsToPdfService setup
echo.
echo Windows will ask for administrator permission.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%INSTALLER%') -Wait -PassThru; exit $p.ExitCode"

if errorlevel 1 (
    echo.
    echo Installation failed. Press any key to close.
    pause >nul
    exit /b 1
)

echo.
echo Installation completed successfully.
pause
