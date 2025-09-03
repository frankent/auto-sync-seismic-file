@echo off
echo ===== SMA Upload Scheduler - Task Management =====
echo.

:MENU
echo Select an option:
echo 1. View existing tasks
echo 2. Delete all SMA upload tasks
echo 3. Delete specific task
echo 4. Enable all tasks
echo 5. Disable all tasks
echo 6. Run task now
echo 7. Exit
echo.
set /p choice="Enter choice (1-7): "

if "%choice%"=="1" goto VIEW_TASKS
if "%choice%"=="2" goto DELETE_ALL
if "%choice%"=="3" goto DELETE_SPECIFIC
if "%choice%"=="4" goto ENABLE_ALL
if "%choice%"=="5" goto DISABLE_ALL
if "%choice%"=="6" goto RUN_NOW
if "%choice%"=="7" goto EXIT
echo Invalid choice. Please try again.
echo.
goto MENU

:VIEW_TASKS
echo.
echo Current SMA upload tasks:
schtasks /Query /TN "SMA_Upload_*" /FO TABLE 2>nul
if errorlevel 1 (
    echo No SMA upload tasks found
)
echo.
pause
goto MENU

:DELETE_ALL
echo.
echo WARNING: This will delete ALL SMA upload tasks!
set /p confirm="Are you sure? (Y/N): "
if /i "%confirm%"=="Y" (
    echo Deleting all SMA upload tasks...
    schtasks /Delete /TN "SMA_Upload_Guralp" /F 2>nul
    schtasks /Delete /TN "SMA_Upload_Reftek" /F 2>nul
    schtasks /Delete /TN "SMA_Upload_FolderDate" /F 2>nul
    echo Done.
) else (
    echo Cancelled.
)
echo.
pause
goto MENU

:DELETE_SPECIFIC
echo.
echo Available tasks:
echo 1. SMA_Upload_Guralp
echo 2. SMA_Upload_Reftek
echo 3. SMA_Upload_FolderDate
set /p task_choice="Enter task number to delete (1-3): "
if "%task_choice%"=="1" set TASK_NAME=SMA_Upload_Guralp
if "%task_choice%"=="2" set TASK_NAME=SMA_Upload_Reftek
if "%task_choice%"=="3" set TASK_NAME=SMA_Upload_FolderDate
if defined TASK_NAME (
    schtasks /Delete /TN "%TASK_NAME%" /F
    echo Task %TASK_NAME% deleted.
) else (
    echo Invalid choice.
)
echo.
pause
goto MENU

:ENABLE_ALL
echo.
echo Enabling all SMA upload tasks...
schtasks /Change /TN "SMA_Upload_Guralp" /ENABLE 2>nul
schtasks /Change /TN "SMA_Upload_Reftek" /ENABLE 2>nul
schtasks /Change /TN "SMA_Upload_FolderDate" /ENABLE 2>nul
echo Done.
echo.
pause
goto MENU

:DISABLE_ALL
echo.
echo Disabling all SMA upload tasks...
schtasks /Change /TN "SMA_Upload_Guralp" /DISABLE 2>nul
schtasks /Change /TN "SMA_Upload_Reftek" /DISABLE 2>nul
schtasks /Change /TN "SMA_Upload_FolderDate" /DISABLE 2>nul
echo Done.
echo.
pause
goto MENU

:RUN_NOW
echo.
echo Available tasks:
echo 1. SMA_Upload_Guralp
echo 2. SMA_Upload_Reftek
echo 3. SMA_Upload_FolderDate
set /p task_choice="Enter task number to run (1-3): "
if "%task_choice%"=="1" set TASK_NAME=SMA_Upload_Guralp
if "%task_choice%"=="2" set TASK_NAME=SMA_Upload_Reftek
if "%task_choice%"=="3" set TASK_NAME=SMA_Upload_FolderDate
if defined TASK_NAME (
    echo Running task %TASK_NAME%...
    schtasks /Run /TN "%TASK_NAME%"
    echo Task started. Check Task Scheduler for status.
) else (
    echo Invalid choice.
)
echo.
pause
goto MENU

:EXIT
echo Goodbye!
pause
