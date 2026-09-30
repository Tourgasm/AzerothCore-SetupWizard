@echo off
:: Double-click this to start the AzerothCore setup wizard.
:: It bypasses the PowerShell execution policy for this one run only.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AzerothCore-Setup.ps1"
