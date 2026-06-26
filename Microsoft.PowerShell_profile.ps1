function treee {
	param(
	    [string]$Path = ".",
	    [int]$MaxDepth = 10,
	    [switch]$FollowReparsePoints,
	    [string[]]$HideExt = @()
	)

	try {
	    $FullPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
	} catch {
	    Write-Error "Path '$Path' not found."
	    exit 1
	}

	"Directory Tree for: $FullPath`n"

	$Visited = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

	function Show-Tree {
	    param(
		[string]$CurrentPath,
		[string]$Prefix = "",
		[bool]$IsLast = $true,
		[int]$Depth = 0
	    )
	    try {
		$Item = Get-Item -LiteralPath $CurrentPath -ErrorAction Stop
	    } catch {
		"$Prefix\-- (inaccessible or removed)"
		return
	    }

	    if ($Item.Name -match '^\.') {
		return
	    }

	    if (-not $Item.PSIsContainer -and $HideExt.Count -gt 0) {
		$ext = [System.IO.Path]::GetExtension($Item.Name)
		foreach ($h in $HideExt) {
		    if ($ext -ieq $h) { return }
		}
	    }

	    $realPath = $Item.FullName
	    if ($Visited.Contains($realPath)) {
		"$Prefix\-- $($Item.Name) (already visited)"
		return
	    }
	    $null = $Visited.Add($realPath)

	    $branch = if ($IsLast) { "\-- " } else { "|-- " }
	    "$Prefix$branch$($Item.Name)"

	    if (-not $Item.PSIsContainer) {
		return
	    }

	    if ($Depth -ge $MaxDepth) {
		$newPrefix = if ($IsLast) { "$Prefix    " } else { "$Prefix|   " }
		"$newPrefix\-- (max depth reached)"
		return
	    }

	    $NewPrefix = if ($IsLast) { "$Prefix    " } else { "$Prefix|   " }

	    try {
		$children = Get-ChildItem -LiteralPath $realPath -ErrorAction Stop |
		    Where-Object {
			$_.Name -notmatch '^\.' -and
			( $FollowReparsePoints -or -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) )
		    }

		if ($HideExt.Count -gt 0) {
		    $children = $children | Where-Object {
			if ($_.PSIsContainer) { return $true }
			$ext = [System.IO.Path]::GetExtension($_.Name)
			foreach ($h in $HideExt) {
			    if ($ext -ieq $h) { return $false }
			}
			return $true
		    }
		}

		$children = $children | Sort-Object -Property { if ($_.PSIsContainer) { "0$($_.Name)" } else { "1$($_.Name)" } }
	    } catch {
		"$NewPrefix\-- (cannot enumerate children)"
		return
	    }

	    $count = $children.Count
	    $i = 0
	    foreach ($child in $children) {
		$i++
		$isLastChild = ($i -eq $count)
		Show-Tree -CurrentPath $child.FullName -Prefix $NewPrefix -IsLast $isLastChild -Depth ($Depth + 1)
	    }
	}

	$output = Show-Tree -CurrentPath $FullPath -Depth 0
	$output | Set-Clipboard
	$output
}
. "C:\Users\AHussain\OneDrive - Megabyte Systems, Inc\Desktop\TFS to GIT\tree.ps1" 6>$null

# Unix-to-PowerShell aliases
Set-Alias grep    Select-String
Set-Alias which   Get-Command
function env     { Get-ChildItem Env: @args }
Set-Alias wc      Measure-Object
Set-Alias df      Get-PSDrive
Set-Alias uniq    Get-Unique
Set-Alias du      Get-ChildItem

