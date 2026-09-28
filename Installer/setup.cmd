@echo off
setlocal

set "INSTALLER=%~dp0install.ps1"

echo TytanXpsToPdf setup
echo.
echo Windows will ask for administrator permission.
echo Starting the elevated installer. Please wait...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Normal -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%INSTALLER%') -Wait -PassThru; exit $p.ExitCode"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
echo Elevated installer finished with exit code %INSTALL_EXIT%.

if not "%INSTALL_EXIT%"=="0" (
    rem PowerShell can return a non-zero host code even after the service
    rem was installed successfully. Verify the real service state first.
    sc.exe query TytanXpsToPdf | find /I "RUNNING" >nul
    if not errorlevel 1 goto installation_success
    echo.
    echo Installation failed.
    echo Press any key to close this window.
    pause >nul
    exit /b 1
)

:installation_success
echo.
echo Installation completed successfully.
echo Press any key to close this window.
pause
