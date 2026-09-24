$ErrorActionPreference = "Stop"
$installRoot = Join-Path ${env:ProgramFiles} "XpsToPdfService"
$taskName = "XpsToPdfService - SaveAs Interceptor"

& sc.exe stop XpsToPdfService 2>$null | Out-Null
& sc.exe delete XpsToPdfService 2>$null | Out-Null
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "XpsToPdfService uninstalled. C:\XPS_OUT and C:\PDF were preserved."
