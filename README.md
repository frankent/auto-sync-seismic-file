# SMA File Uploader - Seismic Data Upload Automation

This project provides automated uploaders for seismic data files from multiple station formats to an FTP server. It supports three different data structure formats:

1. **Guralp Format** (`upload.ps1`) - Station-based folder structure
2. **Reftek Format** (`upload_reftek.ps1`) - Julian date folder structure  
3. **Folder-Date Format** (`upload_folder_date.ps1`) - Hierarchical date folder structure

## 📁 Project Structure

```
SMAUploader_final/
├── upload.ps1                    # Guralp station uploader
├── upload_reftek.ps1             # Reftek Julian date uploader
├── upload_folder_date.ps1        # Folder-date hierarchy uploader
├── config.json                   # Guralp/Folder-date configuration
├── config_reftek.json            # Reftek configuration
├── bin/
│   ├── logs/                     # Upload logs (auto-created)
│   └── state/                    # Upload state tracking (auto-created)
└── README.md                     # This file
```

## 🚀 Quick Start

### 1. Prerequisites

- **Windows PowerShell 5.1+** or **PowerShell Core 7+**
- **WinSCP** installed at `C:\Program Files (x86)\WinSCP\WinSCP.com`
- **Network access** to the FTP server

### 2. Configuration

#### For Guralp/Folder-Date Format (`config.json`):
```json
{
  "BaseFolder": "F:\\Scream\\data",
  "Stations": [
    { "StationFolder": "5he3e0", "DeviceName": "Maetalop" },
    { "StationFolder": "5he3n0", "DeviceName": "Maetalop" }
  ],
  "FtpHost": "122.154.8.21",
  "FtpPort": 38866,
  "FtpUser": "FTP-SMA-InFraTech01",
  "FtpPass": "your_password",
  "TelegramToken": "your_telegram_token",
  "TelegramChatId": "your_chat_id",
  "WinScpPath": "C:\\Program Files (x86)\\WinSCP\\WinSCP.com",
  "DryRun": false
}
```

#### For Reftek Format (`config_reftek.json`):
```json
{
  "BaseFolder": "D:\\reftek\\arc_mrf",
  "Stations": [
    { "StationFolder": "34076", "DeviceName": "HuaiPongOn" },
    { "StationFolder": "34077", "DeviceName": "HuaiPongOn" }
  ],
  "FtpHost": "122.154.8.21",
  "FtpPort": 38866,
  "FtpUser": "FTP-SMA-InFraTech01",
  "FtpPass": "your_password",
  "TelegramToken": "your_telegram_token",
  "TelegramChatId": "your_chat_id",
  "WinScpPath": "C:\\Program Files (x86)\\WinSCP\\WinSCP.com",
  "DryRun": false
}
```

### 3. Running Scripts

#### Test Mode (DryRun):
```powershell
# Set DryRun: true in config, then run:
powershell -ExecutionPolicy Bypass -File .\upload.ps1
powershell -ExecutionPolicy Bypass -File .\upload_reftek.ps1
powershell -ExecutionPolicy Bypass -File .\upload_folder_date.ps1
```

#### Production Mode:
```powershell
# Set DryRun: false in config, then run:
powershell -ExecutionPolicy Bypass -File .\upload.ps1
```

## 📊 Data Formats Supported

### 1. Guralp Format (`upload.ps1`)
- **Structure:** `BaseFolder\<StationFolder>\**\*.gcf`
- **Example:** `F:\Scream\data\5he3e0\2024\08\15\*.gcf`
- **Files grouped by:** Creation date
- **Remote path:** `/SMA-File-InFraTech/<DeviceName>/YYYY/MM/DD/`

### 2. Reftek Format (`upload_reftek.ps1`)
- **Structure:** `BaseFolder\<YYYYDDD>\<Station>\<Channel>\*.mrf`
- **Example:** `D:\reftek\arc_mrf\2024276\34076\0\*.mrf`
- **Julian date:** `2024276` = October 2, 2024
- **Remote path:** `/SMA-File-InFraTech/<DeviceName>/YYYY/MM/DD/<Station>/<Channel>/`

