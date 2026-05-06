$repo = Get-Location

$remote = git -C $repo remote get-url origin 2>$null
if ($remote -notmatch "brtaptora/") {
    Write-Host "wrong remote: $remote"; exit 1
}

$repoName = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
$branch   = git -C $repo branch --show-current 2>$null

if (-not $branch) { Write-Host "not a git repo"; exit 1 }

# find open PR for this branch
$prJson = gh pr list --repo $repoName --head $branch --json number,state 2>$null | ConvertFrom-Json
if (-not $prJson -or $prJson.Count -eq 0) {
    Write-Host "no open PR for branch '$branch'"; exit 1
}
$prNumber = $prJson[0].number

# merge PR (merge commit, no auto-delete via gh so we control cleanup)
gh pr merge $prNumber --repo $repoName --merge 2>$null | Out-Null

# switch to production and pull
git -C $repo checkout production 2>$null | Out-Null
git -C $repo pull origin production 2>$null | Out-Null

# delete remote branch
git -C $repo push origin --delete $branch 2>$null | Out-Null

# delete local branch
git -C $repo branch -d $branch 2>$null | Out-Null

# create new wip branch
$newBranch = "wip/$(Get-Date -Format 'MMdd-HHmm')"
git -C $repo checkout -b $newBranch 2>$null | Out-Null

Write-Host "merged #$prNumber · deleted $branch · new branch $newBranch"
