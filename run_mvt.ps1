# AGENT NOTE: run this file itself with pwsh, and it will spawn $Script (mvt.ps1)
# with pwsh too. Do not swap either pwsh.exe for powershell.exe - a powershell.exe
# child spawned this way (redirected stdio, no profile) fails to autoload
# Get-AuthenticodeSignature, which makes mvt.ps1 report "still unsigned" forever.
#   pwsh -NoProfile -File run_mvt.ps1 -Exe <path-to-exe> -Log <path-to-logfile> -Script <path-to-mvt.ps1>
# Safe to launch several of these in parallel - mvt.ps1 serializes its own tf.exe calls.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Log,
    [Parameter(Mandatory)][string]$Script,
    [int]$MaxMinutes = 40
)
$pwshExe = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path $pwshExe)) {
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "pwsh.exe not found (checked `$PSHOME and PATH)." }
    $pwshExe = $cmd.Source
}
if (-not (Test-Path $Script)) { throw "Script not found: $Script" }
if (-not (Test-Path $Exe)) { throw "Exe not found: $Exe" }

$logDir = Split-Path $Log -Parent
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $pwshExe
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" `"$Exe`""
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
$sb = New-Object Text.StringBuilder
$out = $p.StandardOutput; $buf = New-Object char[] 4096
$task = $out.ReadAsync($buf, 0, 4096)
$deadline = [DateTime]::UtcNow.AddMinutes($MaxMinutes)
$answeredAt = 0
"START $Exe $(Get-Date)" | Set-Content $Log
while (-not $p.HasExited -and [DateTime]::UtcNow -lt $deadline) {
  if ($task.Wait(1000)) {
    $n = $task.Result
    if ($n -le 0) { break }
    [void]$sb.Append($buf, 0, $n); Add-Content $Log (New-Object string($buf, 0, $n)) -NoNewline
    $task = $out.ReadAsync($buf, 0, 4096)
  }
  $t = $sb.ToString()
  if ($t.Length -gt $answeredAt) {
    $tail = $t.Substring($answeredAt)
    if ($tail -match '\(Y/N\)\s*:?\s*$') {
      $line = ($tail -split "`n")[-1]
      Add-Content $Log "`n<<< PROMPT: $($line.Trim())  ->  y >>>`n"
      $p.StandardInput.WriteLine('y'); $p.StandardInput.Flush()
      $answeredAt = $t.Length
    }
  }
}
if (-not $p.HasExited) { Add-Content $Log "`nTIMEOUT - stopping mvt"; Stop-Process -Id $p.Id -Force }
$p.WaitForExit(); Add-Content $Log "`nEXIT $($p.ExitCode) $(Get-Date)"
