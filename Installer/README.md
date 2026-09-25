# XpsToPdfService installation package

## Build the package

Run PowerShell from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\Installer\build-package.ps1
```

The build publishes a self-contained `win-x64` service and copies GhostXPS
and AutoHotkey into `Installer\package`.

If GhostXPS is installed elsewhere, provide its directory explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\Installer\build-package.ps1 `
  -GhostXpsSource "C:\Path\To\ghostxps" `
  -AutoHotkeySource "C:\Path\To\AutoHotkey64.exe"
```

## Install on a client machine

For a simple click-based installation, double-click `setup.cmd`. It requests
administrator permission and runs the installer automatically.

The PowerShell method remains available for technical administrators:

Extract the package and run PowerShell as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The script installs the service under `C:\Program Files\XpsToPdfService`,
creates `C:\XPS_OUT` and `C:\PDF`, registers the Windows service, and starts
the AutoHotkey interceptor at interactive logon.

## Uninstall

Run as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The uninstall script removes the service and installed program files. It keeps
`C:\XPS_OUT` and `C:\PDF` so generated documents are not deleted.
