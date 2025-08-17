
# filename=upload.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$config = Get-Content (Join-Path $ScriptDir 'config.json') -Raw | ConvertFrom-Json

$BinDir   = Join-Path $ScriptDir 'bin'
$TempDir  = Join-Path $BinDir 'temp'
$LogDir   = Join-Path $BinDir 'logs'
$StateDir = Join-Path $BinDir 'state'
$StateFile = Join-Path $StateDir 'sent-state.json'
$RetryFile = Join-Path $StateDir 'retry-queue.json'

New-Item -ItemType Directory -Force -Path $TempDir,$LogDir,$StateDir | Out-Null
if (-not (Test-Path $StateFile)) { '{}' | Out-File -Encoding UTF8 $StateFile }
if (-not (Test-Path $RetryFile)) { '[]' | Out-File -Encoding UTF8 $RetryFile }

function Write-Log($msg) {
  $logPath = Join-Path $LogDir ("upload_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Add-Content -Encoding UTF8 -Path $logPath -Value "[$timestamp] $msg"
}

function Send-Telegram($text) {
  try {
    $uri = "https://api.telegram.org/bot$($config.TelegramToken)/sendMessage"
    Invoke-RestMethod -Uri $uri -Method Post -Body @{ chat_id = $config.TelegramChatId; text = $text } | Out-Null
  } catch { Write-Log "Telegram send error: $($_.Exception.Message)" }
}

function Is-FileReady($path) {
  try { $fs = [System.IO.File]::Open($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read); $fs.Close(); return $true }
  catch { return $false }
}

function Load-RetryQueue { try { $raw = Get-Content $RetryFile -Raw; if ([string]::IsNullOrWhiteSpace($raw)) { return @() }; $arr = $raw | ConvertFrom-Json; if ($arr -is [System.Array]) { return $arr } else { return @() } } catch { return @() } }
function Save-RetryQueue($items) { ($items | ConvertTo-Json -Depth 5) | Out-File -Encoding UTF8 $RetryFile }
function Make-Key($fullPath, $ticks) { return "$fullPath||$ticks" }

# Rotate logs
Get-ChildItem $LogDir -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-[int]$config.LogRetentionDays) } | Remove-Item -Force -ErrorAction SilentlyContinue

# Collect yesterday files
$yesterday = (Get-Date).AddDays(-1).Date
$today     = (Get-Date).Date
$inc = @($config.IncludePatterns); if(-not $inc -or $inc.Count -eq 0){ $inc=@('*.*') }
$exc = @($config.ExcludePatterns)
$all = foreach($pat in $inc){ Get-ChildItem -Path $config.SourceFolder -Recurse -File -Filter $pat -ErrorAction SilentlyContinue }
$all = $all | Group-Object FullName | ForEach-Object { $_.Group[0] }
$filesYesterday = $all | Where-Object {
  $ok = $_.LastWriteTime -ge $yesterday -and $_.LastWriteTime -lt $today -and $_.Length -gt 0
  if($exc){ foreach($e in $exc){ if($_.Name -like $e){ $ok=$false } } }
  $ok
}

# Load retry queue
$retryQueue = Load-RetryQueue
$retryCandidates = @()
foreach($r in $retryQueue){
  $p = [string]$r.Path; $t = [int64]$r.Ticks
  if (Test-Path $p) {
    $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if ($fi -and (Is-FileReady $fi.FullName) -and $fi.Length -gt 0) {
      $state = Get-Content $StateFile -Raw | ConvertFrom-Json
      if ($null -eq $state) { $state = @{} }
      $key = Make-Key $fi.FullName $fi.LastWriteTimeUtc.Ticks
      if (-not $state.ContainsKey($key)) { $retryCandidates += $fi }
    }
  }
}

$state = Get-Content $StateFile -Raw | ConvertFrom-Json
if ($null -eq $state) { $state = @{} }

$todo = @()
foreach($f in $filesYesterday){
  $key = Make-Key $f.FullName $f.LastWriteTimeUtc.Ticks
  if (-not $state.ContainsKey($key) -and Is-FileReady $f.FullName) { $todo += $f }
}
$exist = [System.Collections.Generic.HashSet[string]]::new([string[]]($todo | ForEach-Object { $_.FullName }))
foreach($f in $retryCandidates){ if(-not $exist.Contains($f.FullName)){ $todo += $f; $exist.Add($f.FullName) } }

