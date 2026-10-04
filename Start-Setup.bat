@echo off
setlocal DisableDelayedExpansion
title Fresh Windows Setup
if not exist "%~dp0Fresh-Windows-Setup.ps1" (
    echo Missing Fresh-Windows-Setup.ps1. Keep the BAT and PS1 in the same folder.
    pause
    exit /b 2
)
set "setupPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%setupPowerShell%" -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Requesting administrator access. The setup opens in another window.
    set "setupLauncher=%~f0"
    "%setupPowerShell%" -NoProfile -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c ' + [char]34 + [char]34 + $env:setupLauncher + [char]34 + [char]34) -Verb RunAs -Wait -PassThru; exit $p.ExitCode } catch { Write-Host $_.Exception.Message; exit 2 }"
    if errorlevel 1 pause
    exit /b
)
"%setupPowerShell%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fresh-Windows-Setup.ps1" %*
set "setupExitCode=%ERRORLEVEL%"
echo Setup returned code %setupExitCode%. Review the report path above.
echo All setup terminals have finished. You may close this launcher.
pause
exit /b %setupExitCode%
