# Reftek Multi-Station File Uploader
# Handles Reftek data structure: arc_mrf/YYYYDDD/STATION/CHANNEL/*.mrf

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load config
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $ScriptDir 'config_reftek.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host "=== Reftek File Uploader Started ===" -ForegroundColor Green
Write-Host "DryRun: $($config.DryRun)" -ForegroundColor Yellow

# Setup paths
$BinDir = Join-Path $ScriptDir 'bin'
$LogDir = Join-Path $BinDir 'logs'
$StateDir = Join-Path $BinDir 'state'
$StateFile = Join-Path $StateDir 'uploaded_reftek.txt'

# Create directories
New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null

# Simple logging
function Write-Log($msg) {
    $logFile = Join-Path $LogDir "upload_reftek_$(Get-Date -Format 'yyyyMMdd').log"
    $timestamp = Get-Date -Format 'HH:mm:ss'
    "[$timestamp] $msg" | Add-Content $logFile -Encoding UTF8
    Write-Host "[$timestamp] $msg" -ForegroundColor Gray
}

# Convert Julian date (YYYYDDD) to regular date (YYYY/MM/DD)
function Convert-JulianToDate($julianDate) {
    try {
        $year = [int]$julianDate.Substring(0, 4)
        $dayOfYear = [int]$julianDate.Substring(4, 3)
        $date = [DateTime]::new($year, 1, 1).AddDays($dayOfYear - 1)
        return $date.ToString('yyyy/MM/dd')
    } catch {
        Write-Log "Error converting Julian date: $julianDate"
        return "unknown"
    }
}

# Load uploaded files list
$uploadedFiles = @{}
if (Test-Path $StateFile) {
    Get-Content $StateFile -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -and $_.Trim()) {
            $uploadedFiles[$_.Trim()] = $true
        }
    }
}
Write-Log "Loaded $($uploadedFiles.Count) previously uploaded files"

# Process Reftek data structure
$totalProcessed = 0
$totalUploaded = 0

Write-Host "`n--- Scanning Reftek data structure ---" -ForegroundColor Cyan
Write-Host "Base path: $($config.BaseFolder)" -ForegroundColor White

# Scan for date folders (YYYYDDD format)
$dateFolders = Get-ChildItem -Path $config.BaseFolder -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^\d{7}$'  # 7 digits: YYYYDDD
}

