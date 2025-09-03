@echo off
echo ===== Running All SMA Uploaders =====
echo Time: %date% %time%
echo.

REM Check if PowerShell is available
powershell -Command "Write-Host 'PowerShell is available'" >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is not available or not in PATH
    pause
    exit /b 1
)

set TOTAL_ERRORS=0

REM Run Guralp uploader
echo [1/3] Running Guralp uploader...
powershell -ExecutionPolicy Bypass -File .\upload.ps1
if errorlevel 1 (
    echo ERROR: Guralp uploader failed
    set /a TOTAL_ERRORS+=1
) else (
    echo SUCCESS: Guralp uploader completed
)
echo.

REM Run Reftek uploader
echo [2/3] Running Reftek uploader...
powershell -ExecutionPolicy Bypass -File .\upload_reftek.ps1
if errorlevel 1 (
    echo ERROR: Reftek uploader failed
    set /a TOTAL_ERRORS+=1
) else (
    echo SUCCESS: Reftek uploader completed
)
echo.

REM Run Folder-Date uploader
echo [3/3] Running Folder-Date uploader...
powershell -ExecutionPolicy Bypass -File .\upload_folder_date.ps1
if errorlevel 1 (
    echo ERROR: Folder-Date uploader failed
    set /a TOTAL_ERRORS+=1
) else (
    echo SUCCESS: Folder-Date uploader completed
)
echo.

echo ===== Summary =====
if %TOTAL_ERRORS% EQU 0 (
    echo All uploaders completed successfully
    echo Time: %date% %time%
) else (
    echo %TOTAL_ERRORS% uploader(s) failed - check logs for details
    echo Time: %date% %time%
)
echo.
pause
