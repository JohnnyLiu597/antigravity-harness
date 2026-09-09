@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pre-tool-use.ps1"
exit /b %ERRORLEVEL%
