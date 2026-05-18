param(
    [Parameter(ValueFromPipeline)]
    [string]$Name,
    [int]$Steps = [int]::MaxValue,
    [switch]$Squash,
    [switch]$Rebase
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

# Step 1: find open PR for this branch
$prJson = gh pr list --repo $repoName --head $branch --json number,state 2>$null | ConvertFrom-Json
if (-not $prJson -or $prJson.Count -eq 0) {
    Write-Host "no open PR for branch '$branch'"; exit 1
}
$prNumber = $prJson[0].number

# Stack unwind: rebase and retarget downstream PRs before deleting this branch
$downstreamJson = gh pr list --repo $repoName --base $branch --state open --json number,headRefName 2>$null | ConvertFrom-Json
if ($downstreamJson -and $downstreamJson.Count -gt 0) {
    Write-Host "stack: $($downstreamJson.Count) downstream PR(s) — rebasing onto $baseBranch ..."
    foreach ($dpr in $downstreamJson) {
        $dBranch = $dpr.headRefName
        $dNum    = $dpr.number
        Write-Host "  PR #$dNum ($dBranch) → rebase onto $baseBranch ..."

        git -C $repo fetch origin "${dBranch}:${dBranch}" 2>$null | Out-Null

        $coOut = git -C $repo checkout $dBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  error: cannot checkout $dBranch"
            $coOut | ForEach-Object { Write-Host "    $_" }
            git -C $repo checkout $branch 2>$null | Out-Null
            exit 1
        }

        $rbOut = git -C $repo rebase --onto "origin/$baseBranch" "origin/$branch" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  rebase conflict on $dBranch -- resolve and retry (git rebase --continue)"
            $rbOut | ForEach-Object { Write-Host "    $_" }
            git -C $repo rebase --abort 2>$null | Out-Null
            git -C $repo checkout $branch 2>$null | Out-Null
            exit 1
        }

        $pushOut = git -C $repo push origin $dBranch --force-with-lease 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  push failed for $dBranch (upstream diverged -- pull and retry)"
            $pushOut | ForEach-Object { Write-Host "    $_" }
            git -C $repo checkout $branch 2>$null | Out-Null
            exit 1
        }

        gh pr edit $dNum --repo $repoName --base $baseBranch 2>$null | Out-Null
        Write-Host "  PR #$dNum retargeted → $baseBranch"
        git -C $repo checkout $branch 2>$null | Out-Null
    }
}

if (1 -ge $Steps) { exit 0 }

# Step 2: merge
# gh pr merge exit code is the only reliable signal; stderr must be captured to surface failures
$mergeFlag = '--merge'
if ($Squash)       { $mergeFlag = '--squash' }
elseif ($Rebase)   { $mergeFlag = '--rebase' }
else {
    $cfgStrategy = (Get-GitboxConfig -RepoPath $repo).MergeStrategy
    if ($cfgStrategy -eq 'squash') { $mergeFlag = '--squash' }
    elseif ($cfgStrategy -eq 'rebase') { $mergeFlag = '--rebase' }
}
Write-Host "merging #$prNumber ..."
$mergeOut = gh pr merge $prNumber --repo $repoName $mergeFlag 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "merge failed: PR #$prNumber not merged; branch '$branch' preserved"
    $mergeOut | ForEach-Object { Write-Host "  $_" }
    exit 1
}
if (2 -ge $Steps) { exit 0 }

# Step 3: switch to base branch and pull
$checkoutOut = git -C $repo checkout $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "checkout $baseBranch failed"; $checkoutOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
$pullOut = git -C $repo pull origin $baseBranch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "pull origin/$baseBranch failed"; $pullOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
if (3 -ge $Steps) { exit 0 }

# Step 4: delete remote branch (GitHub may already have deleted it on merge)
$delRemoteOut = git -C $repo push origin --delete $branch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "  warning: remote branch delete failed (may already be deleted)" }
if (4 -ge $Steps) { exit 0 }

# Step 5: delete local branch
$delLocalOut = git -C $repo branch -d $branch 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "  warning: local branch delete failed: $($delLocalOut -join ' ')" }
if (5 -ge $Steps) { exit 0 }

# Step 6: post-merge destination (config key PostMerge: wip | base | stack)
$postMerge = (Get-GitboxConfig -RepoPath $repo).PostMerge

if ($postMerge -eq 'base') {
    $coOut = git -C $repo checkout $baseBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "checkout $baseBranch failed"; $coOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
    $pullOut = git -C $repo pull origin $baseBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "pull origin/$baseBranch failed"; $pullOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
    Write-Host "merged #$prNumber |deleted $branch |on $baseBranch"
} elseif ($postMerge -eq 'stack' -and $downstreamJson -and $downstreamJson.Count -gt 0) {
    $nextBranch = $downstreamJson[0].headRefName
    git -C $repo fetch origin "${nextBranch}:${nextBranch}" 2>$null | Out-Null
    $coOut = git -C $repo checkout $nextBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "checkout $nextBranch failed"; $coOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
    Write-Host "merged #$prNumber |deleted $branch |on $nextBranch"
} else {
    $newBranch = if ($Name) { $Name } else { "wip/$(Get-Date -Format 'MMdd-HHmmss')" }
    $newBranchOut = git -C $repo checkout -b $newBranch 2>&1
    if ($LASTEXITCODE -ne 0) {
        if (($newBranchOut -join '') -match 'already exists') {
            Write-Host "  wip branch '$newBranch' already exists -- run: git branch -d $newBranch"
        } else {
            Write-Host "checkout -b $newBranch failed"
            $newBranchOut | ForEach-Object { Write-Host "  $_" }
        }
        exit 1
    }
    Write-Host "merged #$prNumber |deleted $branch |new branch $newBranch"
    Write-Host "  ! on wip branch -- run: gitbox r ""<name>"" to rename, or: gitbox g to return to base"
}
exit 0
