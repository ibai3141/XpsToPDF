@echo off
setlocal

set "INSTALLER=%~dp0install.ps1"
set "TYTAN_INSTALLER=%INSTALLER%"
set "TYTAN_MARKER=%~dp0.install-success"

echo TytanXpsToPdf setup
echo.
echo Windows will ask for administrator permission.
echo Starting the elevated installer. Please wait...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Normal -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',('-File ' + [char]34 + $env:TYTAN_INSTALLER + [char]34)) -PassThru; for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 1; $s = Get-Service -Name 'TytanXpsToPdf' -ErrorAction SilentlyContinue; if ((Test-Path -LiteralPath $env:TYTAN_MARKER) -and $s -and $s.Status -eq 'Running') { exit 0 }; if ($p.HasExited) { exit $p.ExitCode } }; exit 1"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
echo Elevated installer finished with exit code %INSTALL_EXIT%.

if not "%INSTALL_EXIT%"=="0" (
    rem PowerShell can return a non-zero host code even after the service
    rem was installed successfully. Verify the real service state first.
    if exist "%~dp0.install-success" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Service -Name 'TytanXpsToPdf' -ErrorAction SilentlyContinue; if ($s -and $s.Status -eq 'Running') { exit 0 } else { exit 1 }"
        if not errorlevel 1 goto installation_success
    )
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
pause >nul
endlocal
exit /b 0
