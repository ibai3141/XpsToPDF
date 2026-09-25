@echo off
setlocal

rem Relaunch this same script in an elevated CMD window when necessary.
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -Verb RunAs -ArgumentList '/c ""%~f0"" --elevated'"
    exit /b 0
)

set "INSTALLER=%~dp0install.ps1"

echo XpsToPdfService setup
echo.
echo Administrator permissions confirmed.
echo Starting the installer. Please wait...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
echo Installer finished with exit code %INSTALL_EXIT%.

if not "%INSTALL_EXIT%"=="0" (
    echo.
    echo Installation failed.
    echo Press any key to close this window.
    pause >nul
    exit /b 1
)

echo.
echo Installation completed successfully.
echo Press any key to close this window.
pause
