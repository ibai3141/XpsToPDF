@echo off
setlocal

set "INSTALLER=%~dp0install.ps1"

echo XpsToPdfService setup
echo.
echo Windows will ask for administrator permission.
echo.
echo Starting the elevated installer. Please wait...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%INSTALLER%') -Wait -PassThru; exit $p.ExitCode"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
echo Elevated installer finished with exit code %INSTALL_EXIT%.

if not "%INSTALL_EXIT%"=="0" (
    echo.
    echo Installation failed. Press any key to close.
    pause >nul
    exit /b 1
)

echo.
echo Installation completed successfully.
echo Press any key to close this window.
pause
