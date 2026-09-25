# XpsToPdfService — Installation and User Guide

## 1. Package contents

The package automates:

```text
Tytan SQL -> Microsoft XPS Document Writer -> AutoHotkey -> XpsToPdfService -> GhostXPS -> PDF
```

It includes both service builds (`service-x64` and `service-x86`), both
GhostXPS builds (`GhostXPS-x64` and `GhostXPS-x86`), both AutoHotkey builds,
`saveas_xps.ahk`, and click-based setup and removal scripts.
GhostXPS and AutoHotkey do not need to be installed separately.

## 2. Requirements

- Windows 10 or Windows 11, 32-bit or 64-bit.
- Administrator permissions during installation.
- Tytan SQL/Biling SQL and Microsoft XPS Document Writer.

The installer detects the operating-system architecture automatically.

## 3. Installation

1. Extract `XpsToPdfService-package.zip`.
2. Double-click `setup.cmd` and accept the administrator prompt.
For a manual administrator installation, open PowerShell as administrator and
change to the extracted directory:

```powershell
cd "C:\Users\<user>\Downloads\XpsToPdfService-package"
```

No PowerShell knowledge is required for the click-based method. The CMD window
displays the result and waits for a key before closing.

For the manual method, allow scripts for the current PowerShell session:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

Run the installer:

```powershell
.\install.ps1
```

Expected result:

```text
XpsToPdfService installed successfully.
```

The installer stops old service and AutoHotkey processes before copying files,
so reinstallations do not require manual process cleanup.

## 4. Installed layout

The program is installed in:

```text
C:\Program Files\XpsToPdfService
```

The installer creates:

```text
C:\XPS_OUT
C:\PDF
```

The Windows service is registered as `XpsToPdfService`, starts automatically
with delayed start, and has automatic recovery enabled.

AutoHotkey is started immediately and a launcher is placed in the interactive
user's Startup folder:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\XpsToPdfService-AutoHotkey.cmd
```

## 5. Configuration

Configuration is stored in:

```text
C:\Program Files\XpsToPdfService\appsettings.json
```

Default values:

```json
{
  "XpsToPdf": {
    "XpsFolder": "C:\\XPS_OUT",
    "PdfFolder": "C:\\PDF",
    "GhostXpsPath": "C:\\Program Files\\XpsToPdfService\\GhostXPS\\gxpswin64.exe"
  }
}
```

Normally no changes are required. The installer uses `gxpswin64.exe` on
64-bit Windows and `gxpswin32.exe` on 32-bit Windows. Neither `gswin64c.exe`
nor `gswin32c.exe` is required.

## 6. Verify the installation

Run:

```powershell
Get-Service XpsToPdfService
Get-Process AutoHotkey64
```

The service should show `Running` and the AutoHotkey process should exist.

Print one document from Tytan SQL. The expected output is:

```text
C:\XPS_OUT\document-name.xps
C:\PDF\document-name.pdf
```

The document name is read from Tytan SQL's `Printing` window. The XPS save dialog
is handled invisibly.

The service log is:

```text
C:\XPS_OUT\xpstoservice.log
```

The interceptor log is:

```text
C:\XPS_OUT\saveas-interceptor.log
```

## 7. Troubleshooting

If the service is stopped, run PowerShell as administrator:

```powershell
Start-Service XpsToPdfService
```

If AutoHotkey is not running, verify that these files exist:

```text
C:\Program Files\XpsToPdfService\SaveAsInterceptor\AutoHotkey64.exe
C:\Program Files\XpsToPdfService\SaveAsInterceptor\saveas_xps.ahk
```

If the Startup launcher is missing, run `install.ps1` again as administrator.

If a name is not immediately available, AutoHotkey keeps the hidden save
dialog open and retries for up to 15 seconds. It cancels the dialog only after
that timeout.

If GhostXPS is not found, verify:

```text
C:\Program Files\XpsToPdfService\GhostXPS\gxpswin64.exe
```

and check `GhostXpsPath` in `appsettings.json`.

## 9. Uninstallation

For a one-click removal, double-click `uninstall.cmd` and accept the
administrator prompt. The window displays the result and waits for a key.

For a technical-admin removal, use an elevated PowerShell window:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\uninstall.ps1
```

The uninstaller removes the service, program files and Startup launcher, but
preserves `C:\XPS_OUT` and `C:\PDF`.
