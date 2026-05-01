#!/usr/bin/env pwsh
# ============================================================
#  Megabyte Systems - Commit Tag Tool (mct)
#  mct         - show usage and exit
#  mct tag     - interactive tag builder
# ============================================================
# Executable the script ./mct.ps1 in your powershell 
# and it should install in your system globallu
# No admin access needed for executing this script
# ============================================================
# v1.7.6

param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$Command
)

# ── ANSI palette ──────────────────────────────────────────────
$E    = [char]27
$RST  = "$E[0m"
$CYN  = "$E[96m"       # bright cyan     – titles
$WHT  = "$E[97m"       # bright white    – filter text
$GRY  = "$E[90m"       # dark gray       – hints
$GRN  = "$E[92m"       # bright green    – selection summary
$HLFG = "$E[30m$E[46m" # black on cyan   – cursor highlight row
$CLRDN= "$E[J"         # clear from cursor to bottom of screen

# ── Self-Install ─────────────────────────────────────────────
$toolsDir   = "$env:USERPROFILE\.megabyte-tools"
$scriptDest = Join-Path $toolsDir "mct.ps1"
$cmdWrapper = Join-Path $toolsDir "mct.cmd"
$thisScript = $MyInvocation.MyCommand.Path
$installNeeded = $false

if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $installNeeded = $true
}

if ($thisScript -and $thisScript -ne $scriptDest) {
    $srcHash   = (Get-FileHash $thisScript -Algorithm MD5).Hash
    $dstExists = Test-Path $scriptDest
    $dstHash   = if ($dstExists) { (Get-FileHash $scriptDest -Algorithm MD5).Hash } else { "" }
    if (-not $dstExists -or $srcHash -ne $dstHash) {
        Copy-Item -Path $thisScript -Destination $scriptDest -Force
        $installNeeded = $true
    }
}

if (-not (Test-Path $cmdWrapper)) {
    Set-Content -Path $cmdWrapper `
        -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptDest`" %*"
    $installNeeded = $true
}

$curPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($curPath -notlike "*$toolsDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$curPath;$toolsDir", "User")
    $env:PATH = "$env:PATH;$toolsDir"
    $installNeeded = $true
}

