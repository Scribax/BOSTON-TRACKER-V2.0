@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "DEVICE_ID=%~1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run_phone_wireless.ps1" -DeviceId "%DEVICE_ID%"
set "EXITCODE=%ERRORLEVEL%"

pause
exit /b %EXITCODE%
