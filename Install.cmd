@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
    echo Installation completed.
) else (
    echo Installation failed with code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%

