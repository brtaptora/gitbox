$SecretPattern = '\.env$|\.key$|\.pem$|\.pfx$|\.p12$|credentials|secrets?\.|id_rsa|id_ed25519|\.token$|\.npmrc$|\.pypirc$|\.dockercfg$|password$|apikey|oauth|jwt|\.aws[/\\]|\.kube[/\\]|\.ssh[/\\]'

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

# [ordered] so specific patterns match before generic subsets (e.g. BRANCH_CREATE before CHECKOUT)
$CapabilityPatterns = [ordered]@{
    BRANCH_CREATE = 'git\b.+checkout\b.+-b\b'
    PUSH_DELETE   = 'git\b.+push\b.+--delete\b'
    BRANCH_RENAME = 'git\b.+branch\b.+-m\b'
    BRANCH_DELETE = 'git\b.+branch\b.+(-d|-D)\b'
    STAGE         = 'git\b.+add\b'
    COMMIT        = 'git\b.+commit\b'
    PUSH          = 'git\b.+push\b'
    PULL          = 'git\b.+pull\b'
    REBASE        = 'git\b.+rebase\b'
    CHECKOUT      = 'git\b.+checkout\b'
    MERGE         = 'git\b.+merge\b'
    PR_CREATE     = 'gh\b.+pr\s+create\b'
    PR_MERGE      = 'gh\b.+pr\s+merge\b'
    PR_READY      = 'gh\b.+pr\s+ready\b'
    PR_CHECKS     = 'gh\b.+pr\s+checks\b'
    PR_LIST       = 'gh\b.+pr\s+list\b'
}

function Get-ScriptCapabilities {
    param([string]$Path)
    $seen   = [System.Collections.Generic.HashSet[string]]::new()
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content $Path)) {
        $t = $line.Trim()
        if (-not $t -or $t -match '^#' -or $t -match '^\$\w+\s*[+]?=\s*".*\b(git|gh)\b') { continue }
        foreach ($cap in $CapabilityPatterns.Keys) {
            if ($t -match $CapabilityPatterns[$cap]) {
                if ($seen.Add($cap)) { $result.Add($cap) }
                break
            }
        }
    }
    return [string[]]$result
}

# Hardcoded capability vectors per flag for workflow gap-coverage analysis
$FlagCapabilities = @{
    b = @('BRANCH_CREATE')
    r = @('BRANCH_RENAME')
    s = @('REBASE', 'PULL')
    c = @('STAGE', 'COMMIT', 'PUSH')
    p = @('PUSH')
    o = @('PR_CREATE')
    x = @('PR_CHECKS')
    m = @('PR_MERGE', 'BRANCH_DELETE', 'BRANCH_CREATE', 'CHECKOUT')
}

# Named flag sequences for the gitbox orchestrator
$WorkflowRegistry = [ordered]@{
    start   = 'b'
    rename  = 'r'
    sync    = 's'
    commit  = 'c'
    push    = 'p'
    pr      = 'o'
    checks  = 'x'
    merge   = 'm'
    ship    = 'cxm'
    full    = 'cpom'
}
