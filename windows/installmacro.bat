@echo off
REM Wrapper to run the PowerShell installer for Windows
REM Usage: double-click this .bat or run from CMD

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installmacro.ps1"

pause
