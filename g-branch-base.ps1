param([switch]$NoStashPop)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

if ($branch -eq $baseBranch) {
    Write-Host "already on $baseBranch"
    exit 0
}

$stashed = $false
if (@(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
    $stashOut = git -C $repo stash push -m 'gitbox-base' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "stash failed"
        $stashOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    $stashed = $true
}

$coOut = git -C $repo checkout $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "checkout $baseBranch failed"
    $coOut | ForEach-Object { Write-Host "  $_" }
    if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
    exit 1
}

$pullOut = git -C $repo pull origin $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "pull $baseBranch failed"
    $pullOut | ForEach-Object { Write-Host "  $_" }
    if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
    exit 1
}

if ($stashed) {
    if ($NoStashPop) {
        Write-Host "  stash preserved -- run: git stash pop to restore changes"
    } else {
        $popOut = git -C $repo stash pop 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "warning: stash pop failed -- run: git stash pop"
            $popOut | ForEach-Object { Write-Host "  $_" }
        }
    }
}

Write-Host "on $baseBranch | pulled origin/$baseBranch"
exit 0
