@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Unpack-Form.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo Unpack exited with code %RC%.
pause
exit /b %RC%
