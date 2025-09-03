@echo off
echo ===== Setting up SMA Upload Scheduler Tasks =====
echo This will create Windows Task Scheduler entries for automated uploads
echo.

REM Check if running as administrator
net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: This script must be run as Administrator
    echo Please right-click and select "Run as administrator"
    pause
    exit /b 1
)

echo Setting up scheduled tasks...
echo.

REM Get current directory for task paths
set CURRENT_DIR=%~dp0
echo Current directory: %CURRENT_DIR%
echo.

REM Create task for Guralp uploader (every 4 hours)
echo Creating task: SMA_Upload_Guralp
schtasks /Create /SC DAILY /ST 02:00 /TN "SMA_Upload_Guralp" /TR "powershell -ExecutionPolicy Bypass -File \"%CURRENT_DIR%upload.ps1\"" /RU SYSTEM /RL HIGHEST /F
if errorlevel 1 (
    echo WARNING: Failed to create Guralp upload task
) else (
    echo SUCCESS: Guralp upload task created
    REM Set repetition interval (every 4 hours)
    schtasks /Change /TN "SMA_Upload_Guralp" /RI 240 /DU 1440
)
echo.

REM Create task for Reftek uploader (every 6 hours)
echo Creating task: SMA_Upload_Reftek
schtasks /Create /SC DAILY /ST 03:00 /TN "SMA_Upload_Reftek" /TR "powershell -ExecutionPolicy Bypass -File \"%CURRENT_DIR%upload_reftek.ps1\"" /RU SYSTEM /RL HIGHEST /F
if errorlevel 1 (
    echo WARNING: Failed to create Reftek upload task
) else (
    echo SUCCESS: Reftek upload task created
    REM Set repetition interval (every 6 hours)
    schtasks /Change /TN "SMA_Upload_Reftek" /RI 360 /DU 1440
)
echo.

REM Create task for Folder-Date uploader (daily at 1 AM)
echo Creating task: SMA_Upload_FolderDate
schtasks /Create /SC DAILY /ST 01:00 /TN "SMA_Upload_FolderDate" /TR "powershell -ExecutionPolicy Bypass -File \"%CURRENT_DIR%upload_folder_date.ps1\"" /RU SYSTEM /RL HIGHEST /F
if errorlevel 1 (
    echo WARNING: Failed to create Folder-Date upload task
) else (
    echo SUCCESS: Folder-Date upload task created
)
echo.

echo ===== Task Setup Complete =====
echo.
echo Created tasks:
schtasks /Query /TN "SMA_Upload_*" /FO TABLE 2>nul
echo.
echo To view tasks in GUI: Run 'taskschd.msc'
echo To delete tasks: Run 'schtasks /Delete /TN "SMA_Upload_*" /F'
echo.
pause
