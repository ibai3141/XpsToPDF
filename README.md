# XpsToPdfService

Automated Microsoft XPS Document Writer to PDF conversion for Tytan/Biling SQL
printing workflows.

```text
Tytan / Biling SQL
        |
        v
Microsoft XPS Document Writer
        |
        v
AutoHotkey SaveAs Interceptor
        |
        v
C:\XPS_OUT\document-name.xps
        |
        v
XpsToPdfService + GhostXPS
        |
        v
C:\PDF\document-name.pdf
```

Tytan/Biling SQL remains an external, closed-source application. This
repository contains the interceptor, conversion service, and deployment
scripts required to automate its XPS output.

## Features

- Uses Microsoft XPS Document Writer as required by the workflow.
- Reads the real document identifier from Tytan's `Printing` or `Drukowanie` window.
- Handles the XPS save dialog invisibly.
- Supports `.xps` and `.oxps` input.
- Converts with `gxpswin64.exe` and the `pdfwrite` device.
- Preserves names containing `%`.
- Publishes PDFs through a temporary file to prevent partial output.
- Prevents duplicate service instances with a global mutex.
- Starts automatically after Windows boot and user logon.
- Includes a self-contained `win-x64` installer package.

## Requirements

- Windows 10 or Windows 11, 64-bit.
- Microsoft XPS Document Writer.
- Tytan/Biling SQL configured to print.
- Administrator permissions for installation.

The package includes GhostXPS and both AutoHotkey architectures; they do not
need to be installed separately. `gswin64c.exe` is not used. The XPS
interpreter is `gxpswin64.exe`.

## Installation

Build the package from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\Installer\build-package.ps1
```

The output is created in `Installer\package`. A ZIP package is also generated
as `Installer\XpsToPdfService-package.zip`.

On the client computer, extract the ZIP and run PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

The installer:

1. Stops previous service and AutoHotkey processes.
2. Installs the application under `C:\Program Files\XpsToPdfService`.
3. Copies GhostXPS and AutoHotkey.
4. Creates `C:\XPS_OUT` and `C:\PDF`.
5. Registers delayed automatic service startup and recovery.
6. Creates an interactive-user Startup launcher for AutoHotkey.

See [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) for the client procedure.

## Runtime configuration

The installed service reads `appsettings.json`:

```json
{
  "XpsToPdf": {
    "XpsFolder": "C:\\XPS_OUT",
    "PdfFolder": "C:\\PDF",
    "GhostXpsPath": "C:\\Program Files\\XpsToPdfService\\GhostXPS\\gxpswin64.exe"
  }
}
```

Paths can be changed without recompiling. Restart the service after changing
the file.

## Verify a client installation

```powershell
Get-Service XpsToPdfService
Get-Process AutoHotkey64
```

Print a test document from Tytan and verify:

```text
C:\XPS_OUT\<document-name>.xps
C:\PDF\<document-name>.pdf
```

The normal user workflow requires no PowerShell commands.

## Development

Build the service:

```powershell
dotnet build
```

Run it interactively during development:

```powershell
dotnet run
```

Stop an interactive instance with `Ctrl+C`. If a background process is holding
the executable, stop only this service:

```powershell
Get-Process XpsToPdfService | Stop-Process -Force
```

Restart the AutoHotkey script after changing it:

```text
SaveAsInterceptor\saveas_xps.ahk
```

Do not run multiple service instances; the global mutex deliberately prevents
duplicate watchers and conversions.

## Name resolution

The interceptor uses the following order:

1. Tytan's `Printing` or `Drukowanie` window (`Page 1 of ...`).
2. `Win32_PrintJob.Document` as a technical fallback.
3. If neither source is available, the save is cancelled rather than creating
   a misleading filename.

The application window title and the XPS dialog's proposed filename are not
used as document names.

### Exact name extraction

Tytan opens a modal window titled `Printing` or `Drukowanie`. Its text contains
the real document identifier. English installations show:

```text
Page 1 of %_2026_000006_20260923_123547644
```

Polish installations show the equivalent:

```text
Strona 1 z %_2025_000002_20260924_143709875
```

`SaveAsInterceptor\saveas_xps.ahk` reads that window with AutoHotkey:

```autohotkey
windows := WinGetList("Printing")
text := WinGetText("ahk_id " hwnd)

if RegExMatch(
    text,
    "im)^\s*Page\s+\d+\s+of\s+(.+?)\s*$",
    &match
)
    pendingPrintName := Trim(match[1])
```

The captured value becomes the base filename:

```text
%_2026_000006_20260923_123547644
        |
        +-- C:\XPS_OUT\%_2026_000006_20260923_123547644.xps
        +-- C:\PDF\%_2026_000006_20260923_123547644.pdf
```

The save-dialog path is filled automatically with the captured name:

```autohotkey
filePath := xpsFolder . "\\" . documentName . ".xps"
ControlSetText(filePath, "Edit1", "ahk_id " hwnd)
ControlSend("{Enter}", , "ahk_id " hwnd)
```

## Conversion safety

The service waits until the XPS is non-empty, exclusively readable, and stable
before conversion. GhostXPS writes `<name>.tmp.pdf`; only a successful exit
code and an existing temporary file allow publication as `<name>.pdf`.

Names beginning with `%` are escaped only in the GhostXPS argument:

```csharp
string ghostOutputFile = temporaryPdfFile.Replace("%", "%%");
```

The filename on disk remains unchanged.

## Documentation

- [Client installation guide](INSTALLATION_GUIDE.md)
- [Technical documentation](TECHNICAL_DOCUMENTATION.md)
- [Technical documentation (Word)](XPS_TO_PDF_SERVICE_DOCUMENTATION.docx)
- [Client installation guide (Word)](XpsToPdfService_Installation_Guide.docx)

## Uninstallation

From an elevated PowerShell window in the extracted package directory:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\uninstall.ps1
```

The uninstaller removes installed program files, the Windows service, and the
AutoHotkey Startup launcher. It preserves `C:\XPS_OUT` and `C:\PDF`.

## Licensing and redistribution

Tytan/Biling SQL is not part of this repository. When redistributing the
package, preserve the license files included with GhostXPS and AutoHotkey and
review their respective redistribution terms.
