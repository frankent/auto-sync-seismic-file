# Folder-Date Multi-Station File Uploader
# Handles folder structure: BaseFolder/YYYY/YYYYMM/YYYYMMDD/*.gcf
# File pattern: {number}_{station_id}_{YYYYMMDD}_{HH00}{n|e|z}.gcf

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load config
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $ScriptDir 'config.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host "=== Folder-Date File Uploader Started ===" -ForegroundColor Green
Write-Host "DryRun: $($config.DryRun)" -ForegroundColor Yellow

# Setup paths
$BinDir = Join-Path $ScriptDir 'bin'
$LogDir = Join-Path $BinDir 'logs'
$StateDir = Join-Path $BinDir 'state'
$StateFile = Join-Path $StateDir 'uploaded_folder_date.txt'

# Create directories
New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null

# Simple logging
function Write-Log($msg) {
    $logFile = Join-Path $LogDir "upload_folder_date_$(Get-Date -Format 'yyyyMMdd').log"
    $timestamp = Get-Date -Format 'HH:mm:ss'
    "[$timestamp] $msg" | Add-Content $logFile -Encoding UTF8
    Write-Host "[$timestamp] $msg" -ForegroundColor Gray
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

# Process folder structure: BaseFolder/YYYY/YYYYMM/YYYYMMDD
$totalProcessed = 0
$totalUploaded = 0

Write-Host "`n--- Scanning folder structure ---" -ForegroundColor Cyan
Write-Host "Base path: $($config.BaseFolder)" -ForegroundColor White

# Find year folders (YYYY)
$yearFolders = Get-ChildItem -Path $config.BaseFolder -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^\d{4}$'  # 4 digits: YYYY
}

