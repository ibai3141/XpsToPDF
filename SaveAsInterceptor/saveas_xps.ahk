#Requires AutoHotkey v2.0

SetTitleMatchMode 2
SetControlDelay -1

xpsFolder := "C:\XPS_OUT"
DirCreate xpsFolder

lastDocumentTitle := ""
lastDocumentHwnd := 0

; Recordamos únicamente la ventana real de LibreOffice.
SetTimer RememberDocumentTitle, 50

; Vigilamos el diálogo "Save Print Output As".
SetTimer WatchSaveDialog, 25


RememberDocumentTitle()
{
    global lastDocumentTitle, lastDocumentHwnd

    ; Si ya apareció el diálogo de guardado, NO cambiamos
    ; el nombre que capturamos antes de pulsar Print.
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

    windows := WinGetList()

    for _, hwnd in windows
    {
        try
        {
            class := WinGetClass("ahk_id " hwnd)
            title := Trim(WinGetTitle("ahk_id " hwnd))
        }
        catch
        {
            continue
        }

        ; SOLO LibreOffice.
        if !InStr(class, "SALFRAME")
            continue

        if (title = "")
            continue

        ; Nunca guardar títulos genéricos de impresión.
        if IsGenericPrintJobName(title)
            continue

        ; Guardamos el último documento real de LibreOffice.
        lastDocumentTitle := title
        lastDocumentHwnd := hwnd

        ; Ya encontramos la ventana que nos interesa.
        break
    }
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

    ; No procesar el mismo diálogo varias veces.
    if (hwnd = handledDialog)
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

    ; Quitar extensión XPS si Windows la propone.
    documentName := RegExReplace(
        suggestedFileName,
        "i)(?:\.xps|\.oxps)+$"
    )

    ; Si Windows no propone un nombre útil,
    ; utilizamos el nombre real de LibreOffice.
    if (documentName = "" || IsGenericPrintJobName(documentName))
        documentName := lastDocumentTitle

    ; Si por alguna razón tampoco tenemos nombre de LibreOffice,
    ; no hacemos nada.
    if (documentName = "" || IsGenericPrintJobName(documentName))
    {
        Log(
            "ERROR: no se pudo obtener el nombre real. " .
            "Propuesto='" . suggestedFileName .
            "' | título='" . lastDocumentTitle . "'"
        )
        return
    }

    ; Ejemplo:
    ; Zadanie_skrót_21_września.docx — LibreOffice Writer
    ;
    ; queda:
    ; Zadanie_skrót_21_września.docx
    documentName := RegExReplace(
        documentName,
        "\s+[—-]\s+.*$"
    )

    ; Quitar extensión original.
    documentName := RegExReplace(
        documentName,
        "i)\.(?:docx|doc|odt|rtf|txt|xlsx|xls|ods|pptx|ppt|odp|pdf)$"
    )

    ; Sustituir caracteres no permitidos en Windows.
    invalidPattern := "[<>:" . Chr(34) . "/\\|?*\x00-\x1F]"

    documentName := RegExReplace(
        documentName,
        invalidPattern,
        "_"
    )

    ; Windows no permite terminar con espacio o punto.
    documentName := RTrim(
        documentName,
        " ."
    )

    if (documentName = "")
        return

    ; AQUÍ construimos el nombre definitivo.
    filePath :=
        xpsFolder
        . "\"
        . documentName
        . ".xps"

    Log(
        "Propuesto: '" . suggestedFileName .
        "' | título: '" . lastDocumentTitle .
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

        ; Ya hemos procesado este diálogo.
        handledDialog := hwnd

        ; Ocultamos el diálogo antes de confirmar.
        WinSetTransparent(
            0,
            "ahk_id " hwnd
        )

        ; Guardar.
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

    return normalizedName = "printing"
        || normalizedName = "print"
        || normalizedName = "drukowanie dokumentu"
        || normalizedName = "drukowanie"
        || normalizedName = "save print output as"
        || normalizedName = "zapisz wydruk jako"
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
