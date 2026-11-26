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
if not "%~1"=="" goto run_with_arguments
set "setupPart="
echo.
echo 0. Exit
echo 1. All
echo 2. Debloat
echo 3. Software
echo 4. Office
echo 5. Drivers
echo 6. AMD / NVIDIA / Intel utilities
choice /c 1234560 /n /m "Choose an option: "
set "setupChoice=%ERRORLEVEL%"
if "%setupChoice%"=="1" set "setupPart=All"
if "%setupChoice%"=="2" set "setupPart=Debloat"
if "%setupChoice%"=="3" set "setupPart=Software"
if "%setupChoice%"=="4" set "setupPart=Office"
if "%setupChoice%"=="5" set "setupPart=Drivers"
if "%setupChoice%"=="6" set "setupPart=Gpu"
if not defined setupPart exit /b 0
"%setupPowerShell%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fresh-Windows-Setup.ps1" -Part %setupPart%
goto report

:run_with_arguments
"%setupPowerShell%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fresh-Windows-Setup.ps1" %*
:report
set "setupExitCode=%ERRORLEVEL%"
echo Setup returned code %setupExitCode%. Review the report path above.
echo All setup terminals have finished. You may close this launcher.
pause
exit /b %setupExitCode%
