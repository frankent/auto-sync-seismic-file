# Simple Multi-Station File Uploader
# Optimized for speed and simplicity

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load config
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $ScriptDir 'config.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host "=== File Uploader Started ===" -ForegroundColor Green
Write-Host "DryRun: $($config.DryRun)" -ForegroundColor Yellow

# Setup paths
$BinDir = Join-Path $ScriptDir 'bin'
$LogDir = Join-Path $BinDir 'logs'
$StateDir = Join-Path $BinDir 'state'
$StateFile = Join-Path $StateDir 'uploaded.txt'

# Create directories
New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null

# Simple logging
function Write-Log($msg) {
    $logFile = Join-Path $LogDir "upload_$(Get-Date -Format 'yyyyMMdd').log"
    $timestamp = Get-Date -Format 'HH:mm:ss'
    "[$timestamp] $msg" | Add-Content $logFile -Encoding UTF8
    Write-Host "[$timestamp] $msg" -ForegroundColor Gray
}

# Load uploaded files list (simple text file)
$uploadedFiles = @{}
if (Test-Path $StateFile) {
    Get-Content $StateFile -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -and $_.Trim()) {
            $uploadedFiles[$_.Trim()] = $true
        }
    }
}
Write-Log "Loaded $($uploadedFiles.Count) previously uploaded files"

# Process each station
$totalProcessed = 0
$totalUploaded = 0

foreach ($station in $config.Stations) {
    Write-Host "`n--- Station: $($station.StationFolder) ---" -ForegroundColor Cyan
    
    $stationPath = Join-Path $config.BaseFolder $station.StationFolder
    
    if (-not (Test-Path $stationPath)) {
        Write-Log "SKIP: $($station.StationFolder) - folder not found"
        continue
    }
    
    # Find .gcf files (simple, fast search)
    $files = Get-ChildItem -Path $stationPath -Filter "*.gcf" -Recurse -File -ErrorAction SilentlyContinue
    $totalProcessed += $files.Count
    
    # Filter out already uploaded files
    $newFiles = $files | Where-Object { 
        -not $uploadedFiles.ContainsKey($_.FullName) -and $_.Length -gt 0 
    }
    
    if ($newFiles.Count -eq 0) {
        Write-Log "$($station.StationFolder): No new files (found $($files.Count) total)"
        continue
    }
    
    Write-Host "Found $($newFiles.Count) new files (of $($files.Count) total)" -ForegroundColor Green
    
    $deviceName = if ($station.DeviceName) { $station.DeviceName } else { $station.StationFolder }
    
    # Group files by their creation date
    $filesByDate = @{}
    foreach ($file in $newFiles) {
        $fileDate = $file.CreationTime.ToString('yyyy/MM/dd')
        if (-not $filesByDate.ContainsKey($fileDate)) {
            $filesByDate[$fileDate] = @()
        }
        $filesByDate[$fileDate] += $file
    }
    
    Write-Host "Files grouped into $($filesByDate.Count) date folders:" -ForegroundColor Yellow
    foreach ($date in $filesByDate.Keys | Sort-Object) {
        Write-Host "  ${date}: $($filesByDate[$date].Count) files" -ForegroundColor Gray
    }
    
    # DryRun mode - show what would be uploaded
    if ($config.DryRun -eq $true) {
        Write-Host "DRY RUN - Would upload files by date:" -ForegroundColor Magenta
        foreach ($date in $filesByDate.Keys | Sort-Object) {
            $remoteDir = "/SMA-File-InFraTech/$deviceName/$date"
            Write-Host "  To: $remoteDir ($($filesByDate[$date].Count) files)" -ForegroundColor White
            foreach ($file in $filesByDate[$date] | Select-Object -First 3) {
                $sizeMB = [Math]::Round($file.Length / 1MB, 3)
                Write-Host "    - $($file.Name) (${sizeMB}MB)" -ForegroundColor Gray
            }
            if ($filesByDate[$date].Count -gt 3) {
                Write-Host "    ... and $($filesByDate[$date].Count - 3) more" -ForegroundColor Gray
            }
        }
        continue
    }
    
    # Real upload mode - process each date group separately
    $stationUploaded = 0
    foreach ($date in $filesByDate.Keys | Sort-Object) {
        $dateFiles = $filesByDate[$date]
        $remoteDir = "/SMA-File-InFraTech/$deviceName/$date"
        
        Write-Host "Uploading $($dateFiles.Count) files from ${date} to: $remoteDir" -ForegroundColor Yellow
        
        # Create temp directory for this date
        $tempDir = Join-Path $BinDir "temp_${date}_$([Guid]::NewGuid().ToString('N')[0..7] -join '')".Replace('/', '_')
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        
        # Copy files to temp
        $copiedFiles = @()
        foreach ($file in $dateFiles) {
            $tempFile = Join-Path $tempDir $file.Name
            Copy-Item $file.FullName $tempFile -Force
            $copiedFiles += $file.FullName
        }
        
        # Create WinSCP script for this date
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
        
        # Run WinSCP for this date group
        Write-Host "  Running WinSCP for ${date}..." -ForegroundColor Gray
        $proc = Start-Process -FilePath $config.WinScpPath -ArgumentList "/script=`"$scriptFile`"" -Wait -PassThru -WindowStyle Hidden
        
        if ($proc.ExitCode -eq 0) {
            # Success - mark files as uploaded
            foreach ($filePath in $copiedFiles) {
                $filePath | Add-Content $StateFile -Encoding UTF8
                $uploadedFiles[$filePath] = $true
            }
            $stationUploaded += $copiedFiles.Count
            Write-Host "  SUCCESS: Uploaded $($copiedFiles.Count) files for ${date}" -ForegroundColor Green
            Write-Log "$($station.StationFolder): Uploaded $($copiedFiles.Count) files to $remoteDir"
        } else {
            Write-Host "  ERROR: WinSCP failed for ${date} (exit code: $($proc.ExitCode))" -ForegroundColor Red
            Write-Log "$($station.StationFolder): Upload failed for ${date} - exit code $($proc.ExitCode)"
        }
        
        # Cleanup this temp directory
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $totalUploaded += $stationUploaded
    Write-Host "Station total: $stationUploaded files uploaded" -ForegroundColor Green
}

# Final summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta
if ($config.DryRun -eq $true) {
    Write-Host "DRY RUN completed - checked $totalProcessed files across all stations" -ForegroundColor Green
} else {
    Write-Host "Uploaded: $totalUploaded files" -ForegroundColor Green
    Write-Host "Total files processed: $totalProcessed" -ForegroundColor Gray
    
    # Send Telegram notification
    if ($totalUploaded -gt 0) {
        try {
            $message = "✅ Upload completed`nFiles uploaded: $totalUploaded`nDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
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
