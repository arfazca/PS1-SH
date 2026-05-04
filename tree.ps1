function tree {
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
