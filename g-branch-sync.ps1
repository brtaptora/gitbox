$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$baseBranch = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
if (-not $baseBranch) { $baseBranch = "main" }

if ($branch -eq $baseBranch) {
    Write-Host "already on base branch; run: git pull origin $baseBranch"; exit 1
}

$fetchOut = git -C $repo fetch origin $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "fetch failed"
    $fetchOut | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$behind = (git -C $repo rev-list "HEAD..origin/${baseBranch}" 2>$null | Measure-Object -Line).Lines
if ($behind -eq 0) {
    Write-Host "already up to date with origin/$baseBranch"
    exit 0
}

$rebaseOut = git -C $repo rebase "origin/$baseBranch" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "rebase conflict: resolve manually then run: git rebase --continue"
    $rebaseOut | ForEach-Object { Write-Host "  $_" }
    git -C $repo rebase --abort 2>$null | Out-Null
    Write-Host "rebase aborted; working tree restored"
    exit 1
}

$ahead = (git -C $repo rev-list "origin/${baseBranch}..HEAD" 2>$null | Measure-Object -Line).Lines
Write-Host "synced $branch onto origin/$baseBranch |+$ahead ahead |0 behind"
exit 0
