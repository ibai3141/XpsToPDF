# XPS to PDF Service — Current Flow

## Purpose

```text
Tytan / Biling SQL
        |
        v
Microsoft XPS Document Writer
        |
        v
SaveAs Interceptor (AutoHotkey)
        |
        v
C:\XPS_OUT\document-name.xps
        |
        v
XpsToPdfService (Worker.cs)
        |
        v
GhostXPS (gxpswin64.exe)
        |
        v
C:\PDF\document-name.pdf
```

Tytan/Biling SQL remains closed-source. This project intercepts the XPS save
operation and converts the resulting XPS/OpenXPS package to PDF.

## 1. AutoHotkey interceptor

File: `SaveAsInterceptor\saveas_xps.ahk`

The interceptor runs in the interactive user session because a Windows service
cannot directly control desktop windows.

### Obtaining the document name

Tytan displays the real print identifier in its modal `Printing` window:

```text
Page 1 of %_2026_000006_20260923_123547644
```

The script reads that window and extracts the value after `Page 1 of`:

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

The name is then used when the XPS save dialog appears. The fallback order is:

1. Name proposed in the XPS dialog.
2. `DocumentName` from the Windows print queue.
3. Name captured from Tytan's `Printing` window.
4. Source application window title as a last resort.

The save dialog is made transparent, filled automatically, and confirmed:

```autohotkey
WinSetTransparent(0, "ahk_id " hwnd)
ControlSetText(filePath, "Edit1", "ahk_id " hwnd)
ControlSend("{Enter}", , "ahk_id " hwnd)
```

The script selects classic XPS when available, preventing the driver from
defaulting to `.oxps`.

## 2. XPS service

File: `Worker.cs`

The service watches `C:\XPS_OUT` and accepts both `.xps` and `.oxps` files:

```csharp
if (!e.FullPath.EndsWith(".xps", StringComparison.OrdinalIgnoreCase) &&
    !e.FullPath.EndsWith(".oxps", StringComparison.OrdinalIgnoreCase))
    return;
```

Before conversion, it verifies that the file exists, is non-empty, can be
opened exclusively, and remains stable across two quick checks. This prevents
GhostXPS from reading an incomplete package.

GhostXPS is started with the `pdfwrite` device:

```csharp
psi.ArgumentList.Add("-dSAFER");
psi.ArgumentList.Add("-dBATCH");
psi.ArgumentList.Add("-dNOPAUSE");
psi.ArgumentList.Add("-sDEVICE=pdfwrite");
psi.ArgumentList.Add($"-sOutputFile={ghostOutputFile}");
psi.ArgumentList.Add(xpsFile);
```

### Percent signs in names

Tytan identifiers can begin with `%`. GhostXPS treats `%` in an output path as
a pattern marker, so it is escaped only for the process argument:

```csharp
string ghostOutputFile = temporaryPdfFile.Replace("%", "%%");
```

The actual filename on disk remains unchanged.

### Temporary PDF

GhostXPS first writes `document.tmp.pdf`. Only after exit code `0` and a file
existence check does the service publish the final PDF:

```csharp
File.Move(temporaryPdfFile, pdfFile, true);
```

This prevents incomplete PDFs from appearing in `C:\PDF`.

## 3. Reliability protections

Two service processes could race over the same temporary PDF. `Worker.cs` uses
a named mutex so only one instance watches the folder:

```csharp
using Mutex instanceMutex =
    new(false, "Global\\XpsToPdfService");
```

Each job reports service-side timing:

```text
XPS job time: 2.44 s | C:\XPS_OUT\document.xps
```

This measures XPS readiness plus GhostXPS conversion; it does not include all
time spent by Tytan before the XPS is created.

## 4. Problems corrected

- Replaced the incorrect `gswin64c.exe` XPS invocation with `gxpswin64.exe`.
- Added readiness checks for XPS files still being written.
- Added support for both `.xps` and `.oxps`.
- Prevented stale dialog values and repeated `.xps` extensions.
- Selected the classic XPS format explicitly.
- Escaped `%` names for GhostXPS.
- Added a single-instance mutex to prevent duplicate conversion.
- Added timing diagnostics.

## 5. Performance limits

The service no longer has an explicit conversion thread pool. New watcher
events are handled without blocking detection, but Tytan normally creates XPS
jobs sequentially. More threads therefore cannot accelerate the upstream step:

```text
Tytan creates XPS 1 -> XPS 2 -> XPS 3
```

The main remaining cost is Microsoft XPS Document Writer creating each XPS,
followed by GhostXPS rendering. BullZip is faster because it generates PDF
directly and avoids the intermediate XPS stage.

## 6. Source integration

The ideal source-side code would be:

```csharp
printDocument.DocumentName = filename;
printDocument.Print();
```

That code is not available in this repository because Tytan/Biling SQL is
closed-source. The interceptor therefore reads the identifier exposed by the
`Printing` window and uses the source window title only as a fallback.
