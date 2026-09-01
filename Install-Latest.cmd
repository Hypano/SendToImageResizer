@echo off
setlocal EnableExtensions

title SendToImageResizer Installer

set "STIR_EFFECTIVE_URL=https://github.com/Hypano/SendToImageResizer/releases/latest/download/SendToImageResizer.zip"
if defined STIR_DOWNLOAD_URL set "STIR_EFFECTIVE_URL=%STIR_DOWNLOAD_URL%"

set "STIR_WORK_DIR=%TEMP%\SendToImageResizer-%RANDOM%-%RANDOM%"
set "STIR_ZIP_PATH=%STIR_WORK_DIR%\SendToImageResizer.zip"
set "STIR_EXTRACT_DIR=%STIR_WORK_DIR%\extracted"

echo SendToImageResizer - Latest Release Installer
echo.
echo Temporary files: %STIR_WORK_DIR%
echo.

mkdir "%STIR_WORK_DIR%" >nul 2>&1
if errorlevel 1 goto :prepare_failed
mkdir "%STIR_EXTRACT_DIR%" >nul 2>&1
if errorlevel 1 goto :prepare_failed

if defined STIR_PACKAGE_PATH (
    echo Using local release package...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Copy-Item -LiteralPath $env:STIR_PACKAGE_PATH -Destination $env:STIR_ZIP_PATH -Force"
) else (
    echo Downloading the latest release...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $env:STIR_EFFECTIVE_URL -OutFile $env:STIR_ZIP_PATH"
)
if errorlevel 1 goto :download_failed

echo Extracting package...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath $env:STIR_ZIP_PATH -DestinationPath $env:STIR_EXTRACT_DIR -Force"
if errorlevel 1 goto :extract_failed

set "STIR_INSTALL_SCRIPT=%STIR_EXTRACT_DIR%\SendToImageResizer\Install.ps1"
if not exist "%STIR_INSTALL_SCRIPT%" goto :invalid_package

echo Installing...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%STIR_INSTALL_SCRIPT%"
set "STIR_RESULT=%ERRORLEVEL%"

call :cleanup
if not "%STIR_RESULT%"=="0" goto :install_failed

echo.
echo SendToImageResizer was installed successfully.
echo The downloaded package and temporary files were removed.
goto :success

:prepare_failed
echo ERROR: The temporary working directory could not be created.
goto :failure

:download_failed
echo ERROR: The release package could not be downloaded.
goto :failure

:extract_failed
echo ERROR: The release package could not be extracted.
goto :failure

:invalid_package
echo ERROR: The downloaded release package is incomplete.
goto :failure

:install_failed
echo ERROR: Installation failed with exit code %STIR_RESULT%.
goto :failure_no_cleanup

:failure
call :cleanup

:failure_no_cleanup
echo.
if not defined STIR_NO_PAUSE pause
exit /b 1

:success
echo.
if not defined STIR_NO_PAUSE pause
exit /b 0

:cleanup
if defined STIR_WORK_DIR if exist "%STIR_WORK_DIR%" rmdir /s /q "%STIR_WORK_DIR%" >nul 2>&1
exit /b 0