function pbcopy   { $input | Set-Clipboard }
function pbpaste  { Get-Clipboard }
function touch    { New-Item -ItemType File -Path @($args, '.')[!$args] -Force }
function head     { Get-Content -TotalCount $args[0] @($args[1..$args.Count]) }
function tail     { Get-Content -Tail $args[0] @($args[1..$args.Count]) }
function find     { Get-ChildItem -Recurse @args }
function less     { $input | Out-Host -Paging }
function open     { Invoke-Item @args }

Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
Remove-Item Alias:mkdir -Force -ErrorAction SilentlyContinue
Remove-Item Alias:find -Force -ErrorAction SilentlyContinue
function _lsColor {
    param($Item)
    if ($Item.PSIsContainer -or ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return 'DarkYellow' }
        return 'Cyan'
    }
    if ($Item.Attributes -band [System.IO.FileAttributes]::Hidden) { return 'DarkGray' }
    if ($Item.Attributes -band [System.IO.FileAttributes]::System) { return 'DarkRed' }
    switch ($Item.Extension) {
        '.exe'   { return 'Green' }
        '.cmd'   { return 'Green' }
        '.bat'   { return 'Green' }
        '.ps1'   { return 'Green' }
        '.com'   { return 'Green' }
        '.zip'   { return 'Red' }
        '.rar'   { return 'Red' }
        '.7z'    { return 'Red' }
        '.tar'   { return 'Red' }
        '.gz'    { return 'Red' }
        '.jpg'   { return 'Magenta' }
        '.jpeg'  { return 'Magenta' }
        '.png'   { return 'Magenta' }
        '.gif'   { return 'Magenta' }
        '.bmp'   { return 'Magenta' }
        '.ico'   { return 'Magenta' }
        '.svg'   { return 'Magenta' }
        '.mp3'   { return 'Yellow' }
        '.wav'   { return 'Yellow' }
        '.flac'  { return 'Yellow' }
        '.mp4'   { return 'DarkYellow' }
        '.avi'   { return 'DarkYellow' }
        '.mkv'   { return 'DarkYellow' }
        '.mov'   { return 'DarkYellow' }
        default  { return 'White' }
    }
}

function _lsMode {
    param($Item)
    $m = if ($Item.PSIsContainer) { 'd' } else { '-' }
    $m += if ($Item.IsReadOnly) { 'r--' } else { 'rw-' }
    $m += if ($Item.Attributes -band [System.IO.FileAttributes]::System) { 's' } else { '-' }
    $m += if ($Item.Attributes -band [System.IO.FileAttributes]::Hidden) { 'h' } else { '-' }
    $m += if ($Item.PSIsContainer -or $Item.Extension -match '\.(exe|ps1|cmd|bat|com)') { 'x' } else { '-' }
    return $m
}

function _lsSize {
    param($Item, $Human)
    if ($Item.PSIsContainer) { return (' ' * 8) }
    $b = $Item.Length
    if (-not $Human) { return $b.ToString().PadLeft(8) }
    $s = if     ($b -ge 1GB) { '{0:N1}G' -f ($b/1GB) }
          elseif ($b -ge 1MB) { '{0:N1}M' -f ($b/1MB) }
          elseif ($b -ge 1KB) { '{0:N1}K' -f ($b/1KB) }
          else                { "$b" }
    return $s.PadLeft(8)
}

function _lsTime {
    param($Item)
    return $Item.LastWriteTime.ToString('MMM dd HH:mm')
}

function ls {
    param([string]$Path = ".")
    $all = $false; $long = $false; $time = $false; $reverse = $false; $human = $false; $size = $false
    $remaining = @()
    foreach ($a in $args) {
        if ($a -is [string] -and $a.StartsWith('-') -and $a.Length -gt 1) {
            $flat = $a.Substring(1)
            foreach ($c in $flat.ToCharArray()) {
                switch ($c) {
                    'a' { $all = $true }
                    'l' { $long = $true }
                    't' { $time = $true }
                    'r' { $reverse = $true }
                    'h' { $human = $true }
                    'S' { $size = $true }
                    default { $remaining += "-$c" }
                }
            }
        } else {
            $remaining += $a
        }
    }
    $params = @{}
    if ($all) { $params['Force'] = $true }
    $items = Get-ChildItem -Path $Path @params @remaining 2>$null
    if (-not $items) { $items = Get-ChildItem -LiteralPath $Path @params @remaining 2>$null }
    if (-not $items) { $items = Get-ChildItem @params @remaining }
    if ($time)  { $items = $items | Sort-Object LastWriteTime -Descending }
    if ($size)  { $items = $items | Sort-Object Length -Descending }
    if ($reverse -and $time) { $items = $items | Sort-Object LastWriteTime }
    if ($long) {
        foreach ($i in $items) {
            $c = _lsColor $i
            Write-Host "$(_lsMode $i) " -NoNewline -ForegroundColor Gray
            Write-Host "$(_lsTime $i) " -NoNewline -ForegroundColor Gray
            Write-Host "$(_lsSize $i $human) " -NoNewline -ForegroundColor Gray
            Write-Host $i.Name -ForegroundColor $c
        }
    } else {
        $names = @($items | ForEach-Object { $_ })
        $max = ($names | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
        $winWidth = try { [Console]::WindowWidth } catch { 80 }
        $cols = [Math]::Floor($winWidth / ($max + 2))
        if ($cols -lt 1) { $cols = 1 }
        $rows = [Math]::Ceiling($names.Count / $cols)
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                $idx = $r + $c * $rows
                if ($idx -lt $names.Count) {
                    $item = $names[$idx]
                    $color = _lsColor $item
                    Write-Host $item.Name.PadRight($max + 2) -NoNewline -ForegroundColor $color
                }
            }
            Write-Host
        }
    }
}

