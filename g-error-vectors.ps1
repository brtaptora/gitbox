$ErrorVectors = @{
    B_CLASS   = @('no feature branch', 'currently on base branch', 'on default branch')
    W_CLASS   = @('no rename script', 'currently on wip branch', 'wip branch detected')
    BEHIND    = @('behind', 'diverged', 'fetch first', 'not up to date', 'would be overwritten')
    NO_PUSH   = @('nothing to stage', 'unpushed commits', 'ahead of origin')
    NO_REMOTE = @('no such remote', 'does not appear', 'repository not found')
    AUTH      = @('authentication failed', 'permission denied', 'could not read username')
    CONFLICT  = @('conflict', 'merge conflict', 'cannot merge', 'automatic merge failed')
    NO_BRANCH = @('unknown revision', 'not a valid object', 'pathspec did not match')
    CHECKS    = @('required status checks', 'failing checks', 'check failed', 'status check', 'blocked')
    NO_PR     = @('no pull requests', 'pull request not found', 'no open pull requests')
    PROTECTED = @('protected branch', 'cannot force push', 'push declined')
}

function Resolve-StderrToVector {
    param([string]$Stderr)
    # ToLower once; Contains is sufficient for these terse, unambiguous error strings
    $lower = $Stderr.ToLower()
    foreach ($dim in $ErrorVectors.Keys) {
        foreach ($token in $ErrorVectors[$dim]) {
            if ($lower.Contains($token)) { return $dim }
        }
    }
    return $null
}

$GapRequirements = @{
    B_CLASS = @('BRANCH_CREATE')
    W_CLASS = @('BRANCH_RENAME')
    BEHIND  = @('REBASE', 'PULL')
    CHECKS  = @('PR_CHECKS')
    NO_PUSH = @('PUSH')
}

function Format-GapLabel {
    param(
        [string]$Class,
        [string]$Dim,
        [int]$Ahead  = 0,
        [int]$Behind = 0,
        [string]$Pr  = ''
    )
    $classStr = switch ($Class) { 'B' {'base'} 'W' {'wip'} 'F' {'feature'} default {$Class.ToLower()} }
    $dimStr   = switch ($Dim) {
        'B_CLASS' { "transition from $classStr to feature branch" }
        'W_CLASS' { "rename from $classStr branch to feature name" }
        'BEHIND'  { "sync $Behind commit$(if ($Behind -ne 1) {'s'}) from base" }
        'CHECKS'  { "resolve failing checks ($Pr)" }
        'NO_PUSH' { "push $Ahead unpushed commit$(if ($Ahead -ne 1) {'s'}) to origin" }
        default   { $Dim.ToLower() -replace '_',' ' }
    }
    return "GAP[$Dim]: no script to $dimStr"
}
