# TytanXpsToPdf — Client Installation Guide

## What is included

The package connects Tytan SQL printing to PDF creation. Microsoft XPS
Document Writer, GhostXPS and AutoHotkey are included; nothing else must be
installed separately.

## Requirements

- Windows 10 or Windows 11 (32-bit or 64-bit).
- Tytan SQL and Microsoft XPS Document Writer already installed.
- Permission to approve one Windows administrator prompt.

## Installation

1. Extract `TytanXpsToPdf-package.zip` into `C:\Program Files\Tytan`.
2. Open `C:\Program Files\Tytan\TytanXpsToPdf`.
3. Double-click **setup.cmd**.
4. Accept the Windows administrator prompt and wait for **Installation
   completed successfully**. Press a key to close the window.

No commands or PowerShell knowledge are required.

## Using the program

Before printing in Tytan SQL, open the printer selection and choose
**Microsoft XPS Document Writer**. This printer must be selected for the
automatic conversion to work. Then print normally; no filename selection is
required.

Files are created here:

- XPS: `C:\XPS_OUT`
- PDF: `C:\PDF`

The PDF uses the same document name as the Tytan SQL print job.

## Uninstallation

Open the installed package folder and double-click **uninstall.cmd**. Accept
the administrator prompt and wait for **Uninstallation completed successfully**.
Existing files in `C:\XPS_OUT` and `C:\PDF` are preserved.

## If help is needed

Please send the document name, approximate print time, and the files
`C:\XPS_OUT\xpstoservice.log` and
`C:\XPS_OUT\saveas-interceptor.log` to technical support.