if ($dateFolders.Count -eq 0) {
    Write-Host "No date folders found in $($config.BaseFolder)" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($dateFolders.Count) date folders" -ForegroundColor Yellow

foreach ($dateFolder in $dateFolders) {
    $julianDate = $dateFolder.Name
    $regularDate = Convert-JulianToDate $julianDate
    
    Write-Host "`n--- Processing date: $julianDate ($regularDate) ---" -ForegroundColor Cyan
    
    # Find station folders within this date
    $stationFolders = Get-ChildItem -Path $dateFolder.FullName -Directory -ErrorAction SilentlyContinue
    
    foreach ($stationFolder in $stationFolders) {
        $stationName = $stationFolder.Name
        
        # Find matching station in config
        $stationConfig = $config.Stations | Where-Object { $_.StationFolder -eq $stationName }
        if (-not $stationConfig) {
            Write-Log "SKIP: Station $stationName not found in config"
            continue
        }
        
        $deviceName = if ($stationConfig.DeviceName) { $stationConfig.DeviceName } else { $stationName }
        
        Write-Host "  Station: $stationName (Device: $deviceName)" -ForegroundColor Yellow
        
        # Find channel folders (0, 1, 2, etc.)
        $channelFolders = Get-ChildItem -Path $stationFolder.FullName -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^\d+$'  # Numeric channel names
        }
        
        foreach ($channelFolder in $channelFolders) {
            $channelName = $channelFolder.Name
            
            Write-Host "    Channel: $channelName" -ForegroundColor Gray
            
            # Find .mrf files in this channel
            $mrfFiles = @(Get-ChildItem -Path $channelFolder.FullName -Filter "*.mrf" -File -ErrorAction SilentlyContinue)
            $totalProcessed += $mrfFiles.Count
            
            # Filter out already uploaded files
            $newFiles = @($mrfFiles | Where-Object { 
                -not $uploadedFiles.ContainsKey($_.FullName) -and $_.Length -gt 0 
            })
            
            if ($newFiles.Count -eq 0) {
                Write-Host "      No new files (found $($mrfFiles.Count) total)" -ForegroundColor Blue
                continue
            }
            
            Write-Host "      Found $($newFiles.Count) new files (of $($mrfFiles.Count) total)" -ForegroundColor Green
            
            # Remote directory: /SMA-File-InFraTech/<DeviceName>/YYYY/MM/DD/<channel>
            $remoteDir = "/SMA-File-InFraTech/$deviceName/$regularDate/$channelName"
            
            # DryRun mode
            if ($config.DryRun -eq $true) {
                Write-Host "      DRY RUN - Would upload to: $remoteDir" -ForegroundColor Magenta
                foreach ($file in $newFiles | Select-Object -First 3) {
                    $sizeMB = [Math]::Round($file.Length / 1MB, 3)
                    Write-Host "        - $($file.Name) (${sizeMB}MB)" -ForegroundColor White
                }
                if ($newFiles.Count -gt 3) {
                    Write-Host "        ... and $($newFiles.Count - 3) more files" -ForegroundColor White
                }
                continue
            }
            
            # Real upload mode
            Write-Host "      Uploading $($newFiles.Count) files to: $remoteDir" -ForegroundColor Yellow
            
            # Create temp directory
            $tempDir = Join-Path $BinDir "temp_reftek_${julianDate}_${stationName}_${channelName}_$([Guid]::NewGuid().ToString('N')[0..7] -join '')"
            New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
            
            # Copy files to temp
            $copiedFiles = @()
            foreach ($file in $newFiles) {
                $tempFile = Join-Path $tempDir $file.Name
                Copy-Item $file.FullName $tempFile -Force
                $copiedFiles += $file.FullName
            }
            
            # Create WinSCP script
            $scriptContent = @"
open ftp://$($config.FtpUser):$($config.FtpPass)@$($config.FtpHost):$($config.FtpPort)
option batch on
option confirm off
mkdir "$remoteDir"
cd "$remoteDir"
lcd "$tempDir"
put *.mrf
close
exit
"@
            
            $scriptFile = Join-Path $tempDir "upload.txt"
            $scriptContent | Out-File -Encoding ASCII $scriptFile
            
            # Run WinSCP
            Write-Host "      Running WinSCP..." -ForegroundColor Gray
            $proc = Start-Process -FilePath $config.WinScpPath -ArgumentList "/script=`"$scriptFile`"" -Wait -PassThru -WindowStyle Hidden
            
            if ($proc.ExitCode -eq 0) {
                # Success - mark files as uploaded
                foreach ($filePath in $copiedFiles) {
                    $filePath | Add-Content $StateFile -Encoding UTF8
                    $uploadedFiles[$filePath] = $true
                }
                $totalUploaded += $copiedFiles.Count
                Write-Host "      SUCCESS: Uploaded $($copiedFiles.Count) files" -ForegroundColor Green
                Write-Log "Station ${stationName} Channel ${channelName}: Uploaded $($copiedFiles.Count) files to $remoteDir"
            } else {
                Write-Host "      ERROR: WinSCP failed (exit code: $($proc.ExitCode))" -ForegroundColor Red
                Write-Log "Station ${stationName} Channel ${channelName}: Upload failed - exit code $($proc.ExitCode)"
            }
            
            # Cleanup
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Final summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta
if ($config.DryRun -eq $true) {
    Write-Host "DRY RUN completed - checked $totalProcessed files across all stations/channels" -ForegroundColor Green
} else {
    Write-Host "Uploaded: $totalUploaded files" -ForegroundColor Green
    Write-Host "Total files processed: $totalProcessed" -ForegroundColor Gray
    
    # Send Telegram notification
    if ($totalUploaded -gt 0) {
        try {
            $message = "✅ Reftek Upload completed`nFiles uploaded: $totalUploaded`nDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            $uri = "https://api.telegram.org/bot$($config.TelegramToken)/sendMessage"
            $body = @{ chat_id = $config.TelegramChatId; text = $message }
            Invoke-RestMethod -Uri $uri -Method Post -Body $body | Out-Null
            Write-Log "Telegram notification sent"
        } catch {
            Write-Log "Telegram notification failed: $($_.Exception.Message)"
        }
    }
}

Write-Host "Completed at $(Get-Date)" -ForegroundColor Cyan
