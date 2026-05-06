# Derives the gap backlog directly from g-matrix-resolve.ps1.
# Source of truth is the resolve script; this script is a read-only view of it.

$resolveScript = Join-Path $PSScriptRoot "g-matrix-resolve.ps1"

if (-not (Test-Path $resolveScript)) {
    Write-Host "g-matrix-resolve.ps1 not found at $resolveScript"; exit 1
}

$gaps = Get-Content $resolveScript |
    Where-Object { $_ -match '"GAP:' } |
    ForEach-Object { $_ -replace '.*"(GAP:[^"]+)".*', '$1' } |
    Select-Object -Unique

if (-not $gaps) { Write-Host "no gaps found"; exit 0 }

$i = 1
foreach ($gap in $gaps) {
    Write-Host "$i. $gap"
    $i++
}
