#Requires AutoHotkey v2.0

SetTitleMatchMode 2
SetControlDelay -1

xpsFolder := "C:\XPS_OUT"
DirCreate xpsFolder

pendingPrintName := ""

; Monitor the XPS save dialog.
SetTimer WatchSaveDialog, 25

; Capture the document identifier shown by Tytan's modal "Printing" window.
SetTimer CapturePrintingName, 25


WatchSaveDialog()
{
    global xpsFolder, pendingPrintName

    static handledDialog := 0

    hwnd := FindSaveDialog()

    if !hwnd
    {
        handledDialog := 0
        return
    }

    ; Do not process the same dialog more than once.
    if (hwnd = handledDialog)
        return

    ; Hide the dialog immediately. Name lookup and path assignment can take
    ; a moment, and the user must never see the Save Print Output window.
    try
        WinSetTransparent(0, "ahk_id " hwnd)
    catch TargetError
        return

    try
    {
        suggestedPath := Trim(
            ControlGetText(
                "Edit1",
                "ahk_id " hwnd
            )
        )
    }
    catch TargetError
    {
        return
    }

    SplitPath suggestedPath, &suggestedFileName

    ; Tytan's Printing window is the authoritative source for the document name.
    documentName := ""
    if (pendingPrintName != "" && !IsGenericPrintJobName(pendingPrintName))
    {
        documentName := pendingPrintName
        pendingPrintName := ""
        Log("INFO: name obtained from the Printing window: '" . documentName . "'")
    }

    ; Keep the print queue as a technical fallback if the modal window was missed.
    if (documentName = "" || IsGenericPrintJobName(documentName))
    {
        queueName := GetLatestPrintJobDocumentName()
        if (queueName != "" && !IsGenericPrintJobName(queueName))
        {
            documentName := queueName
        }
    }

    if (documentName = "" || IsGenericPrintJobName(documentName))
    {
        Log("ERROR: no document name was obtained from the Printing window or print queue.")
        handledDialog := hwnd
        ControlSend("{Escape}", , "ahk_id " hwnd)
        return
    }

    ; Example:
    ; Zadanie_skrĂłt_21_wrzeĹ›nia.docx â€” LibreOffice Writer
    ;
    ; becomes:
    ; Zadanie_skrĂłt_21_wrzeĹ›nia.docx
    documentName := RegExReplace(
        documentName,
        "\s+[-\x{2013}\x{2014}]\s+.*$"
    )

    ; Remove the original document extension.
    documentName := RegExReplace(
        documentName,
        "i)\.(?:docx|doc|odt|rtf|txt|xlsx|xls|ods|pptx|ppt|odp|pdf)$"
    )

    ; Preserve the name supplied by Tytan or by the source application.

    ; Replace characters that are not valid in Windows filenames.
    invalidPattern := "[<>:" . Chr(34) . "/\\|?*\x00-\x1F]"

    documentName := RegExReplace(
        documentName,
        invalidPattern,
        "_"
    )

    ; Windows filenames cannot end with a space or period.
    documentName := RTrim(
        documentName,
        " ."
    )

    if (documentName = "")
        return

    ; Build the output filename supplied to Microsoft XPS Document Writer.
    filePath := xpsFolder . "\" . documentName . ".xps"

    Log("XPS output: '" . filePath . "'")

    try
    {
        ControlFocus(
            "Edit1",
            "ahk_id " hwnd
        )

        ; The Windows XPS writer defaults to OpenXPS (*.oxps). Select the
        ; classic XPS type explicitly so the saved file has a .xps extension.
        for _, typeName in ["XPS Document (*.xps)", "XPS Document", "*.xps"]
        {
            try
            {
                if ControlChooseString(typeName, "ComboBox2", "ahk_id " hwnd)
                    break
            }
            catch TargetError
            {
                ; The control name differs between Windows versions.
            }
        }

        ; WM_SETTEXT avoids keyboard-layout and stale-clipboard problems.
        ControlSetText(
            filePath,
            "Edit1",
            "ahk_id " hwnd
        )
        ; Allow the dialog control to process WM_SETTEXT without adding a
        ; noticeable delay to every print job.
        Sleep 10

        actualPath := ControlGetText(
            "Edit1",
            "ahk_id " hwnd
        )
        Log("Field after writing: '" . actualPath . "'")

        ; The dialog has now been processed.
        handledDialog := hwnd

        ; Confirm Save.
        ControlSend(
            "{Enter}",
            ,
            "ahk_id " hwnd
        )
    }
    catch TargetError
    {
        handledDialog := 0
    }
}


FindSaveDialog()
{
    titles := [
        "Save Print Output As",
        "Zapisz wydruk jako"
    ]

    for _, title in titles
    {
        hwnd := WinExist(title)

        if hwnd
            return hwnd
    }

    return 0
}


IsGenericPrintJobName(name)
{
    normalizedName := StrLower(
        Trim(name)
    )

    ; File Explorer can become the active window after a print. Its title is
    ; not a document name and must never be used for an output file.
    if RegExMatch(normalizedName, "i)\s-\sfile explorer$")
        return true

    if RegExMatch(normalizedName, "i)^xps_out(?:\s-\s.*)?$")
        return true

    return normalizedName = "printing"
        || normalizedName = "print"
        || normalizedName = "drukowanie dokumentu"
        || normalizedName = "drukowanie dokumentów"
        || normalizedName = "drukowanie dokumentow"
        || normalizedName = "drukowanie"
        || normalizedName = "save print output as"
        || normalizedName = "zapisz wydruk jako"
}


GetLatestPrintJobDocumentName()
{
    latestName := ""
    latestJobId := -1

    try
    {
        wmi := ComObjGet("winmgmts:")
        jobs := wmi.ExecQuery("SELECT Name, Document, JobId FROM Win32_PrintJob")

        for job in jobs
        {
            if !InStr(StrLower(job.Name), "xps")
                continue

            document := Trim(job.Document)
            if (document = "" || IsGenericPrintJobName(document))
                continue

            jobId := Integer(job.JobId)
            if (jobId > latestJobId)
            {
                latestJobId := jobId
                latestName := document
            }
        }
    }
    catch
    {
        return ""
    }

    return RegExReplace(latestName, "i)(?:\.xps|\.oxps)+$", "")
}


CapturePrintingName()
{
    global pendingPrintName

    try
    {
        windows := WinGetList("Printing")
        for _, hwnd in windows
        {
            if !WinExist("ahk_id " hwnd)
                continue

            text := WinGetText("ahk_id " hwnd)
            if (text = "")
                continue

            ; Tytan displays the identifier in a line such as:
            ; "Page 1 of %_2026_000013_20260923_112101037".
            if RegExMatch(text, "im)^\s*Page\s+\d+\s+of\s+(.+?)\s*$", &match)
            {
                candidate := Trim(match[1])
                if (candidate != "" && !IsGenericPrintJobName(candidate))
                    pendingPrintName := candidate
            }
        }
    }
    catch
    {
        return
    }
}

Log(message)
{
    global xpsFolder

    FileAppend(
        FormatTime(
            A_Now,
            "yyyy-MM-dd HH:mm:ss"
        )
        . " "
        . message
        . "`n",
        xpsFolder . "\saveas-interceptor.log",
        "UTF-8"
    )
}