$profilePath = $PROFILE.CurrentUserAllHosts
$aliasLine   = "Set-Alias -Name mct -Value `"$scriptDest`""
if (Test-Path $profilePath) {
    $pc = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    $needsAlias = $pc -notlike "*Set-Alias -Name mct*"
} else { $needsAlias = $true }
if ($needsAlias) {
    if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }
    Add-Content -Path $profilePath -Value "`r`n# Megabyte Systems - Commit Tag Tool`r`n$aliasLine"
    $installNeeded = $true
}

if ($installNeeded) {
    Write-Host ""
    Write-Host "  [SETUP] mct installed/updated at: $toolsDir" -ForegroundColor DarkCyan
    Write-Host "  [SETUP] You can now run 'mct' from anywhere." -ForegroundColor DarkCyan
    Write-Host "  [SETUP] Restart terminal if this is the first install." -ForegroundColor DarkCyan
    Write-Host ""
}

# ── Usage banner (always printed) ────────────────────────────
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Megabyte Systems - Commit Tag Tool (mct)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  USAGE:" -ForegroundColor Yellow
Write-Host "    mct tag" -ForegroundColor White
Write-Host ""
Write-Host "  WHAT IT DOES:" -ForegroundColor Yellow
Write-Host "    1. Fuzzy-pick object type  (Executable / Dependent)" -ForegroundColor DarkGray
Write-Host "    2. Fuzzy-pick person(s)    (multi-select; Routine is exclusive)" -ForegroundColor DarkGray
Write-Host "    3. Copies the NPT-630 tag string to clipboard" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  OUTPUT FORMATS:" -ForegroundColor Yellow
Write-Host "    (NPT-630) Signed Executable Objects for [Name(s)]" -ForegroundColor DarkGray
Write-Host "    (NPT-630) Signed Dependent Objects for [Name(s)]" -ForegroundColor DarkGray
Write-Host "    (NPT-630) Routine Signed Executable Objects" -ForegroundColor DarkGray
Write-Host "    (NPT-630) Routine Signed Dependent Objects" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  CONTROLS:" -ForegroundColor Yellow
Write-Host "    Type       Filter items in real-time" -ForegroundColor DarkGray
Write-Host "    Backspace  Remove last filter character" -ForegroundColor DarkGray
Write-Host "    Up/Down    Move cursor" -ForegroundColor DarkGray
Write-Host "    Space      Toggle selection (step 2 only)" -ForegroundColor DarkGray
Write-Host "    Enter      Confirm  (auto-picks highlighted if nothing toggled)" -ForegroundColor DarkGray
Write-Host "    Esc        Cancel" -ForegroundColor DarkGray
Write-Host ""

if ($Command -ne "tag") { exit 0 }

# ══════════════════════════════════════════════════════════════
#  CONSOLE UI ENGINE
#
#  All rendering goes through a single [Console]::Write() call
#  per frame (no Write-Host in the loop).  Frames overwrite
#  themselves in-place via ESC[nA (move cursor up n lines),
#  then ESC[J (clear to end of screen) after the new content.
#
#  Make-Line pads pure-text to terminal width BEFORE applying
#  ANSI color codes so that PadRight() never miscounts escape
#  characters as visible characters.
# ══════════════════════════════════════════════════════════════

function Make-Line {
    param([string]$txt = "", [string]$clr = "", [switch]$hl)
    $w   = [Math]::Max(10, [Console]::WindowWidth - 1)
    # Pad/truncate on the raw text (no ANSI) so width is exact
    $vis = if ($txt.Length -ge $w) { $txt.Substring(0, $w) } else { $txt.PadRight($w) }
    if ($hl)   { return "$HLFG$vis$RST" }   # black text, cyan bg
    if ($clr)  { return "$clr$vis$RST"   }   # caller-supplied color
    return $vis                               # no color (terminal default)
}

# ── Generic fuzzy picker ──────────────────────────────────────
# $Multi = $false  -  single-select (arrow + Enter; Space ignored)
# $Multi = $true   -  multi-select  (Space to toggle; Enter to commit)
# "Routine" in multi mode is mutually exclusive with all other picks
function Invoke-FuzzyPicker {
    param(
        [string[]]$Items,
        [string]  $Title,
        [switch]  $Multi
    )

    $sel        = [System.Collections.Generic.HashSet[int]]::new()
    $filter     = ""
    $cursor     = 0
    $prevLines  = 0
    $routineIdx = [Array]::IndexOf($Items, "Routine")
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            # ── 1. Build filtered view ────────────────────────
            $fLow = $filter.ToLower()
            $vis  = [System.Collections.Generic.List[pscustomobject]]::new($Items.Count)
            for ($i = 0; $i -lt $Items.Count; $i++) {
                if ($filter.Length -eq 0 -or $Items[$i].ToLower().Contains($fLow)) {
                    $vis.Add([pscustomobject]@{ I = $i; N = $Items[$i] })
                }
            }
            if ($vis.Count -eq 0)           { $cursor = 0 }
            elseif ($cursor -ge $vis.Count) { $cursor = $vis.Count - 1 }

            # ── 2. Render one frame ───────────────────────────
            $w  = [Math]::Max(10, [Console]::WindowWidth - 1)
            $sb = [System.Text.StringBuilder]::new(($w + 16) * ($vis.Count + 9))
            $ln = 0
            if ($prevLines -gt 0) { [void]$sb.Append("$E[${prevLines}A") }
            [void]$sb.Append((Make-Line "  $Title" $CYN)); [void]$sb.Append("`r`n"); $ln++
            [void]$sb.Append((Make-Line ""));               [void]$sb.Append("`r`n"); $ln++
            [void]$sb.Append((Make-Line "  Search: $filter`_" $WHT)); [void]$sb.Append("`r`n"); $ln++
            [void]$sb.Append((Make-Line ""));                          [void]$sb.Append("`r`n"); $ln++
            if ($vis.Count -eq 0) {
                [void]$sb.Append((Make-Line "  (no matches)" $GRY)); [void]$sb.Append("`r`n"); $ln++
            } else {
                for ($i = 0; $i -lt $vis.Count; $i++) {
                    $v    = $vis[$i]
                    $isHl = ($i -eq $cursor)
                    if ($Multi) {
                        $chk = if ($sel.Contains($v.I)) { "[x]" } else { "[ ]" }
                        $txt = "  $chk  $($v.N)"
                    } else {
                        $pfx = if ($isHl) { " > " } else { "   " }
                        $txt = "  $pfx$($v.N)"
                    }
                    [void]$sb.Append((Make-Line $txt "" -hl:$isHl)); [void]$sb.Append("`r`n"); $ln++
                }
            }
            [void]$sb.Append((Make-Line "")); [void]$sb.Append("`r`n"); $ln++
            if ($Multi) {
                $sn = @($sel | Sort-Object | ForEach-Object { $Items[$_] })
                $ss = if ($sn.Count -gt 0) { "  Selected: $($sn -join ', ')" } else { "  Selected: (none)" }
                [void]$sb.Append((Make-Line $ss $GRN)); [void]$sb.Append("`r`n"); $ln++
                [void]$sb.Append((Make-Line ""));        [void]$sb.Append("`r`n"); $ln++
            }
            $hint = if ($Multi) {
                "  Type=filter  Up/Down=move  Space=toggle  Enter=confirm  Esc=cancel"
            } else {
                "  Type=filter  Up/Down=move  Enter=select  Esc=cancel"
            }
            [void]$sb.Append((Make-Line $hint $GRY)); [void]$sb.Append("`r`n"); $ln++
            [void]$sb.Append($CLRDN)
            [Console]::Write($sb.ToString())
            $prevLines = $ln

            # ── 3. Process one keypress ───────────────────────
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {

                "UpArrow"   { if ($cursor -gt 0) { $cursor-- } }
                "DownArrow" { if ($cursor -lt $vis.Count - 1) { $cursor++ } }

                "Backspace" {
                    if ($filter.Length -gt 0) {
                        $filter = $filter.Substring(0, $filter.Length - 1)
                        $cursor = 0
                    }
                }

                "Spacebar" {
                    if ($Multi -and $vis.Count -gt 0) {
                        $oi = $vis[$cursor].I
                        if ($sel.Contains($oi)) {
                            [void]$sel.Remove($oi)
                        } elseif ($Items[$oi] -eq "Routine") {
                            $sel.Clear()
                            [void]$sel.Add($oi)
                        } else {
                            if ($routineIdx -ge 0) { [void]$sel.Remove($routineIdx) }
                            [void]$sel.Add($oi)
                        }
                    }
                }

                "Enter" {
                    if ($Multi) {
                        if ($sel.Count -eq 0 -and $vis.Count -gt 0) {
                            [void]$sel.Add($vis[$cursor].I)
                        }
                        if ($sel.Count -gt 0) {
                            [Console]::Write("$E[${prevLines}A$CLRDN")
                            return @($sel | Sort-Object | ForEach-Object { $Items[$_] })
                        }
                    } else {
                        if ($vis.Count -gt 0) {
                            [Console]::Write("$E[${prevLines}A$CLRDN")
                            return $vis[$cursor].N
                        }
                    }
                }

                "Escape" {
                    [Console]::Write("$E[${prevLines}A$CLRDN")
                    return $null
                }

                default {
                    if ([char]::IsLetterOrDigit($key.KeyChar)) {
                        $filter += $key.KeyChar
                        $cursor  = 0
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# ── Name list formatter ───────────────────────────────────────
function Format-NameList([string[]]$n) {
    switch ($n.Count) {
        0       { return "" }
        1       { return $n[0] }
        2       { return "$($n[0]) & $($n[1])" }
        default {
            $j  = $n -join ", "
            $lc = $j.LastIndexOf(", ")
            return $j.Substring(0, $lc) + " & " + $j.Substring($lc + 2)
        }
    }
}

# ══════════════════════════════════════════════════════════════
#  STEP 1 – Object type  (single-select, fuzzy)
# ══════════════════════════════════════════════════════════════
Write-Host "  Starting tag builder..." -ForegroundColor DarkCyan
Write-Host ""

$typeOptions = @(
    "(NPT-630) Signed Executable Objects for ...",
    "(NPT-630) Signed Dependent Objects for ..."
)

$chosenType = Invoke-FuzzyPicker -Items $typeOptions -Title "Step 1 of 2  -  Object type"

if (-not $chosenType) {
    Write-Host "  Cancelled." -ForegroundColor DarkGray; Write-Host ""; exit 0
}

$objectWord = if ($chosenType -like "*Executable*") { "Executable" } else { "Dependent" }
Write-Host ""

# ══════════════════════════════════════════════════════════════
#  STEP 2 – Person(s)  (multi-select, fuzzy)
# ══════════════════════════════════════════════════════════════
$people = @("Aran", "Josmi", "Cam", "Jacobo", "Rhett", "Jerry", "Sunny", "Routine")

$chosenPeople = Invoke-FuzzyPicker -Items $people -Title "Step 2 of 2  -  Person(s)" -Multi

if (-not $chosenPeople) {
    Write-Host "  Cancelled." -ForegroundColor DarkGray; Write-Host ""; exit 0
}

Write-Host ""

# ══════════════════════════════════════════════════════════════
#  BUILD TAG + COPY TO CLIPBOARD
# ══════════════════════════════════════════════════════════════
if ($chosenPeople.Count -eq 1 -and $chosenPeople[0] -eq "Routine") {
    $tag = "(NPT-630) Routine Signed $objectWord Objects"
} else {
    $names = @($chosenPeople | Where-Object { $_ -ne "Routine" })
    $tag   = "(NPT-630) Signed $objectWord Objects for $(Format-NameList $names)"
}

Set-Clipboard -Value $tag

Write-Host "  +-------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |  TAG COPIED TO CLIPBOARD                        |" -ForegroundColor Cyan
Write-Host "  +-------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  $tag" -ForegroundColor Green
Write-Host ""
Write-Host "  Paste with Ctrl+V." -ForegroundColor DarkCyan
Write-Host ""
