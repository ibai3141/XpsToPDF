# XpsToPdfService — Technical Documentation

## Architecture

```text
Tytan -> Microsoft XPS Document Writer -> AutoHotkey -> C:\XPS_OUT\*.xps
      -> XpsToPdfService -> GhostXPS -> C:\PDF\*.pdf
```

Tytan/Biling SQL is external and closed-source. The project contains an
interactive AutoHotkey interceptor and a .NET Windows service because a
Windows service cannot control desktop windows in the user's session.

## Repository components

```text
Worker.cs                         Service and XPS-to-PDF pipeline
Program.cs                        Generic host and Windows-service integration
appsettings.json                  Runtime paths
SaveAsInterceptor/saveas_xps.ahk  Interactive dialog automation
Installer/build-package.ps1      Self-contained package builder
Installer/install.ps1             Installation and recovery configuration
Installer/uninstall.ps1           Removal script
README.md                         Short technical overview
INSTALLATION_GUIDE.md             Client installation guide
```

## AutoHotkey interceptor

The script runs in the interactive user session. It creates `C:\XPS_OUT` and
polls two things:

```autohotkey
SetTimer WatchSaveDialog, 25
SetTimer CapturePrintingName, 25
```

Tytan's `Printing` window contains the authoritative identifier, for example:

```text
Page 1 of %_2026_000006_20260923_123547644
```

The script reads the window text and extracts the value after `Page 1 of`:

```autohotkey
windows := WinGetList("Printing")
text := WinGetText("ahk_id " hwnd)

if RegExMatch(text, "im)^\s*Page\s+\d+\s+of\s+(.+?)\s*$", &match)
    pendingPrintName := Trim(match[1])
```

The XPS dialog itself is kept alive but invisible. Its controls are filled and
confirmed automatically:

```autohotkey
WinSetTransparent(0, "ahk_id " hwnd)
ControlSetText(filePath, "Edit1", "ahk_id " hwnd)
ControlSend("{Enter}", , "ahk_id " hwnd)
```

The script selects `XPS Document (*.xps)` when available, preventing the
driver from selecting `.oxps`. The Windows print queue (`Win32_PrintJob`) is
retained as a technical fallback if the `Printing` window is missed. The
application window title and the XPS-proposed name are not used as names.

## Worker service

### Configuration

`Worker` receives `IConfiguration` and reads paths from `appsettings.json`:

```csharp
public Worker(IConfiguration configuration)
{
    xpsFolder = configuration["XpsToPdf:XpsFolder"] ?? @"C:\XPS_OUT";
    pdfFolder = configuration["XpsToPdf:PdfFolder"] ?? @"C:\PDF";
    ghostXps = configuration["XpsToPdf:GhostXpsPath"]
        ?? @"C:\Program Files\GhostXPS\gxpswin64.exe";
}
```

The installer writes the final path:

```json
{
  "XpsToPdf": {
    "XpsFolder": "C:\\XPS_OUT",
    "PdfFolder": "C:\\PDF",
    "GhostXpsPath": "C:\\Program Files\\XpsToPdfService\\GhostXPS\\gxpswin64.exe"
  }
}
```

`gswin64c.exe` is not used. The required executable is `gxpswin64.exe`.

### File watcher and duplicate protection

The service watches all names because Microsoft XPS may produce `.xps` or
`.oxps`:

```csharp
watcher.Path = xpsFolder;
watcher.Filter = "*.*";
watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite;
watcher.Created += OnXpsCreated;
```

The handler filters extensions and uses a concurrent dictionary to avoid
processing the same path twice. A named global mutex prevents two service
processes from watching the folder at the same time:

```csharp
using Mutex instanceMutex = new(false, "Global\\XpsToPdfService");
if (!instanceMutex.WaitOne(0))
    return;
```

### XPS readiness

The `Created` event may occur while the file is still being written. The
service requires a non-empty file, exclusive access, and two stable size/write
time checks. Polling occurs every 100 ms for up to 60 attempts:

```csharp
using FileStream stream = new(
    filePath, FileMode.Open, FileAccess.Read, FileShare.None);
```

This prevents GhostXPS from reading an incomplete package.

### GhostXPS process

The process is started without a shell and with `ArgumentList`:

```csharp
ProcessStartInfo psi = new()
{
    FileName = ghostXps,
    UseShellExecute = false,
    CreateNoWindow = true,
    RedirectStandardOutput = true,
    RedirectStandardError = true
};
psi.ArgumentList.Add("-dSAFER");
psi.ArgumentList.Add("-dBATCH");
psi.ArgumentList.Add("-dNOPAUSE");
psi.ArgumentList.Add("-sDEVICE=pdfwrite");
psi.ArgumentList.Add($"-sOutputFile={ghostOutputFile}");
psi.ArgumentList.Add(xpsFile);
```

### Percent-sign handling

Tytan identifiers can begin with `%`. GhostXPS treats `%` in output paths as
a pattern marker. The service escapes it only for the process argument:

```csharp
string ghostOutputFile = temporaryPdfFile.Replace("%", "%%");
```

The actual filename on disk remains unchanged.

### Safe PDF publication

GhostXPS first writes `<name>.tmp.pdf`. The service publishes the final file
only after exit code `0` and a file existence check:

```csharp
if (process.ExitCode != 0 || !File.Exists(temporaryPdfFile))
    return;

File.Move(temporaryPdfFile, pdfFile, true);
```

This prevents incomplete PDFs from appearing as final output.

## Host and installer

`Program.cs` enables Windows-service hosting:

```csharp
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "XpsToPdfService";
});
builder.Services.AddHostedService<Worker>();
```

`build-package.ps1` publishes a self-contained `win-x64` executable and copies
GhostXPS, AutoHotkey, the interceptor, and install scripts into the package.
`install.ps1` stops old processes, copies files to `C:\Program Files`, creates
the output directories, registers delayed automatic service startup and
recovery, and creates a correctly quoted Startup launcher for the interactive
user. `uninstall.ps1` removes installed components but preserves output files.

The launcher must use the empty `start` window title before quoted paths:

```cmd
start "" "C:\Program Files\XpsToPdfService\SaveAsInterceptor\AutoHotkey64.exe" "C:\Program Files\XpsToPdfService\SaveAsInterceptor\saveas_xps.ahk"
```

## Failure history and fixes

| Symptom | Root cause | Fix |
|---|---|---|
| Empty PDF | Incomplete XPS or wrong interpreter | readiness checks and `gxpswin64.exe` |
| `.oxps` extension | OpenXPS selected | select classic XPS explicitly |
| Wrong document name | stale title/dialog value | read Tytan `Printing` identifier |
| GhostXPS exit code 1 | `%` interpreted as pattern | pass `%%` to GhostXPS |
| Temporary PDF missing | duplicate service processes | global mutex and cleanup |
| Build file locked | running executable | stop service/process before copy |
| AutoHotkey missing after reboot | bad Startup quoting/profile | user-specific launcher and correct `start` syntax |

## Performance and maintenance

The service normally spends 2–5 seconds per XPS job. Tytan creates jobs
sequentially, so extra conversion threads do not improve a batch when no XPS
jobs are waiting. The main cost is Microsoft XPS generation, followed by
GhostXPS rendering.

Maintenance checklist:

- Keep `GhostXpsPath` synchronized with `gxpswin64.exe`.
- Test names containing `%` and ordinary invoice names.
- Test a multi-document Tytan print.
- Verify service and AutoHotkey after a Windows restart.
- Never run multiple service instances during development.
- Rebuild the ZIP after changing binaries or installer scripts.
- Preserve GhostXPS license files when redistributing its directory.
