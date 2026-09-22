#Requires AutoHotkey v2.0
SetTitleMatchMode 2

for title in ["Save Print Output As", "Zapisz wydruk jako"]
{
    if (hwnd := WinExist(title))
    {
        WinSetTransparent "Off", "ahk_id " hwnd
        ControlSend "{Esc}", , "ahk_id " hwnd
        break
    }
}
