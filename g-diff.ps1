$repo   = Get-Location
$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$stat = @(git -C $repo diff --stat HEAD 2>$null | Where-Object { $_ })
if ($stat.Count -eq 0) {
    Write-Host "working tree clean"
    exit 0
}
$stat | ForEach-Object { Write-Host $_ }
