# Multi-Station File Uploader
# Clean PowerShell script with proper syntax

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get script directory and load config
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Script starting at $(Get-Date)" -ForegroundColor Green

try {
    $configPath = Join-Path $ScriptDir 'config.json'
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Host "Configuration loaded" -ForegroundColor Green
    Write-Host "DryRun mode: $($config.DryRun)" -ForegroundColor Yellow
} catch {
    Write-Error "Failed to load config: $($_.Exception.Message)"
    exit 1
}

# Setup directories
$BinDir = Join-Path $ScriptDir 'bin'
$TempDir = Join-Path $BinDir 'temp'
$LogDir = Join-Path $BinDir 'logs'
$StateDir = Join-Path $BinDir 'state'
$StateFile = Join-Path $StateDir 'sent-state.json'
$RetryFile = Join-Path $StateDir 'retry-queue.json'

New-Item -ItemType Directory -Force -Path $TempDir, $LogDir, $StateDir | Out-Null

# Initialize files
if (-not (Test-Path $StateFile)) {
    '{}' | Out-File -Encoding UTF8 $StateFile
}
if (-not (Test-Path $RetryFile)) {
    '[]' | Out-File -Encoding UTF8 $RetryFile
}

# Functions
function Write-Log {
    param([string]$Message)
    $logPath = Join-Path $LogDir ("upload_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Encoding UTF8 -Path $logPath -Value "[$timestamp] $Message"
}

function Send-Telegram {
    param([string]$Text)
    try {
        $uri = "https://api.telegram.org/bot$($config.TelegramToken)/sendMessage"
        $body = @{ chat_id = $config.TelegramChatId; text = $Text }
        Invoke-RestMethod -Uri $uri -Method Post -Body $body | Out-Null
    } catch {
        Write-Log "Telegram error: $($_.Exception.Message)"
    }
}

function Test-FileReady {
    param([string]$FilePath)
    try {
        $fs = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'Read')
        $fs.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-RetryQueue {
    try {
        $content = Get-Content $RetryFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $items = $content | ConvertFrom-Json
            if ($items -is [array]) {
                return $items
            }
        }
        return @()
    } catch {
        return @()
    }
}

function Set-RetryQueue {
    param([array]$Items)
    ($Items | ConvertTo-Json) | Out-File -Encoding UTF8 $RetryFile
}

function New-FileKey {
    param([string]$Path, [long]$Ticks)
    return "$Path||$Ticks"
}

# Setup variables
$yesterday = (Get-Date).AddDays(-1).Date
$today = (Get-Date).Date
$includePatterns = @($config.IncludePatterns)
if (-not $includePatterns) { $includePatterns = @('*.gcf') }
$excludePatterns = @($config.ExcludePatterns)

# Load state
$state = @{}
try {
    $stateContent = Get-Content $StateFile -Raw | ConvertFrom-Json
    if ($stateContent) { $state = $stateContent }
} catch {
    Write-Log "Starting with empty state"
}

$retryQueue = Get-RetryQueue
$failedByStation = @{}
$totalSent = 0
$totalSize = 0

Write-Host "Processing $($config.Stations.Count) stations..." -ForegroundColor Cyan

# Main processing loop
foreach ($station in $config.Stations) {
    Write-Host "Processing station: $($station.StationFolder)" -ForegroundColor Yellow
    
    $stationPath = Join-Path $config.BaseFolder $station.StationFolder
    
    if (-not (Test-Path $stationPath)) {
        Write-Host "Station folder not found: $stationPath" -ForegroundColor Red
        Write-Log "Skip $($station.StationFolder) - not found"
        continue
    }
    
    $deviceName = if ($station.DeviceName) { $station.DeviceName } else { $station.StationFolder }
    
    # Find files
    $allFiles = @()
    foreach ($pattern in $includePatterns) {
        $files = Get-ChildItem -Path $stationPath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
        $allFiles += $files
    }
    
    # Filter by date
    $validFiles = $allFiles | Where-Object {
        $isValid = $_.LastWriteTime -ge $yesterday -and $_.LastWriteTime -lt $today -and $_.Length -gt 0
        
        if ($isValid -and $excludePatterns) {
            foreach ($exclude in $excludePatterns) {
                if ($_.Name -like $exclude) {
                    $isValid = $false
                    break
                }
            }
        }
        return $isValid
    }
    
    # Find retry files
    $retryFiles = @()
    foreach ($retry in $retryQueue) {
        $retryPath = [string]$retry.Path
        if ($retryPath -like "$stationPath*") {
            if (Test-Path $retryPath) {
                $fileInfo = Get-Item $retryPath -ErrorAction SilentlyContinue
                if ($fileInfo -and (Test-FileReady $fileInfo.FullName)) {
                    $retryFiles += $fileInfo
                }
            }
        }
    }
    
    # Build todo list
    $todoFiles = @()
    
    foreach ($file in $validFiles) {
        $key = New-FileKey $file.FullName $file.LastWriteTimeUtc.Ticks
        if (-not $state.ContainsKey($key) -and (Test-FileReady $file.FullName)) {
            $todoFiles += $file
        }
    }
    
    foreach ($file in $retryFiles) {
        $key = New-FileKey $file.FullName $file.LastWriteTimeUtc.Ticks
        if (-not $state.ContainsKey($key)) {
            $alreadyExists = $false
            foreach ($existing in $todoFiles) {
                if ($existing.FullName -eq $file.FullName) {
                    $alreadyExists = $true
                    break
                }
            }
            if (-not $alreadyExists) {
                $todoFiles += $file
            }
        }
    }
    
    if ($todoFiles.Count -eq 0) {
        Write-Host "No files to process for $($station.StationFolder)" -ForegroundColor Blue
        continue
    }
    
    Write-Host "Files to process: $($todoFiles.Count)" -ForegroundColor Green
    
    $remoteDir = "/SMA-File-InFraTech/$deviceName/$($yesterday.ToString('yyyy'))/$($yesterday.ToString('MM'))/$($yesterday.ToString('dd'))"
    
    # Handle DryRun
    if ($config.DryRun -eq $true) {
        Write-Host "DRY RUN MODE" -ForegroundColor Magenta
        foreach ($file in $todoFiles) {
            Write-Host "Would upload: $($file.Name)" -ForegroundColor White
            Write-Log "[DRYRUN] $($file.FullName) -> $remoteDir/$($file.Name)"
        }
        continue
    }
    
    # Create staging
    $stagingDir = Join-Path $TempDir ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
    
    $stageMap = @{}
    foreach ($file in $todoFiles) {
        $stagePath = Join-Path $stagingDir $file.Name
        Copy-Item $file.FullName $stagePath -Force
        $stageMap[$stagePath] = $file.FullName
    }
    
    # Create WinSCP script
    $scriptLines = @(
        "open ftp://$($config.FtpUser):$($config.FtpPass)@$($config.FtpHost):$($config.FtpPort)"
        "option batch on"
        "option confirm off"
        "mkdir `"$remoteDir`""
        "cd `"$remoteDir`""
        "lcd `"$stagingDir`""
        "put *"
        "exit"
    )
    
    $scriptContent = $scriptLines -join "`r`n"
    $scriptFile = Join-Path $stagingDir 'script.txt'
    $scriptContent | Out-File -Encoding ASCII $scriptFile
    
    # Run WinSCP
    $logFile = Join-Path $LogDir "winscp_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $proc = Start-Process -FilePath $config.WinScpPath -ArgumentList "/script=`"$scriptFile`"", "/log=`"$logFile`"" -Wait -PassThru
    
    # Check results
    $failedFiles = @()
    try {
        $logContent = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        if ($logContent -and $logContent -match 'Error') {
            Write-Log "WinSCP reported errors for station $($station.StationFolder)"
            $failedFiles = $todoFiles  # Assume all failed if errors detected
        }
    } catch {
        Write-Log "Could not parse WinSCP log"
    }
    
    # Update state
    $newRetry = @()
    foreach ($retry in $retryQueue) {
        if (-not ([string]$retry.Path -like "$stationPath*")) {
            $newRetry += $retry
        }
    }
    
    $stationSent = 0
    $stationSize = 0
    
    foreach ($file in $todoFiles) {
        $key = New-FileKey $file.FullName $file.LastWriteTimeUtc.Ticks
        
        if ($failedFiles -contains $file) {
            $newRetry += @{ Path = $file.FullName; Ticks = $file.LastWriteTimeUtc.Ticks }
            Write-Log "FAIL: $($file.FullName)"
        } else {
            $state[$key] = (Get-Date).ToString('s')
            $stationSent++
            $stationSize += $file.Length
            Write-Log "OK: $($file.FullName)"
        }
    }
    
    Set-RetryQueue $newRetry
    $state | ConvertTo-Json | Out-File -Encoding UTF8 $StateFile
    
    if ($failedFiles.Count -gt 0) {
        $failedByStation[$station.StationFolder] = $failedFiles
    }
    
    $totalSent += $stationSent
    $totalSize += $stationSize
    
    Write-Host "Station $($station.StationFolder): $stationSent files sent" -ForegroundColor Green
    
    Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Final summary
Write-Host "=== SUMMARY ===" -ForegroundColor Magenta

if ($config.DryRun -eq $true) {
    $message = "DryRun completed for $($yesterday.ToString('yyyy-MM-dd'))"
    Write-Host $message -ForegroundColor Green
} elseif ($failedByStation.Count -gt 0) {
    $message = "Upload completed with some failures - $($yesterday.ToString('yyyy-MM-dd'))"
    Send-Telegram $message
    Write-Host $message -ForegroundColor Yellow
} else {
    $sizeMB = [Math]::Round($totalSize / 1MB, 2)
    $message = "Upload completed successfully - $($yesterday.ToString('yyyy-MM-dd'))`nFiles: $totalSent`nSize: $sizeMB MB"
    Send-Telegram $message
    Write-Host "All uploads successful!" -ForegroundColor Green
}

Write-Host "Script completed at $(Get-Date)" -ForegroundColor Cyan
