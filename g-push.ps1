. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

if ($branch -eq $baseBranch) {
    Write-Host "on base branch; g-push is for feature branches only"; exit 1
}

# check remote ref before counting so first-push counts against base, not the nonexistent origin/$branch
$remoteRef = git -C $repo rev-parse --verify "origin/$branch" 2>$null
$noRemote  = ($LASTEXITCODE -ne 0)

$countBase = if ($noRemote) { "origin/${baseBranch}" } else { "origin/${branch}" }
$ahead = (git -C $repo rev-list "${countBase}..HEAD" 2>$null | Measure-Object -Line).Lines

if (-not $noRemote -and $ahead -eq 0) {
    Write-Host "nothing to push; origin/$branch is up to date"; exit 0
}

$pushOut = git -C $repo push origin -u $branch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "push failed"
    $pushOut | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "pushed $ahead commit$(if ($ahead -ne 1) {'s'}) to origin/$branch"
exit 0
