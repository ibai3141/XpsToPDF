#Requires AutoHotkey v2.0

SetTitleMatchMode 2
SetControlDelay -1

xpsFolder := "C:\XPS_OUT"
DirCreate xpsFolder

lastDocumentTitle := ""
lastDocumentHwnd := 0

; Track the source document window and monitor the save dialog.
SetTimer RememberDocumentTitle, 50

; Track the source document window and monitor the save dialog.
SetTimer WatchSaveDialog, 25


RememberDocumentTitle()
{
    global lastDocumentTitle, lastDocumentHwnd

    ; Keep the title captured before the save dialog appeared.
    if FindSaveDialog()
        return

    ; Use the application active immediately before printing. The old code
    ; below searched only LibreOffice windows, so Tytan reused an old title.
    activeHwnd := WinExist("A")
    if !activeHwnd
        return
    try
    {
        activeClass := WinGetClass("ahk_id " activeHwnd)
        activeTitle := Trim(WinGetTitle("ahk_id " activeHwnd))
    }
    catch
    {
        return
    }
    if (activeTitle != "" && activeClass != "#32770" && !IsGenericPrintJobName(activeTitle)
        && !InStr(activeTitle, "AutoHotkey") && !InStr(activeTitle, "XpsToPdfService"))
    {
        lastDocumentTitle := activeTitle
        lastDocumentHwnd := activeHwnd
    }
    return
}


WatchSaveDialog()
{
    global xpsFolder, lastDocumentTitle

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

    ; Remove the XPS extension if Windows supplies one.
    documentName := RegExReplace(
        suggestedFileName,
        "i)(?:\.xps|\.oxps)+$"
    )

    ; If Windows does not provide a useful name, use the print queue once.
    if (documentName = "" || IsGenericPrintJobName(documentName))
    {
        queueName := GetLatestPrintJobDocumentName()
        if (queueName != "" && !IsGenericPrintJobName(queueName))
        {
            documentName := queueName
        }
        else
            documentName := lastDocumentTitle
    }

    ; If no source-document name is available,
    ; do nothing.
    if (documentName = "" || IsGenericPrintJobName(documentName))
    {
        Log(
            "ERROR: no se pudo obtener el nombre real. " .
            "Propuesto='" . suggestedFileName .
            "' | tĂ­tulo='" . lastDocumentTitle . "'"
        )
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

    Log(
        "Propuesto: '" . suggestedFileName .
        "' | tĂ­tulo: '" . lastDocumentTitle .
        "' | XPS: '" . filePath . "'"
    )

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
        Sleep 150

        actualPath := ControlGetText(
            "Edit1",
            "ahk_id " hwnd
        )
        Log("Campo tras escribir: '" . actualPath . "'")

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
