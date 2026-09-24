$ErrorActionPreference = "Stop"

$installRoot = Join-Path ${env:ProgramFiles} "XpsToPdfService"
$serviceSource = Join-Path $PSScriptRoot "service\XpsToPdfService.exe"
$serviceTarget = Join-Path $installRoot "XpsToPdfService.exe"
$ahkTarget = Join-Path $installRoot "SaveAsInterceptor\AutoHotkey64.exe"
$scriptTarget = Join-Path $installRoot "SaveAsInterceptor\saveas_xps.ahk"
$taskName = "XpsToPdfService - SaveAs Interceptor"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this installer from an elevated PowerShell window."
}

New-Item -ItemType Directory -Force -Path $installRoot, "$installRoot\SaveAsInterceptor", "C:\XPS_OUT", "C:\PDF" | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot "service\*") -Destination $installRoot -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "GhostXPS") -Destination $installRoot -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "SaveAsInterceptor\*") -Destination "$installRoot\SaveAsInterceptor" -Recurse -Force

& sc.exe stop XpsToPdfService 2>$null | Out-Null
& sc.exe delete XpsToPdfService 2>$null | Out-Null
& sc.exe create XpsToPdfService binPath= "`"$serviceTarget`"" start= auto DisplayName= "XPS to PDF Service" | Out-Null
& sc.exe description XpsToPdfService "Converts Microsoft XPS Document Writer output to PDF." | Out-Null
& sc.exe failure XpsToPdfService reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
& sc.exe failureflag XpsToPdfService 1 | Out-Null

$action = New-ScheduledTaskAction -Execute $ahkTarget -Argument "`"$scriptTarget`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$taskSettings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

& sc.exe start XpsToPdfService | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "XpsToPdfService installed successfully."