if ($yearFolders.Count -eq 0) {
    Write-Host "No year folders found in $($config.BaseFolder)" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($yearFolders.Count) year folders" -ForegroundColor Yellow

foreach ($yearFolder in $yearFolders) {
    $year = $yearFolder.Name
    Write-Host "`n--- Processing year: $year ---" -ForegroundColor Cyan
    
    # Find month folders (YYYYMM)
    $monthFolders = Get-ChildItem -Path $yearFolder.FullName -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "^${year}\d{2}$"  # YYYYMM format
    }
    
    foreach ($monthFolder in $monthFolders) {
        $month = $monthFolder.Name
        Write-Host "  Month: $month" -ForegroundColor Yellow
        
        # Find date folders (YYYYMMDD)
        $dateFolders = Get-ChildItem -Path $monthFolder.FullName -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match "^${year}\d{4}$"  # YYYYMMDD format
        }
        
        foreach ($dateFolder in $dateFolders) {
            $dateString = $dateFolder.Name  # YYYYMMDD
            $formattedDate = $dateString.Substring(0,4) + "/" + $dateString.Substring(4,2) + "/" + $dateString.Substring(6,2)  # YYYY/MM/DD
            
            Write-Host "    Date: $dateString ($formattedDate)" -ForegroundColor Gray
            
            # Find .gcf files in this date folder
            $gcfFiles = @(Get-ChildItem -Path $dateFolder.FullName -Filter "*.gcf" -File -ErrorAction SilentlyContinue)
            $totalProcessed += $gcfFiles.Count
            
            if ($gcfFiles.Count -eq 0) {
                Write-Host "      No .gcf files found" -ForegroundColor Blue
                continue
            }
            
            # Group files by station (extract station_id from filename)
            $filesByStation = @{}
            foreach ($file in $gcfFiles) {
                # File pattern: {number}_{station_id}_{YYYYMMDD}_{HH00}[{n|e|z}].gcf (channel component optional)
                if ($file.Name -match '^([^_]+)_([^_]+)_(\d{8})_(\d{4}[nez]?)\.gcf$') {
                    $stationId = $matches[1] + "_" + $matches[2]  # Combine first two parts
                    
                    # Find matching station in config
                    $stationConfig = $config.Stations | Where-Object { $_.StationFolder -eq $stationId }
                    if ($stationConfig) {
                        if (-not $filesByStation.ContainsKey($stationId)) {
                            $filesByStation[$stationId] = @{
                                Config = $stationConfig
                                Files = @()
                            }
                        }
                        $filesByStation[$stationId].Files += $file
                    } else {
                        Write-Log "SKIP: File $($file.Name) - station $stationId not found in config"
                    }
                } else {
                    Write-Log "SKIP: File $($file.Name) - doesn't match expected pattern"
                }
            }
            
            # Process each station's files
            foreach ($stationId in $filesByStation.Keys) {
                $stationData = $filesByStation[$stationId]
                $stationConfig = $stationData.Config
                $stationFiles = $stationData.Files
                $deviceName = if ($stationConfig.DeviceName) { $stationConfig.DeviceName } else { $stationId }
                
                Write-Host "      Station: $stationId (Device: $deviceName)" -ForegroundColor Cyan
                
                # Filter out already uploaded files
                $newFiles = @($stationFiles | Where-Object { 
                    -not $uploadedFiles.ContainsKey($_.FullName) -and $_.Length -gt 0 
                })
                
                if ($newFiles.Count -eq 0) {
                    Write-Host "        No new files (found $($stationFiles.Count) total)" -ForegroundColor Blue
                    continue
                }
                
                Write-Host "        Found $($newFiles.Count) new files (of $($stationFiles.Count) total)" -ForegroundColor Green
                
                # Remote directory: /SMA-File-InFraTech/<DeviceName>/YYYY/MM/DD/<station>
                $remoteDir = "/SMA-File-InFraTech/$deviceName/$formattedDate/$stationId"
                
                # DryRun mode
                if ($config.DryRun -eq $true) {
                    Write-Host "        DRY RUN - Would upload to: $remoteDir" -ForegroundColor Magenta
                    foreach ($file in $newFiles | Select-Object -First 3) {
                        $sizeMB = [Math]::Round($file.Length / 1MB, 3)
                        Write-Host "          - $($file.Name) (${sizeMB}MB)" -ForegroundColor White
                    }
                    if ($newFiles.Count -gt 3) {
                        Write-Host "          ... and $($newFiles.Count - 3) more files" -ForegroundColor White
                    }
                    continue
                }
                
                # Real upload mode
                Write-Host "        Uploading $($newFiles.Count) files to: $remoteDir" -ForegroundColor Yellow
                
                # Create temp directory
                $tempDir = Join-Path $BinDir "temp_fd_${dateString}_${stationId}_$([Guid]::NewGuid().ToString('N')[0..7] -join '')"
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
put *.gcf
close
exit
"@
                
                $scriptFile = Join-Path $tempDir "upload.txt"
                $scriptContent | Out-File -Encoding ASCII $scriptFile
                
                # Run WinSCP
                Write-Host "        Running WinSCP..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $config.WinScpPath -ArgumentList "/script=`"$scriptFile`"" -Wait -PassThru -WindowStyle Hidden
                
                if ($proc.ExitCode -eq 0) {
                    # Success - mark files as uploaded
                    foreach ($filePath in $copiedFiles) {
                        $filePath | Add-Content $StateFile -Encoding UTF8
                        $uploadedFiles[$filePath] = $true
                    }
                    $totalUploaded += $copiedFiles.Count
                    Write-Host "        SUCCESS: Uploaded $($copiedFiles.Count) files" -ForegroundColor Green
                    Write-Log "Station ${stationId}: Uploaded $($copiedFiles.Count) files to $remoteDir"
                } else {
                    Write-Host "        ERROR: WinSCP failed (exit code: $($proc.ExitCode))" -ForegroundColor Red
                    Write-Log "Station ${stationId}: Upload failed - exit code $($proc.ExitCode)"
                }
                
                # Cleanup
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Final summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta
if ($config.DryRun -eq $true) {
    Write-Host "DRY RUN completed - checked $totalProcessed files across all date folders" -ForegroundColor Green
} else {
    Write-Host "Uploaded: $totalUploaded files" -ForegroundColor Green
    Write-Host "Total files processed: $totalProcessed" -ForegroundColor Gray
    
    # Send Telegram notification
    if ($totalUploaded -gt 0) {
        try {
            $message = "✅ Folder-Date Upload completed`nFiles uploaded: $totalUploaded`nDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
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
