@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0post-tool-use.ps1"
exit /b %ERRORLEVEL%
