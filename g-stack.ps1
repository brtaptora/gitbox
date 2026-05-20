. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo     = Get-Location
$branch   = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$repoName   = ((git -C $repo remote get-url origin 2>$null) -replace ".*github\.com[:/]", "") -replace "\.git$", ""
$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

$allPRs = gh pr list --repo $repoName --state open --json number,headRefName,baseRefName,title,statusCheckRollup 2>$null | ConvertFrom-Json
if (-not $allPRs) { $allPRs = @() }

# Build adjacency map: head → base
$headToBase = @{}
$headToPR   = @{}
foreach ($pr in $allPRs) {
    $headToBase[$pr.headRefName] = $pr.baseRefName
    $headToPR[$pr.headRefName]   = $pr
}

# Walk up to find the root of current branch's stack (toward base)
$chain = [System.Collections.Generic.List[string]]::new()
$cur = $branch
$visited = [System.Collections.Generic.HashSet[string]]::new()
while ($cur -and $headToBase.ContainsKey($cur) -and $visited.Add($cur)) {
    $chain.Insert(0, $cur)
    $cur = $headToBase[$cur]
}

# If current branch has no PR but branches above it do, walk down from base
if ($chain.Count -eq 0) {
    # Check if any PR targets the current branch (current branch is a stack parent)
    $children = @($allPRs | Where-Object { $_.baseRefName -eq $branch })
    if ($children.Count -eq 0) {
        Write-Host "no stack — branch '$branch' is not part of a stacked PR chain"
        exit 0
    }
    $chain.Add($branch)
}

# Walk down to find all children
function Get-Children {
    param([string]$Head)
    $kids = @($allPRs | Where-Object { $_.baseRefName -eq $Head })
    return $kids
}

function Write-StackTree {
    param([string]$Head, [int]$Depth = 0, [string]$CurrentBranch)
    $indent = '    ' * $Depth
    $connector = if ($Depth -gt 0) { ' └─ ' } else { '' }
    $pr = $headToPR[$Head]
    $marker = if ($Head -eq $CurrentBranch) { ' ← YOU ARE HERE' } else { '' }
    if ($pr) {
        $ci = switch (Get-PRRollup $pr.statusCheckRollup) {
            'SUCCESS' { '[pass]' }
            'FAILURE' { '[fail]' }
            'PENDING' { '[pend]' }
            default   { '[----]' }
        }
        $state = if ($pr.state -eq 'DRAFT') { 'PRD' } else { 'PRO' }
        Write-Host ("${indent}${connector}{0,-30}  #{1,-4} {2} {3}{4}" -f $Head, $pr.number, $state, $ci, $marker)
    } else {
        Write-Host ("${indent}${connector}{0}{1}" -f $Head, $marker)
    }
    foreach ($child in (Get-Children -Head $Head)) {
        Write-StackTree -Head $child.headRefName -Depth ($Depth + 1) -CurrentBranch $CurrentBranch
    }
}

# Print base branch root
$rootBase = if ($chain.Count -gt 0) {
    $headToBase[$chain[0]]
} else { $baseBranch }
Write-Host $rootBase
Write-StackTree -Head $chain[0] -Depth 1 -CurrentBranch $branch
exit 0
