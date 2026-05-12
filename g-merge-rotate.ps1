param(
    [Parameter(ValueFromPipeline)]
    [string]$Name
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo = Get-Location

$remote = git -C $repo remote get-url origin 2>$null
if ($remote -notmatch '[/@]github\.com[:/]') {
    Write-Host "remote is not GitHub: $remote"; exit 1
}

$repoName   = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
$branch     = git -C $repo branch --show-current 2>$null
$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

if (-not $branch) { Write-Host "not a git repo"; exit 1 }

# find open PR for this branch
$prJson = gh pr list --repo $repoName --head $branch --json number,state 2>$null | ConvertFrom-Json
if (-not $prJson -or $prJson.Count -eq 0) {
    Write-Host "no open PR for branch '$branch'"; exit 1
}
$prNumber = $prJson[0].number

# gh pr merge exit code is the only reliable signal; stderr must be captured to surface failures
$mergeOut = gh pr merge $prNumber --repo $repoName --merge 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "merge failed: PR #$prNumber not merged; branch '$branch' preserved"
    $mergeOut | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# switch to base branch and pull
$checkoutOut = git -C $repo checkout $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "checkout $baseBranch failed"; $checkoutOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
$pullOut = git -C $repo pull origin $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "pull origin/$baseBranch failed"; $pullOut | ForEach-Object { Write-Host "  $_" }; exit 1 }

# delete remote branch (GitHub may already have deleted it on merge)
$delRemoteOut = git -C $repo push origin --delete $branch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "  warning: remote branch delete failed (may already be deleted)" }

# delete local branch
$delLocalOut = git -C $repo branch -d $branch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "  warning: local branch delete failed: $($delLocalOut -join ' ')" }

# create next branch — use supplied name or fall back to wip/ timestamp
$newBranch = if ($Name) { $Name } else { "wip/$(Get-Date -Format 'MMdd-HHmm')" }
$newBranchOut = git -C $repo checkout -b $newBranch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "checkout -b $newBranch failed"; $newBranchOut | ForEach-Object { Write-Host "  $_" }; exit 1 }

Write-Host "merged #$prNumber |deleted $branch |new branch $newBranch"
exit 0
