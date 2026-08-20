#!/usr/bin/env pwsh
# ============================================================
#  Megabyte Systems - Sign & Deploy Tool (mvt)
#  Deploys an executable, waits for VICTL105 to sign it, then checks
#  the signed copy in to TFS
#  Self-installing: ensures it's on PATH every run
# ============================================================

param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$ExePath
)

$script:DepTabWidth = 4
$script:TfExePath = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\tf.exe"
$script:TfScopeRoot = "C:\TFS\MPTS2015\MPTS 2015 Development\24. Executables"

# ── Self-Install ─────────────────────────────────────────────
$toolsDir = "$env:USERPROFILE\.megabyte-tools"
$scriptName = "mvt.ps1"
$scriptDest = Join-Path $toolsDir $scriptName
$cmdWrapper = Join-Path $toolsDir "mvt.cmd"
$thisScript = $MyInvocation.MyCommand.Path
$installNeeded = $false

if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $installNeeded = $true
}

if ($thisScript -and $thisScript -ne $scriptDest) {
    $sourceHash = (Get-FileHash $thisScript -Algorithm MD5).Hash
    $destExists = Test-Path $scriptDest
    $destHash = if ($destExists) { (Get-FileHash $scriptDest -Algorithm MD5).Hash } else { "" }
    if (-not $destExists -or $sourceHash -ne $destHash) {
        Copy-Item -Path $thisScript -Destination $scriptDest -Force
        $installNeeded = $true
    }
}

if (-not (Test-Path $cmdWrapper)) {
    $cmdContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptDest`" %*"
    Set-Content -Path $cmdWrapper -Value $cmdContent
    $installNeeded = $true
}

$currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentUserPath -notlike "*$toolsDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentUserPath;$toolsDir", "User")
    $env:PATH = "$env:PATH;$toolsDir"
    $installNeeded = $true
}

$profilePath = $PROFILE.CurrentUserAllHosts
$aliasLine = "Set-Alias -Name mvt -Value `"$scriptDest`""
$needsAlias = $false

if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -notlike "*Set-Alias -Name mvt*") {
        $needsAlias = $true
    }
}
else {
    $needsAlias = $true
}
if ($needsAlias) {
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }
    Add-Content -Path $profilePath -Value "`r`n# Megabyte Systems - Sign & Deploy Tool`r`n$aliasLine"
    $installNeeded = $true
}
if ($installNeeded) {
    Write-Host ""
    Write-Host "  [SETUP] mvt installed/updated at: $toolsDir" -ForegroundColor DarkCyan
    Write-Host "  [SETUP] You can now run 'mvt' from anywhere." -ForegroundColor DarkCyan
    Write-Host "  [SETUP] Restart terminal if this is the first install." -ForegroundColor DarkCyan
    Write-Host ""
}

# ── show usage and exit ──────────────────────
if (-not $ExePath) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Megabyte Systems - Sign & Deploy (mvt)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    mvt <path-to-exe>" -ForegroundColor White
    Write-Host ""
    Write-Host "  EXAMPLE:" -ForegroundColor Yellow
    Write-Host "    mvt ""C:\TFS\...\Release\AUW5625SR.exe""" -ForegroundColor White
    Write-Host ""
    Write-Host "  WHAT IT DOES:" -ForegroundColor Yellow
    Write-Host "    1. Validates the .exe is in a Release folder" -ForegroundColor DarkGray
    Write-Host "    2. TFS Get Latest on 24. Executables" -ForegroundColor DarkGray
    Write-Host "    3. Checks for duplicate executables" -ForegroundColor DarkGray
    Write-Host "    4. (Optional) NuGet DLL workflow:" -ForegroundColor DarkGray
    Write-Host "         - Scans csproj for NuGet-sourced DLL references (HintPath + PackageReference)" -ForegroundColor DarkGray
    Write-Host "         - Asks before adding DL rows to [Screen] Dependency.txt" -ForegroundColor DarkGray
    Write-Host "         - Copies DLLs to 24. Executables\DLL (per-DLL confirm)" -ForegroundColor DarkGray
    Write-Host "         - Copies DLLs to \\dev1\MPTS\Prod\BIN2015\libs (per-DLL confirm)" -ForegroundColor DarkGray
    Write-Host "         - WebView2 / System.Text.Json get version folders" -ForegroundColor DarkGray
    Write-Host "    5. Copies the unsigned exe to dev1 + dev3 right away" -ForegroundColor DarkGray
    Write-Host "    6. Sends the exe to VICTL105 for signing" -ForegroundColor DarkGray
    Write-Host "    7. Polls every 1 min until the VICTL105 copy is signed" -ForegroundColor DarkGray
    Write-Host "    8. Re-copies the signed exe to dev1 + dev3 + local 24. Executables" -ForegroundColor DarkGray
    Write-Host "    9. Checks that file in to TFS as '(NPT-630) Signed <name> by Arfaz'" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  PROMPTS:" -ForegroundColor Yellow
    Write-Host "    Only y/yy/Y... or n/nn/N... are accepted." -ForegroundColor DarkGray
    Write-Host "    Blank Enter, 'yes', 'no', typos -> re-prompt." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Helper Functions ─────────────────────────────────────────