function mkdir {
    param([string]$Path, [switch]$p, [switch]$Force)
    if (-not $Path) { Write-Error "mkdir: missing operand"; return }
    $parts = $Path.TrimEnd('\').Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)
    $created = @()
    if ($p -or $Force) {
        $acc = if ($Path -match '^[a-zA-Z]:\\') { [System.IO.Path]::GetPathRoot($Path).TrimEnd('\') } else { '' }
        foreach ($part in $parts) {
            $acc = if ($acc) { "$acc\$part" } else { $part }
            if (-not (Test-Path -LiteralPath $acc)) {
                $null = New-Item -ItemType Directory -Path $acc -Force
                $created += $acc
            }
        }
    } else {
        if (Test-Path -LiteralPath $Path) {
            Write-Error "mkdir: $Path : File exists"
            return
        }
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            Write-Error "mkdir: $Path : No such file or directory"
            return
        }
        $null = New-Item -ItemType Directory -Path $Path
        $created = @($Path)
    }
    foreach ($d in $created) {
        Write-Host "  created " -NoNewline -ForegroundColor Green
        Write-Host $d -ForegroundColor Cyan
    }
    if ($created.Count -gt 0) {
        Set-Location -LiteralPath $created[-1]
        Write-Host "  -> cd " -NoNewline -ForegroundColor DarkGray
        Write-Host $created[-1] -ForegroundColor DarkYellow
    }
}

function find {
    param(
        [string]$Path = ".",
        [string]$Name,
        [string]$Type,
        [switch]$Iname
    )
    $filter = if ($Name) { $Name } else { "*" }
    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { if ($Iname) { $_.Name -ilike $filter } else { $_.Name -like $filter } }
    if ($Type) {
        switch -Wildcard ($Type.ToLower()) {
            'f*'   { $items = $items | Where-Object { -not $_.PSIsContainer } }
            'd*'   { $items = $items | Where-Object { $_.PSIsContainer } }
        }
    }
    foreach ($i in $items) {
        $c = _lsColor $i
        Write-Host "$(Resolve-Path -LiteralPath $i.FullName -Relative)" -ForegroundColor $c
    }
    if (-not $items) { Write-Host "  (no results)" -ForegroundColor DarkGray }
}

function winfetch { & "$env:USERPROFILE\winfetch.ps1" @args }
Set-Alias neofetch winfetch

winfetch

function prompt {
    $p = (Get-Location).Path.Replace($env:USERPROFILE, "~")
    $b = try { $(git rev-parse --abbrev-ref HEAD 2>$null) } catch { $null }
    Write-Host "[" -NoNewline -ForegroundColor DarkGray
    Write-Host $p -NoNewline -ForegroundColor Cyan
    if ($b) {
        $d = try { $(git status --porcelain 2>$null) } catch { $null }
        $clr = if ($d) { 'Yellow' } else { 'Green' }
        Write-Host " $b" -NoNewline -ForegroundColor $clr
    }
    Write-Host "]" -NoNewline -ForegroundColor DarkGray
    return "> "
}
