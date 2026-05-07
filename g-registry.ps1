$GapRequirements = @{
    B_CLASS = @('BRANCH_CREATE')
    W_CLASS = @('BRANCH_RENAME')
    BEHIND  = @('REBASE', 'PULL')
    CHECKS  = @('PR_CHECKS')
    NO_PUSH = @('PUSH')
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
