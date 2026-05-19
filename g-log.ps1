param(
    [switch]$Full
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo       = Get-Location
$branch     = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

if ($Full) {
    $commits = @(git -C $repo log --oneline -30 2>$null | Where-Object { $_ })
    Write-Host "$branch -- last $($commits.Count) commits"
    $commits | ForEach-Object { Write-Host "  $_" }
    exit 0
}

$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch
$ref        = if (git -C $repo rev-parse --verify "origin/$baseBranch" 2>$null) { "origin/$baseBranch" } else { $baseBranch }

$commits = @(git -C $repo log --oneline "${ref}..HEAD" 2>$null | Where-Object { $_ })
if ($commits.Count -eq 0) {
    Write-Host "no commits ahead of $baseBranch"
    exit 0
}

$s = if ($commits.Count -ne 1) { 's' } else { '' }
Write-Host "$branch -- $($commits.Count) commit$s ahead of $baseBranch"
$commits | ForEach-Object { Write-Host "  $_" }
