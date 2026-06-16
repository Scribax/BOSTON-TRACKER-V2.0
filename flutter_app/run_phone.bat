@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run_phone_wireless.ps1"
set "EXITCODE=%ERRORLEVEL%"

pause
exit /b %EXITCODE%
