[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

if ($branch -eq $baseBranch) {
    Write-Host "already on base branch; run: git pull origin $baseBranch"; exit 1
}

$fetchOut = git -C $repo fetch origin $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "fetch failed"
    if ($VerbosePreference -ne 'SilentlyContinue') { $fetchOut | ForEach-Object { Write-Host "  $_" } }
    exit 1
}

$behind = (git -C $repo rev-list "HEAD..origin/${baseBranch}" 2>$null | Measure-Object -Line).Lines
if ($behind -eq 0) {
    Write-Host "already up to date with origin/$baseBranch"
    exit 0
}

$stashed = $false
if (@(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
    $stashOut = git -C $repo stash push -m 'gitbox-sync' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "stash failed"
        if ($VerbosePreference -ne 'SilentlyContinue') { $stashOut | ForEach-Object { Write-Host "  $_" } }
        exit 1
    }
    $stashed = $true
}

$rebaseOut = git -C $repo rebase "origin/$baseBranch" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "rebase conflict: resolve manually then run: git rebase --continue"
    if ($VerbosePreference -ne 'SilentlyContinue') { $rebaseOut | ForEach-Object { Write-Host "  $_" } }
    git -C $repo rebase --abort 2>$null | Out-Null
    Write-Host "rebase aborted; working tree restored"
    if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
    exit 1
}

if ($stashed) {
    $popOut = git -C $repo stash pop 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "warning: stash pop after rebase failed -- run: git stash pop"
        if ($VerbosePreference -ne 'SilentlyContinue') { $popOut | ForEach-Object { Write-Host "  $_" } }
    }
}

$ahead = (git -C $repo rev-list "origin/${baseBranch}..HEAD" 2>$null | Measure-Object -Line).Lines
Write-Host "synced $branch onto origin/$baseBranch |+$ahead ahead |0 behind"
exit 0