### 3. Folder-Date Format (`upload_folder_date.ps1`)
- **Structure:** `BaseFolder\<YYYY>\<YYYYMM>\<YYYYMMDD>\*.gcf`
- **Example:** `F:\Scream\data\2024\202402\20240217\*.gcf`
- **File pattern:** `{number}_{station_id}_{YYYYMMDD}_{HH00}{n|e|z}.gcf`
- **Remote path:** `/SMA-File-InFraTech/<DeviceName>/YYYY/MM/DD/<Station>/`

## ⏰ Windows Task Scheduler Setup

### Method 1: Using Task Scheduler GUI

1. **Open Task Scheduler:**
   - Press `Win + R`, type `taskschd.msc`, press Enter

2. **Create Basic Task:**
   - Right-click "Task Scheduler Library" → "Create Basic Task..."
   - **Name:** `SMA File Upload - Guralp`
   - **Description:** `Automated upload of Guralp seismic data files`

3. **Set Trigger:**
   - **Daily** at your preferred time (e.g., 2:00 AM)
   - **Recur every:** 1 days

4. **Set Action:**
   - **Action:** Start a program
   - **Program/script:** `powershell.exe`
   - **Arguments:** `-ExecutionPolicy Bypass -File "C:\SyncToCenter\upload.ps1"`
   - **Start in:** `C:\SyncToCenter\`

5. **Configure Settings:**
   - Check "Run whether user is logged on or not"
   - Check "Run with highest privileges"
   - **Configure for:** Windows 10/11

### Method 2: Using PowerShell Commands

```powershell
# Create scheduled task for Guralp uploader
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\SyncToCenter\upload.ps1`"" -WorkingDirectory "C:\SyncToCenter"
$trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "SMA File Upload - Guralp" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Automated upload of Guralp seismic data files"
```

### Multiple Uploaders Setup

For all three uploaders, create separate tasks:

```powershell
# Guralp (every 4 hours)
$trigger1 = New-ScheduledTaskTrigger -Daily -At "02:00AM"
$trigger1.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition

# Reftek (every 6 hours)
$trigger2 = New-ScheduledTaskTrigger -Daily -At "03:00AM"
$trigger2.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition

# Folder-Date (daily at 1 AM)
$trigger3 = New-ScheduledTaskTrigger -Daily -At "01:00AM"
```

## 📝 Logging & Monitoring

### Log Files
- **Location:** `bin\logs\`
- **Format:** `upload_YYYYMMDD.log`, `upload_reftek_YYYYMMDD.log`, `upload_folder_date_YYYYMMDD.log`
- **Retention:** 30 days (configurable)

### State Tracking
- **Location:** `bin\state\`
- **Files:** `uploaded.txt`, `uploaded_reftek.txt`, `uploaded_folder_date.txt`
- **Purpose:** Prevents duplicate uploads

### Telegram Notifications
Configure Telegram bot for upload completion notifications:
1. Create a bot via [@BotFather](https://t.me/botfather)
2. Get your chat ID
3. Update `TelegramToken` and `TelegramChatId` in config

## 🔧 Troubleshooting

### Common Issues

1. **PowerShell Execution Policy:**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **WinSCP Path Issues:**
   - Verify WinSCP installation path in config
   - Common paths: `C:\Program Files (x86)\WinSCP\WinSCP.com`

3. **Permission Errors:**
   - Run PowerShell as Administrator
   - Check folder permissions for BaseFolder

4. **FTP Connection Issues:**
   - Verify network connectivity
   - Test FTP credentials manually
   - Check firewall settings

### Script Testing

```powershell
# Test configuration
powershell -ExecutionPolicy Bypass -Command "Get-Content .\config.json | ConvertFrom-Json"

# Test with DryRun
# Set "DryRun": true in config, then run script

# Check logs
Get-Content .\bin\logs\upload_20240830.log -Tail 20
```

## 🔐 Security Notes

- Store sensitive credentials securely
- Use dedicated FTP accounts with minimal permissions
- Consider encrypting config files
- Regular credential rotation recommended

## 📈 Performance Tips

- **Batch Size:** Scripts automatically batch files by date/station
- **Timing:** Schedule during low-network usage periods
- **Monitoring:** Check logs regularly for failed uploads
- **Storage:** Ensure sufficient disk space for temp files

## 🆘 Support

For issues or questions:
1. Check log files in `bin\logs\`
2. Verify configuration settings
3. Test with DryRun mode first
4. Review Windows Event Logs for task scheduler issues

---

**Last Updated:** August 2025  
**Version:** 1.0