function Write-Step([string]$msg) {
    Write-Host "  >> $msg" -ForegroundColor Yellow
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Err([string]$msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

function Write-Warn([string]$msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor DarkYellow
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $ans = Read-Host $Prompt
        $t = if ($null -eq $ans) { "" } else { $ans.Trim() }
        if ($t -match '^[Yy]+$') { return $true }
        if ($t -match '^[Nn]+$') { return $false }
        Write-Host "    Please answer with y/yy/Y... or n/nn/N..." -ForegroundColor DarkGray
    }
}

function Invoke-TfOp {
    param(
        [Parameter(Mandatory)][ValidateSet('add', 'delete', 'checkin')][string]$Operation,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Recursive,
        [string]$Comment
    )
    $full = try { [IO.Path]::GetFullPath($Path) } catch { $Path }
    if (-not $full.StartsWith($script:TfScopeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    if (-not (Test-Path $script:TfExePath)) {
        Write-Warn "tf.exe not found; skipping 'tf $Operation' on $full"
        return $null
    }
    $tfArgs = @($Operation, $full)
    if ($Operation -eq 'checkin' -and $Comment) { $tfArgs += "/comment:$Comment" }
    $tfArgs += '/noprompt'
    if ($Recursive) { $tfArgs += '/recursive' }
    $out = & $script:TfExePath @tfArgs 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}

# ── Dependency / NuGet Helpers ───────────────────────────────
function Get-VisualPos {
    param([string]$Text, [int]$Tw = $script:DepTabWidth)
    $p = 0
    foreach ($c in $Text.ToCharArray()) {
        if ($c -eq "`t") { $p = [Math]::Floor($p / $Tw) * $Tw + $Tw } else { $p++ }
    }
    return $p
}

function New-DepDllLine {
    param([string]$Template, [string]$Name, [string]$Version)
    if ($Template -notmatch '^(\S+)(\s+)(\S+)(\s+)(\S+)(\s+)(\S+)(\s+)(\S+)\s*$') { return $null }
    $prefixToDb = "$($Matches[1])$($Matches[2])"
    $prefixToName = "$prefixToDb$($Matches[3])$($Matches[4])"
    $prefixToVer = "$prefixToName$($Matches[5])$($Matches[6])"
    $prefixToGrp = "$prefixToVer$($Matches[7])$($Matches[8])"
    $dbPos = Get-VisualPos $prefixToDb
    $namePos = Get-VisualPos $prefixToName
    $verPos = Get-VisualPos $prefixToVer
    $grpPos = Get-VisualPos $prefixToGrp
    $line = "DL"
    $line += " " * [Math]::Max(1, $dbPos - $line.Length)
    $line += "N/A"
    $line += " " * [Math]::Max(1, $namePos - $line.Length)
    $line += $Name
    $line += " " * [Math]::Max(1, $verPos - $line.Length)
    $line += $Version
    $line += " " * [Math]::Max(1, $grpPos - $line.Length)
    $line += "1"
    return $line
}

function Get-NuGetRefs {
    param([string]$CsprojPath)
    $out = [System.Collections.Generic.List[pscustomobject]]::new()
    if (-not (Test-Path $CsprojPath)) { return $out.ToArray() }
    try { [xml]$x = Get-Content $CsprojPath -Raw } catch { return $out.ToArray() }
    $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
    $ns.AddNamespace("m", "http://schemas.microsoft.com/developer/msbuild/2003")
    $csprojDir = Split-Path $CsprojPath -Parent

    # Classic (packages-folder) References — HintPath pointing into packages\
    $refs = $x.SelectNodes("//m:Reference[m:HintPath]", $ns)
    foreach ($r in $refs) {
        $hp = $r.SelectSingleNode("m:HintPath", $ns).InnerText
        if ($hp -notmatch '(^|\\)packages\\') { continue }
        try {
            $abs = [IO.Path]::GetFullPath((Join-Path $csprojDir $hp))
            if (-not (Test-Path $abs)) { continue }
            $an = [Reflection.AssemblyName]::GetAssemblyName($abs)
            $out.Add([pscustomobject]@{
                    Name       = [IO.Path]::GetFileNameWithoutExtension($abs)
                    Version    = $an.Version.ToString()
                    FileName   = [IO.Path]::GetFileName($abs)
                    SourcePath = $abs
                })
        }
        catch { }
    }

    # SDK-style PackageReference — resolve DLLs from the NuGet global cache.
    # Uses "//m:PackageReference" for classic csproj with MSBuild namespace,
    # and "//PackageReference" for SDK-style csproj (no default namespace).
    $pkgRefNodes = [System.Collections.Generic.List[System.Xml.XmlNode]]::new()
    foreach ($node in $x.SelectNodes("//m:PackageReference", $ns)) { $pkgRefNodes.Add($node) }
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($node in $pkgRefNodes) { [void]$seenIds.Add($node.GetAttribute("Include")) }
    foreach ($node in $x.SelectNodes("//PackageReference")) {
        if ($seenIds.Add($node.GetAttribute("Include"))) { $pkgRefNodes.Add($node) }
    }

    if ($pkgRefNodes.Count -gt 0) {
        $nugetCache = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES }
                      else { Join-Path $env:USERPROFILE ".nuget\packages" }

        # Determine the project's target framework for TFM folder selection.
        $projTfm = ""
        $tfwNode = $x.SelectSingleNode("//m:TargetFrameworkVersion", $ns)
        if (-not $tfwNode) { $tfwNode = $x.SelectSingleNode("//TargetFrameworkVersion") }
        if ($tfwNode) {
            # v4.8 -> net48
            $projTfm = "net" + ($tfwNode.InnerText -replace '^v', '' -replace '\.', '')
        } else {
            $tfNode = $x.SelectSingleNode("//m:TargetFramework", $ns)
            if (-not $tfNode) { $tfNode = $x.SelectSingleNode("//TargetFramework") }
            if ($tfNode) { $projTfm = ($tfNode.InnerText.Trim() -split ';')[0] }
        }

        # TFM preference order: project TFM first, then common .NET Framework TFMs.
        $tfmPriority = @()
        if ($projTfm) { $tfmPriority += $projTfm }
        $tfmPriority += @("net48","net472","net471","net47","net462","net461","net46","net452","net451","net45","net40","netstandard2.0","netstandard1.6","netstandard1.0")

        foreach ($pr in $pkgRefNodes) {
            $pkgId  = $pr.GetAttribute("Include")
            $pkgVer = $pr.GetAttribute("Version")
            if (-not $pkgId -or -not $pkgVer) { continue }

            $pkgVerDir = Join-Path $nugetCache (Join-Path ($pkgId.ToLower()) $pkgVer)
            if (-not (Test-Path $pkgVerDir)) { continue }

            $libDir = Join-Path $pkgVerDir "lib"
            if (-not (Test-Path $libDir)) { continue }

            # Pick the best matching TFM folder.
            $chosenDir = $null
            foreach ($t in $tfmPriority) {
                $d = Join-Path $libDir $t
                if (Test-Path $d) { $chosenDir = $d; break }
            }
            if (-not $chosenDir) {
                # Fall back to the alphabetically last TFM dir (usually highest version).
                $dirs = Get-ChildItem $libDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
                if ($dirs) { $chosenDir = $dirs[0].FullName }
            }
            if (-not $chosenDir) { continue }

            foreach ($dll in (Get-ChildItem $chosenDir -Filter "*.dll" -File -ErrorAction SilentlyContinue)) {
                if ($out | Where-Object { $_.Name -eq $dll.BaseName }) { continue }
                try {
                    $an = [Reflection.AssemblyName]::GetAssemblyName($dll.FullName)
                    $out.Add([pscustomobject]@{
                        Name       = $dll.BaseName
                        Version    = $an.Version.ToString()
                        FileName   = $dll.Name
                        SourcePath = $dll.FullName
                    })
                } catch { }
            }
        }
    }

    return ($out | Sort-Object Name, Version -Unique)
}

function Test-IsVersionedDll {
    param([string]$Name)
    return ($Name -like "Microsoft.Web.WebView2*") -or ($Name -like "System.Text.Json*")
}

function Get-DllTargetPath {
    param([string]$Root, [pscustomobject]$Dll)
    if (Test-IsVersionedDll $Dll.Name) {
        return (Join-Path $Root (Join-Path $Dll.Name (Join-Path $Dll.Version $Dll.FileName)))
    }
    return (Join-Path $Root $Dll.FileName)
}

function Get-DllVersion {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $an = [Reflection.AssemblyName]::GetAssemblyName($Path)
        return $an.Version.ToString()
    }
    catch {
        try { return (Get-Item $Path).VersionInfo.FileVersion } catch { return $null }
    }
}

function Test-VersionedFolderStructureExists {
    param([string]$Root, [string]$Name)
    $sub = Join-Path $Root $Name
    if (-not (Test-Path $sub -PathType Container)) { return $false }
    $vDirs = Get-ChildItem -Path $sub -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+(\.\d+){0,3}$' }
    return ($vDirs.Count -gt 0)
}

function Publish-DllsToRoot {
    param([string]$RootLabel, [string]$Root, [pscustomobject[]]$Dlls)
    if (-not (Test-Path $Root)) {
        Write-Warn "$RootLabel root not reachable: $Root"
        return
    }
    Write-Step "DLL moves to ${RootLabel}: $Root"
    if (-not (Read-YesNo "  Process DLL moves for $RootLabel? (Y/N)")) {
        Write-Host "  Skipped." -ForegroundColor DarkGray
        return
    }
    foreach ($d in $Dlls) {
        $flatPath = Join-Path $Root $d.FileName
        $versionedPath = Join-Path $Root (Join-Path $d.Name (Join-Path $d.Version $d.FileName))
        $isConfigVersioned = Test-IsVersionedDll $d.Name
        $hasVersionedTree = Test-VersionedFolderStructureExists -Root $Root -Name $d.Name

        if ($isConfigVersioned -or $hasVersionedTree) {
            if (Test-Path $versionedPath) {
                $existingVer = Get-DllVersion $versionedPath
                if (-not $existingVer) { $existingVer = $d.Version }
                Write-Host "  [EXISTS] $($d.Name) v$existingVer already at: $versionedPath" -ForegroundColor DarkGray
                continue
            }
            Write-Host ""
            Write-Host "  DLL     : $($d.FileName)" -ForegroundColor White
            Write-Host "  Version : $($d.Version)" -ForegroundColor White
            Write-Host "  Target  : $versionedPath" -ForegroundColor Gray
            if (Read-YesNo "  Add this DLL? (Y/N)") {
                $dir = Split-Path $versionedPath -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                try {
                    Copy-Item -Path $d.SourcePath -Destination $versionedPath -Force
                    Write-Ok "Added: $versionedPath"
                }
                catch {
                    Write-Err "Copy failed: $($_.Exception.Message)"
                }
            }
            continue
        }

        if (Test-Path $flatPath) {
            $existingVer = Get-DllVersion $flatPath
            if ($existingVer -eq $d.Version) {
                Write-Host "  [EXISTS] $($d.Name) v$existingVer already at: $flatPath" -ForegroundColor DarkGray
                continue
            }
            $shownExisting = if ($existingVer) { $existingVer } else { "unknown" }
            $oldVerForMove = if ($existingVer) { $existingVer } else { "unknown" }
            $oldVerPath = Join-Path $Root (Join-Path $d.Name (Join-Path $oldVerForMove $d.FileName))
            $newVerPath = Join-Path $Root (Join-Path $d.Name (Join-Path $d.Version    $d.FileName))

            Write-Host ""
            Write-Host "  [VERSION MISMATCH] $($d.Name) at $flatPath" -ForegroundColor Yellow
            Write-Host "    On disk  : $shownExisting" -ForegroundColor DarkGray
            Write-Host "    Required : $($d.Version)" -ForegroundColor White
            Write-Host "  Proposed migration to versioned subfolders:" -ForegroundColor Gray
            Write-Host "    Move existing -> $oldVerPath" -ForegroundColor DarkGray
            Write-Host "    Add new       -> $newVerPath" -ForegroundColor DarkGray
            if (Read-YesNo "  Migrate this DLL to versioned subfolders? (Y/N)") {
                $moved = $false
                try {
                    $oldDir = Split-Path $oldVerPath -Parent
                    if (-not (Test-Path $oldDir)) { New-Item -ItemType Directory -Path $oldDir -Force | Out-Null }
                    Move-Item -Path $flatPath -Destination $oldVerPath -Force
                    $moved = $true
                    Write-Ok "Moved old: $oldVerPath"
                    $newDir = Split-Path $newVerPath -Parent
                    if (-not (Test-Path $newDir)) { New-Item -ItemType Directory -Path $newDir -Force | Out-Null }
                    Copy-Item -Path $d.SourcePath -Destination $newVerPath -Force
                    Write-Ok "Added new: $newVerPath"
                }
                catch {
                    Write-Err "Migration failed: $($_.Exception.Message)"
                    if ($moved -and (Test-Path $oldVerPath) -and -not (Test-Path $flatPath)) {
                        try {
                            Move-Item -Path $oldVerPath -Destination $flatPath -Force
                            Write-Warn "Rolled back: restored original at $flatPath"
                        }
                        catch {
                            Write-Err "Rollback failed: $($_.Exception.Message). Manual fix needed at $oldVerPath."
                        }
                    }
                }
            }            
            continue
        }

        Write-Host ""
        Write-Host "  DLL     : $($d.FileName)" -ForegroundColor White
        Write-Host "  Version : $($d.Version)" -ForegroundColor White
        Write-Host "  Target  : $flatPath" -ForegroundColor Gray
        if (Read-YesNo "  Add this DLL? (Y/N)") {
            $dir = Split-Path $flatPath -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            try {
                Copy-Item -Path $d.SourcePath -Destination $flatPath -Force
                Write-Ok "Added: $flatPath"
            }
            catch {
                Write-Err "Copy failed: $($_.Exception.Message)"
            }
        }
    }
}

# ── Main ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Megabyte Systems - Sign & Deploy (mvt)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
$ExePath = [System.IO.Path]::GetFullPath($ExePath)

if (-not (Test-Path $ExePath)) {
    Write-Err "File not found: $ExePath"
    exit 1
}

if (-not $ExePath.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Err "File is not an .exe: $ExePath"
    exit 1
}

$parentFolder = Split-Path -Leaf (Split-Path $ExePath -Parent)
if ($ExePath -notmatch '\\Release\\' -and $parentFolder -ne "Release") {
    Write-Err "File is not in a 'Release' folder."
    Write-Err "Path: $ExePath"
    exit 1
}

$exeName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
$exeFile = [System.IO.Path]::GetFileName($ExePath)

Write-Host "  Executable : $exeFile" -ForegroundColor White
Write-Host "  Full Path  : $ExePath" -ForegroundColor DarkGray
Write-Host ""

$execSubfolder = $exeName.Substring(0, 2).ToUpper()
$executables24Path = "C:\TFS\MPTS2015\MPTS 2015 Development\24. Executables\$execSubfolder"
$executables24Root = "C:\TFS\MPTS2015\MPTS 2015 Development\24. Executables"
$victlSigningRoot = "\\VICTL105\Signing\MPTS 2015 Development\24. Executables"
$victlSigningPath = "$victlSigningRoot\$execSubfolder"

Write-Step "TFS Get Latest on 24. Executables..."
if (Test-Path $script:TfExePath) {
    try {
        $tfsProcess = Start-Process -FilePath $script:TfExePath `
            -ArgumentList "get `"$executables24Root`" /recursive /force" `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput "$env:TEMP\mvt_tfs_out.txt" `
            -RedirectStandardError "$env:TEMP\mvt_tfs_err.txt"
        $tfsOut = Get-Content "$env:TEMP\mvt_tfs_out.txt" -Raw -ErrorAction SilentlyContinue
        $tfsErr = Get-Content "$env:TEMP\mvt_tfs_err.txt" -Raw -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\mvt_tfs_out.txt", "$env:TEMP\mvt_tfs_err.txt" -Force -ErrorAction SilentlyContinue
        $tfsAll = "$tfsOut $tfsErr"        
        if ($tfsProcess.ExitCode -eq 0) {
            Write-Ok "TFS Get Latest completed."
        }
        elseif ($tfsAll -match "pending edit") {
            Write-Ok "TFS Get Latest completed."
            $pendingLines = ($tfsAll -split "`n") | Where-Object { $_ -match "pending edit" }
            foreach ($line in $pendingLines) {
                $fileName = $line.Trim()
                if ($line -match 'refresh\s+(.+?)\s+because') {
                    $fileName = $Matches[1]
                }
                Write-Host "    (skipped: $fileName - pending edit)" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Warn "TFS Get Latest returned exit code $($tfsProcess.ExitCode)."
            if ($tfsErr) { Write-Host "  $($tfsErr.Trim())" -ForegroundColor DarkGray }
        }
    }
    catch {
        Write-Warn "TFS Get Latest failed: $($_.Exception.Message)"
    }
}
else {
    Write-Warn "tf.exe not found. Skipping TFS Get Latest."
}
Write-Host ""
Write-Step "Scanning for duplicate copies of $exeFile in 24. Executables..."
$reportWrappersPath = Join-Path $executables24Root "ReportWrappers"
if (Test-Path $executables24Root) {
    $duplicates = Get-ChildItem -Path $executables24Root -Filter $exeFile -Recurse -File -ErrorAction SilentlyContinue
    if ($duplicates.Count -gt 0) {
        $rwDuplicates = $duplicates | Where-Object { $_.FullName -like "$reportWrappersPath\*" }
        $otherDuplicates = $duplicates | Where-Object { $_.FullName -notlike "$reportWrappersPath\*" }
        if ($rwDuplicates.Count -gt 0) {
            Write-Warn "Found $($rwDuplicates.Count) copy/copies in ReportWrappers (deprecated folder):"
            foreach ($dup in $rwDuplicates) {
                Write-Host "    - $($dup.FullName)" -ForegroundColor DarkYellow
                if (Read-YesNo "      Delete this file? (Y/N)") {
                    $delRes = Invoke-TfOp -Operation 'delete' -Path $dup.FullName
                    if ($delRes -and $delRes.ExitCode -eq 0) {
                        Write-Ok "tf delete queued: $($dup.FullName)"
                    }
                    else {
                        try {
                            Remove-Item -Path $dup.FullName -Force
                            Write-Ok "Deleted (untracked): $($dup.FullName)"
                        }
                        catch {
                            Write-Err "Could not delete: $($_.Exception.Message)"
                        }
                    }
                }
                else {
                    Write-Host "      Skipped." -ForegroundColor DarkGray
                }                
            }
        }
        if ($otherDuplicates.Count -gt 0) {
            Write-Warn "Found $($otherDuplicates.Count) copy/copies in other locations:"
            foreach ($dup in $otherDuplicates) {
                Write-Host "    - $($dup.FullName)" -ForegroundColor DarkYellow
            }
        }
    }
    else {
        Write-Ok "No existing copies of $exeFile found. This will be a fresh deploy."
    }
}
else {
    Write-Warn "24. Executables folder not found at: $executables24Root"
}
Write-Host ""

# ── NuGet DLL workflow (dep doc + TFS DLL folder + libs folder) ──
$exeDir = Split-Path $ExePath -Parent
$projectDir = Split-Path (Split-Path (Split-Path $exeDir -Parent) -Parent) -Parent
$csprojPath = Join-Path $projectDir "$exeName.csproj"
$depFile = Join-Path $projectDir "INSTALL\$exeName Dependency.txt"
$tfsDllRoot = "C:\TFS\MPTS2015\MPTS 2015 Development\24. Executables\DLL"
$libsRoot = "\\dev1\MPTS\Prod\BIN2015\libs"
$doDlls = $false
$depLines = $null

if (Test-Path $depFile) {
    $depLines = [IO.File]::ReadAllLines($depFile)
    $hasDL = @($depLines | Where-Object { $_ -match '^DL\s' }).Count -gt 0
    if ($hasDL) {
        Write-Step "Dependency doc already has DL entries."
        $doDlls = Read-YesNo "  Redo the NuGet DLL search? (Y/N)"
    }
    else {
        Write-Step "Dependency doc has no DL entries yet."
        $doDlls = Read-YesNo "  Run NuGet DLL search anyway? (Y/N)"
    }
}
else {
    Write-Warn "Dependency file not found: $depFile  (skipping DLL workflow)"
}

if ($doDlls) {
    Write-Host ""
    Write-Step "Scanning $exeName.csproj for NuGet-referenced DLLs..."
    $dlls = Get-NuGetRefs $csprojPath
    if (-not $dlls -or $dlls.Count -eq 0) {
        Write-Warn "No NuGet references found."
    }
    else {
        Write-Ok "Found $($dlls.Count) NuGet DLL reference(s)."
        foreach ($d in $dlls) { Write-Host ("    - {0,-45} {1}" -f $d.Name, $d.Version) -ForegroundColor DarkGray }
        Write-Host ""
        $hdrIdx = -1; $tmpl = $null; $lastDL = -1
        for ($i = 0; $i -lt $depLines.Length; $i++) {
            if ($hdrIdx -lt 0 -and $depLines[$i] -match '^\s*Type\s+Database\s+Name\s+Version\s+Install\s*Group') { $hdrIdx = $i }
            elseif ($hdrIdx -ge 0 -and $depLines[$i] -match '^(DL|SC)\s') {
                if ($null -eq $tmpl) { $tmpl = $depLines[$i] }
                if ($depLines[$i] -match '^DL\s') { $lastDL = $i }
            }
        }
        if ($hdrIdx -lt 0) {
            Write-Err "Could not locate header row in dep doc. Skipping dep doc edits."
        }
        else {
            $insertAt = if ($lastDL -ge 0) { $lastDL + 1 } else { $hdrIdx + 1 }
            $toAdd = New-Object System.Collections.Generic.List[string]
            $toUpdate = @{}
            foreach ($d in $dlls) {
                $nameEsc = [regex]::Escape($d.Name)
                $alreadyLine = $depLines | Where-Object { $_ -match "^DL\s+\S+\s+$nameEsc\s+" } | Select-Object -First 1
                if ($alreadyLine) {
                    $existingVer = ""
                    if ($alreadyLine -match "^DL\s+\S+\s+$nameEsc\s+(\S+)\s+") { $existingVer = $Matches[1] }
                    if ($existingVer -eq $d.Version) {
                        Write-Host "  [SKIP] $($d.Name) already in dep doc (v$existingVer)." -ForegroundColor DarkGray
                        continue
                    }
                    $newLine = if ($tmpl) { New-DepDllLine -Template $tmpl -Name $d.Name -Version $d.Version }
                    else { "DL`tN/A`t$($d.Name)`t$($d.Version)`t1" }
                    Write-Host ""
                    Write-Host "  [VERSION MISMATCH] $($d.Name) in dep doc" -ForegroundColor Yellow
                    Write-Host "    Existing : $existingVer" -ForegroundColor DarkGray
                    Write-Host "    New      : $($d.Version)" -ForegroundColor White
                    Write-Host "  Proposed update:" -ForegroundColor Gray
                    Write-Host "  $newLine" -ForegroundColor Green
                    if (Read-YesNo "  Update this line in Dependency doc? (Y/N)") {
                        $toUpdate[$alreadyLine] = $newLine
                    }
                    continue
                }
                $line = if ($tmpl) { New-DepDllLine -Template $tmpl -Name $d.Name -Version $d.Version }
                else { "DL`tN/A`t$($d.Name)`t$($d.Version)`t1" }
                Write-Host ""
                Write-Host "  Proposed line:" -ForegroundColor Gray
                Write-Host "  $line" -ForegroundColor Green
                if (Read-YesNo "  Add this line to Dependency doc? (Y/N)") { $toAdd.Add($line) }
            }
            if ($toAdd.Count -gt 0 -or $toUpdate.Count -gt 0) {
                $combined = New-Object System.Collections.Generic.List[string]
                for ($i = 0; $i -lt $depLines.Length; $i++) {
                    $cur = $depLines[$i]
                    if ($toUpdate.ContainsKey($cur)) { $combined.Add($toUpdate[$cur]) } else { $combined.Add($cur) }
                    if ($i -eq ($insertAt - 1)) { foreach ($nl in $toAdd) { $combined.Add($nl) } }
                }
                $origRaw = [IO.File]::ReadAllText($depFile)
                $eol = if ($origRaw -match "`r`n") { "`r`n" } else { "`n" }
                [IO.File]::WriteAllText($depFile, ($combined -join $eol) + $eol, [Text.UTF8Encoding]::new($false))
                $msg = ""
                if ($toAdd.Count -gt 0) { $msg += "$($toAdd.Count) new" }
                if ($toUpdate.Count -gt 0) { if ($msg) { $msg += ", " }; $msg += "$($toUpdate.Count) updated" }
                Write-Ok "Dependency doc updated: $msg DL row(s)."
            }
            else {
                Write-Host "  No DL rows added or updated in dep doc." -ForegroundColor DarkGray
            }        
        }
        Write-Host ""
        Publish-DllsToRoot -RootLabel "TFS DLL folder" -Root $tfsDllRoot -Dlls $dlls
        Write-Host ""
        Write-Step "Queueing TFS pending adds for new DLL files..."
        $tfAddOk = 0; $tfAddFail = 0
        foreach ($d in $dlls) {
            $target = Get-DllTargetPath -Root $tfsDllRoot -Dll $d
            if (-not (Test-Path $target)) { continue }
            $res = Invoke-TfOp -Operation 'add' -Path $target
            if ($res) {
                if ($res.ExitCode -eq 0) { Write-Ok "tf add: $target"; $tfAddOk++ }
                else {
                    # Already tracked (exit 1 with "no items match" or "already under TF") is OK — not a real failure.
                    $msg = ($res.Output -join " ").Trim()
                    if ($msg -match 'no items match|already under|cannot add' ) {
                        Write-Host "  [SKIP] Already tracked: $(Split-Path $target -Leaf)" -ForegroundColor DarkGray
                    } else {
                        Write-Warn "tf add failed for $target : $msg"
                        $tfAddFail++
                    }
                }
            }
        }
        if ($tfAddFail -gt 0) { Write-Warn "$tfAddFail tf add(s) failed — review pending changes in Team Explorer." }
        elseif ($tfAddOk -gt 0) { Write-Ok "$tfAddOk new DLL file(s) queued for add in TFS." }
        else { Write-Host "  All DLL files already tracked in TFS." -ForegroundColor DarkGray }
        Write-Host ""
        Publish-DllsToRoot -RootLabel "dev1 libs" -Root $libsRoot -Dlls $dlls
        Write-Host ""
    }
}
# ── end NuGet DLL workflow ───────────────────────────────────
Write-Host "  +-------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |  DEPLOYMENT DESTINATIONS                        |" -ForegroundColor Cyan
Write-Host "  +-------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. $victlSigningPath" -ForegroundColor White
Write-Host "     (signs in ~3-5 min, then checked in to $executables24Path)" -ForegroundColor DarkGray
Write-Host "  2. \\dev1\MPTS\Prod\BIN2015" -ForegroundColor White
Write-Host "  3. \\dev3\MPTS\Prod\BIN2015" -ForegroundColor White
Write-Host ""
if (-not (Read-YesNo "  Proceed with these destinations? (Y/N)")) {
    Write-Warn "Aborted by user."
    exit 0
}
Write-Host ""

function Copy-ExeToDestination {
    param([string]$Dest, [string]$Source, [string]$FileName)
    if (-not (Test-Path $Dest)) {
        Write-Warn "Destination folder does not exist. Creating: $Dest"
        try { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
        catch { Write-Err "Could not create folder: $($_.Exception.Message)"; return $false }
    }
    try {
        Copy-Item -Path $Source -Destination (Join-Path $Dest $FileName) -Force
        Write-Ok "Copied to $(Join-Path $Dest $FileName)"
        return $true
    }
    catch {
        Write-Err "Failed to copy to ${Dest}: $($_.Exception.Message)"
        return $false
    }
}

$devDestinations = @(
    "\\dev1\MPTS\Prod\BIN2015",
    "\\dev3\MPTS\Prod\BIN2015"
)

Write-Step "Copying unsigned $exeFile to dev1 + dev3..."
foreach ($dest in $devDestinations) { Copy-ExeToDestination -Dest $dest -Source $ExePath -FileName $exeFile | Out-Null }
Write-Host ""

Write-Step "Sending $exeFile to VICTL105 for signing..."
if (-not (Test-Path $victlSigningPath)) {
    try { New-Item -ItemType Directory -Path $victlSigningPath -Force | Out-Null }
    catch { Write-Err "Could not create folder: $($_.Exception.Message)"; exit 1 }
}
$victlFilePath = Join-Path $victlSigningPath $exeFile
try {
    Copy-Item -Path $ExePath -Destination $victlFilePath -Force
    Write-Ok "Sent to $victlFilePath"
}
catch {
    Write-Err "Failed to send to VICTL105: $($_.Exception.Message)"
    exit 1
}
Write-Host ""

# ── Poll VICTL105 until the copy is signed ─────────────────────
Write-Step "Waiting for VICTL105 to sign $exeFile (checking every 1 min)..."
$maxWaitMinutes = 15
$waitedMinutes = 0
$signed = $false
while (-not $signed) {
    Start-Sleep -Seconds 60
    $waitedMinutes++
    $sig = Get-AuthenticodeSignature -FilePath $victlFilePath -ErrorAction SilentlyContinue
    if ($sig -and $sig.Status -eq 'Valid') {
        $signed = $true
        Write-Ok "Signed after ~$waitedMinutes min."
        break
    }
    Write-Host "    ... still unsigned after $waitedMinutes min" -ForegroundColor DarkGray
    if ($waitedMinutes -ge $maxWaitMinutes) {
        Write-Warn "Still unsigned after $maxWaitMinutes min."
        if (-not (Read-YesNo "  Keep waiting? (Y/N)")) {
            Write-Warn "Aborted by user - copies at dev1/dev3/VICTL105 remain UNSIGNED. Nothing checked in."
            exit 1
        }
        $waitedMinutes = 0
    }
}
Write-Host ""

# ── Re-deploy the signed copy and check it in to TFS ────────────
Write-Step "Re-copying signed $exeFile to dev1 + dev3..."
foreach ($dest in $devDestinations) { Copy-ExeToDestination -Dest $dest -Source $victlFilePath -FileName $exeFile | Out-Null }
Write-Host ""

Write-Step "Copying signed $exeFile to local TFS workspace: $executables24Path"
$localCopyOk = Copy-ExeToDestination -Dest $executables24Path -Source $victlFilePath -FileName $exeFile
Write-Host ""

$localTfsPath = Join-Path $executables24Path $exeFile
$objLabel = if ([IO.Path]::GetExtension($exeFile) -ieq ".dll") { "DLL $exeName" } else { $exeName }
$checkinComment = "(NPT-630) Signed $objLabel by Arfaz"
$checkinOk = $false

if (-not $localCopyOk) {
    Write-Err "Signed copy to $localTfsPath failed - skipping TFS checkin. Copy it manually, then check in yourself."
}
else {
    Write-Step "Checking in $exeFile to TFS..."
    Invoke-TfOp -Operation 'add' -Path $localTfsPath | Out-Null
    $checkinRes = Invoke-TfOp -Operation 'checkin' -Path $localTfsPath -Comment $checkinComment
    $checkinOk = $checkinRes -and $checkinRes.ExitCode -eq 0
    if ($checkinOk) {
        Write-Ok "Checked in: $localTfsPath"
    }
    else {
        Write-Warn "tf checkin did not report success - review manually in Team Explorer."
        if ($checkinRes) { Write-Host "  $($checkinRes.Output -join "`n  ")" -ForegroundColor DarkGray }
    }
}
Write-Host ""

Write-Host "  +-------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |  SUMMARY                                        |" -ForegroundColor Cyan
Write-Host "  +-------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Executable  : $exeFile" -ForegroundColor White
Write-Host "  Signed      : Yes" -ForegroundColor Green
Write-Host "  Checked in  : $checkinComment" -ForegroundColor $(if ($checkinOk) { 'Green' } else { 'Yellow' })
Write-Host ""
Write-Host "  DEPLOYED TO:" -ForegroundColor Red
Write-Host "    $localTfsPath" -ForegroundColor Red
foreach ($dest in $devDestinations) {
    Write-Host "    $(Join-Path $dest $exeFile)" -ForegroundColor Red
}
Write-Host ""
Write-Host "  Done!" -ForegroundColor Green
Write-Host ""