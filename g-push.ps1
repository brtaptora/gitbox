$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$baseBranch = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
if (-not $baseBranch) { $baseBranch = "main" }

if ($branch -eq $baseBranch) {
    Write-Host "on base branch; g-push is for feature branches only"; exit 1
}

$ahead = (git -C $repo rev-list "origin/${branch}..HEAD" 2>$null | Measure-Object -Line).Lines

# handle untracked remote (branch never pushed)
$remoteRef = git -C $repo rev-parse --verify "origin/$branch" 2>$null
$noRemote  = ($LASTEXITCODE -ne 0)

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