if(!$todo){ Write-Log "No files to upload."; exit 0 }

# staging
$stage = Join-Path $TempDir ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$StageMap = @{}
foreach($f in $todo){
  $rel = $f.FullName.Substring($config.SourceFolder.Length).TrimStart('\')
  $destDir = Split-Path -Parent (Join-Path $stage $rel)
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $stagedPath = Join-Path $stage $rel
  Copy-Item -Path $f.FullName -Destination $stagedPath -Force
  $StageMap[$stagedPath] = $f.FullName
}

$remoteDir = "/SMA-File-InFraTech/$($config.DeviceName)/$($yesterday.ToString('yyyy'))/$($yesterday.ToString('MM'))/$($yesterday.ToString('dd'))"

$wscp = @"
open ftp://$($config.FtpUser):$($config.FtpPass)@$($config.FtpHost):$($config.FtpPort) -passive=on
option batch on
option confirm off
option reconnecttime 120
option transfer binary
mkdir $remoteDir
cd $remoteDir
lcd "$stage"
put -resume *
exit
"@
$wscpFile = Join-Path $stage 'run.txt'; $wscp | Out-File -Encoding ASCII $wscpFile

$logFile = Join-Path $LogDir ("upload_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
$proc = Start-Process -FilePath $config.WinScpPath -ArgumentList "/script=$wscpFile","/log=$logFile" -PassThru -Wait
$exit = $proc.ExitCode

$logText = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
$failedStagePaths = @()
if ($null -ne $logText) {
  $m = [regex]::Matches($logText, "Error transferring file '([^']+)'")
  if ($m.Count -gt 0) { $failedStagePaths = $m | ForEach-Object { $_.Groups[1].Value } }
}
$failedOriginals = @(); foreach ($p in $failedStagePaths) { if ($StageMap.ContainsKey($p)) { $failedOriginals += $StageMap[$p] } }

$todoFullPaths = $todo | ForEach-Object { $_.FullName }
$failLookup = [System.Collections.Generic.HashSet[string]]::new([string[]]$failedOriginals)
$successSet = @(); foreach ($p in $todoFullPaths) { if (-not $failLookup.Contains($p)) { $successSet += $p } }

$queueMap = @{}; foreach($r in $retryQueue){ $queueMap[(Make-Key $r.Path $r.Ticks)] = $true }

$sentCount = 0; $sentSize = 0
foreach ($f in $todo) {
  $key = Make-Key $f.FullName $f.LastWriteTimeUtc.Ticks
  if ($successSet -contains $f.FullName) {
    $state[$key] = (Get-Date).ToString('s')
    $sentCount += 1; $sentSize += $f.Length
    if ($queueMap.ContainsKey($key)) { $queueMap.Remove($key) }
    Write-Log ("FILE OK   : {0} | size={1}" -f $f.FullName, $f.Length)
  } else {
    $queueMap[$key] = $true
    Write-Log ("FILE FAIL : {0} | size={1}" -f $f.FullName, $f.Length)
  }
}

$state | ConvertTo-Json -Depth 5 | Out-File -Encoding UTF8 $StateFile
$newRetry = @(); foreach ($k in $queueMap.Keys) { $parts = $k -split '\|\|',2; $newRetry += [pscustomobject]@{ Path = $parts[0]; Ticks = [int64]$parts[1] } }
Save-RetryQueue $newRetry

$mb = [Math]::Round(($sentSize/1MB),2)
if ($failedOriginals.Count -gt 0) {
  $maxShow = 30; $list = ($failedOriginals | Select-Object -First $maxShow) -join "`n - "; $more = ($failedOriginals.Count - $maxShow); if ($more -gt 0) { $list += "`n(+ $more more)" }
  $txt = @("❌ Upload FAILED (บางไฟล์) - $($yesterday.ToString('yyyy-MM-dd'))","Site: $($config.DeviceName)","RemoteDir: $remoteDir","ExitCode: $exit","Failed files:"," - $list") -join "`n"
  Write-Log $txt; Send-Telegram $txt
} else {
  $txt = @("✅ Upload OK - $($yesterday.ToString('yyyy-MM-dd'))","Site: $($config.DeviceName)","RemoteDir: $remoteDir","Files: $sentCount","Size(MB): $mb","ExitCode: $exit") -join "`n"
  Write-Log $txt; Send-Telegram $txt
}

Remove-Item -Path $stage -Recurse -Force -ErrorAction SilentlyContinue
