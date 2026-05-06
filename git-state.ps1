param(
    [switch]$d
)

$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$baseBranch = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
if (-not $baseBranch) { $baseBranch = "main" }

# ahead/behind base branch
$upstream = git -C $repo rev-parse --verify origin/$baseBranch 2>$null
if ($upstream) {
    $ahead  = (git -C $repo rev-list origin/${baseBranch}..HEAD 2>$null | Measure-Object -Line).Lines
    $behind = (git -C $repo rev-list HEAD..origin/${baseBranch} 2>$null | Measure-Object -Line).Lines
} else {
    $ahead  = 0
    $behind = 0
}

# dirty file count
$dirty = (git -C $repo status --porcelain 2>$null | Measure-Object -Line).Lines

# PR status
$prJson = gh pr list --repo (gh repo view --json nameWithOwner -q .nameWithOwner 2>$null) --head $branch --json number,state,title 2>$null | ConvertFrom-Json
if ($prJson -and $prJson.Count -gt 0) {
    $pr = $prJson[0]
    $prLabel = "PR #$($pr.number) $($pr.state.ToUpper())"
} else {
    $prLabel = "no PR"
}

$aheadStr  = if ($ahead  -gt 0) { "+$ahead ahead" }  else { "up to date" }
$behindStr = if ($behind -gt 0) { "-$behind behind" } else { $null }
$dirtyStr  = if ($dirty  -gt 0) { "$dirty dirty" }   else { "clean" }

$parts = @($branch, $aheadStr)
if ($behindStr) { $parts += $behindStr }
$parts += $dirtyStr
$parts += $prLabel

Write-Host ($parts -join " · ")

if ($d -and $prJson -and $prJson.Count -gt 0) {
    $body = gh pr view $pr.number --json body -q .body 2>$null
    if ($body) {
        Write-Host ""
        Write-Host $body
    }
}
