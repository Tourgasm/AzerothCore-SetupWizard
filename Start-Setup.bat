@echo off
:: Double-click this to start WoW Emulator Setup.
:: It bypasses the PowerShell execution policy for this one run only.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WoW-Emulator-Setup.ps1"
