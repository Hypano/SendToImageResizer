@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SendToImageResizer.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
    echo.
    echo SendToImageResizer exited with code %EXIT_CODE%.
    pause
)
exit /b %EXIT_CODE%
