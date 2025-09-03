@echo off
echo ===== SMA File Uploader Started =====
echo Time: %date% %time%
echo.

REM Check if PowerShell is available
powershell -Command "Write-Host 'PowerShell is available'" >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is not available or not in PATH
    pause
    exit /b 1
)

REM Run the Reftek uploader (change this to upload.ps1 or upload_folder_date.ps1 as needed)
echo Running Reftek uploader...
powershell -ExecutionPolicy Bypass -File .\upload_reftek.ps1

REM Check exit code
if errorlevel 1 (
    echo ERROR: Upload script failed with exit code %errorlevel%
    pause
    exit /b %errorlevel%
) else (
    echo SUCCESS: Upload completed successfully
)

echo.
echo ===== SMA File Uploader Finished =====
echo Time: %date% %time%
pause