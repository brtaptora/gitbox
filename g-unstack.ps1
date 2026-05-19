param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Quiet
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo     = Get-Location
$branch   = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$repoName   = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

$allPRs = gh pr list --repo $repoName --state open --json number,headRefName,baseRefName,title,statusCheckRollup,isDraft 2>$null | ConvertFrom-Json
if (-not $allPRs) { $allPRs = @() }

$headToBase = @{}
$headToPR   = @{}
foreach ($pr in $allPRs) {
    $headToBase[$pr.headRefName] = $pr.baseRefName
    $headToPR[$pr.headRefName]   = $pr
}

# Walk from current branch toward base to find the bottom of the stack
$chain = [System.Collections.Generic.List[string]]::new()
$cur = $branch
$visited = [System.Collections.Generic.HashSet[string]]::new()
while ($cur -and $headToBase.ContainsKey($cur) -and $visited.Add($cur)) {
    $chain.Insert(0, $cur)
    $cur = $headToBase[$cur]
}

# Walk down from the deepest ancestor to collect all children in topological order
function Get-StackOrder {
    param([string]$Head, [System.Collections.Generic.List[string]]$Out)
    $Out.Add($Head)
    $kids = @($allPRs | Where-Object { $_.baseRefName -eq $Head })
    foreach ($k in $kids) {
        Get-StackOrder -Head $k.headRefName -Out $Out
    }
}

$ordered = [System.Collections.Generic.List[string]]::new()
if ($chain.Count -gt 0) {
    Get-StackOrder -Head $chain[0] -Out $ordered
} else {
    # Current branch may be a stack root (has children, no parent PR)
    $children = @($allPRs | Where-Object { $_.baseRefName -eq $branch })
    if ($children.Count -eq 0) {
        Write-Host "unstack: branch '$branch' is not part of a stacked PR chain"
        exit 0
    }
    Get-StackOrder -Head $branch -Out $ordered
}

if ($ordered.Count -eq 0) {
    Write-Host "unstack: no stacked PRs found"
    exit 1
}

if ($ordered[0] -ne $branch) {
    Write-Host "unstack: repositioning to bottom of stack: $($ordered[0])"
    $coOut = git -C $repo checkout $ordered[0] 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  checkout failed: $($coOut -join ' ')"; exit 1
    }
    $branch = $ordered[0]
}

if (-not $Quiet) {
    & (Join-Path $PSScriptRoot 'g-stack.ps1')
    Write-Host ""
}

$n = $ordered.Count
$labels = ($ordered | ForEach-Object { "#$($headToPR[$_].number) ($_)" }) -join ' → '
Write-Host "unstack: will merge $n PR(s) in order: $labels"

if ($DryRun) {
    Write-Host "unstack: dry run — would merge $n PR(s) in order:"
    foreach ($b in $ordered) {
        $pr = $headToPR[$b]
        Write-Host "  #$($pr.number) $b -> $($headToBase[$b])"
    }
    exit 0
}

if (-not $Force) {
    $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $isInteractive) {
        Write-Host "unstack: non-interactive session — pass -Force to proceed"
        exit 1
    }
    try {
        $answer = Read-Host "Proceed? [y/N]"
    } catch {
        Write-Host "unstack: non-interactive session — pass -Force to proceed"
        exit 1
    }
    if ($answer -notmatch '^[yY]$') {
        Write-Host "unstack: aborted"
        exit 0
    }
}

$i = 0
foreach ($b in $ordered) {
    $i++
    $pr = $headToPR[$b]
    if (-not $pr) {
        Write-Host "unstack: $i/$n — '$b' has no open PR; halting"
        exit 1
    }

    if (-not $Quiet) { Write-Host "unstack: $i/$n — checking out $b ..." }
    $coOut = git -C $repo checkout $b 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  checkout failed: $($coOut -join ' ')"
        exit 1
    }

    if ($pr.isDraft) {
        Write-Host "unstack: $i/$n — PR #$($pr.number) ($b) is a draft — run: gh pr ready $($pr.number)"
        exit 1
    }

    if (-not $Quiet) { Write-Host "unstack: $i/$n — checking CI for #$($pr.number) ..." }
    & (Join-Path $PSScriptRoot 'g-pr-checks.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host "unstack: $i/$n — CI failed for #$($pr.number) ($b); halting"
        exit 1
    }

    if (-not $Quiet) { Write-Host "unstack: $i/$n — merging #$($pr.number) ($b) ..." }
    & (Join-Path $PSScriptRoot 'g-merge-rotate.ps1') -SuppressWipWarning
    if ($LASTEXITCODE -ne 0) {
        Write-Host "unstack: $i/$n — merge failed for #$($pr.number) ($b); halting"
        exit 1
    }

    Write-Host "unstack: $i/$n merged #$($pr.number)"
}

Write-Host "unstack: done — $n PR(s) merged"
exit 0
