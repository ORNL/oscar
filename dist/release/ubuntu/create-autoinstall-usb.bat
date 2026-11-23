@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "USB_SCRIPT=%~dp0create-autoinstall-usb.ps1"
set "USB_LAUNCHER=%~f0"
set "USB_DIRECTORY=%~dp0"

if not "%~1"=="" goto forward_args

rem Double-click / zero-argument launch: auto-elevate via UAC and open native Windows GUI
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator permission for OSCAR Autoinstall USB Creator...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$env:USB_SCRIPT,'-Gui') -WorkingDirectory $env:USB_DIRECTORY -Verb RunAs" ^
        2>nul
    if errorlevel 1 (
        echo OSCAR Autoinstall USB Creator could not obtain administrator permission.
        pause
        exit /b 1
    )
    exit /b 0
)
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%USB_SCRIPT%" -Gui
exit /b %errorlevel%

:forward_args
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%USB_SCRIPT%" %*
exit /b %errorlevel%
