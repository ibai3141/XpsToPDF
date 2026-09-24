# XpsToPdfService — Installation and User Guide

## 1. Package contents

The package automates:

```text
Tytan -> Microsoft XPS Document Writer -> AutoHotkey -> XpsToPdfService -> GhostXPS -> PDF
```

It includes the Windows service, `gxpswin64.exe`, `AutoHotkey64.exe`,
`saveas_xps.ahk`, `appsettings.json`, `install.ps1`, and `uninstall.ps1`.
GhostXPS and AutoHotkey do not need to be installed separately.

## 2. Requirements

- Windows 10 or Windows 11, 64-bit.
- Administrator permissions during installation.
- Tytan/Biling SQL and Microsoft XPS Document Writer.

The package is published for `win-x64` and is not compatible with 32-bit
Windows.

## 3. Installation

1. Extract `XpsToPdfService-package.zip`.
2. Open **PowerShell as administrator**.
3. Change to the extracted directory:

```powershell
cd "C:\Users\<user>\Downloads\XpsToPdfService-package"
```

4. Allow scripts for the current PowerShell session:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

5. Run the installer:

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

Normally no changes are required. The service uses `gxpswin64.exe`;
`gswin64c.exe` is not required.

## 6. Verify the installation

Run:

```powershell
Get-Service XpsToPdfService
Get-Process AutoHotkey64
```

The service should show `Running` and the AutoHotkey process should exist.

Print one document from Tytan. The expected output is:

```text
C:\XPS_OUT\document-name.xps
C:\PDF\document-name.pdf
```

The document name is read from Tytan's `Printing` window. The XPS save dialog
is handled invisibly.

## 7. Normal operation

After installation, the user only selects **Print** / **Drukuj** in Tytan.
No PowerShell command is required during normal operation.

## 8. Troubleshooting

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

If GhostXPS is not found, verify:

```text
C:\Program Files\XpsToPdfService\GhostXPS\gxpswin64.exe
```

and check `GhostXpsPath` in `appsettings.json`.

## 9. Uninstallation

From an elevated PowerShell window in the extracted package directory:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\uninstall.ps1
```

The uninstaller removes the service, program files and Startup launcher, but
preserves `C:\XPS_OUT` and `C:\PDF`.
