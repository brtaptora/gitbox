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

$FlagScripts = @{
    b = 'g-branch-create.ps1'
    r = 'g-branch-rename.ps1'
    s = 'g-branch-sync.ps1'
    c = 'g-commit-push.ps1'
    u = 'g-push.ps1'
    o = 'g-open-pr.ps1'
    x = 'g-pr-checks.ps1'
    m = 'g-merge-rotate.ps1'
}
$FlagCapabilities = @{}
foreach ($flag in $FlagScripts.Keys) {
    $sp = Join-Path $PSScriptRoot $FlagScripts[$flag]
    if (Test-Path $sp) { $FlagCapabilities[$flag] = Get-ScriptCapabilities -Path $sp }
}

# Named flag sequences for the gitbox orchestrator
$WorkflowRegistry = [ordered]@{
    start   = 'b'
    rename  = 'r'
    sync    = 's'
    commit  = 'c'
    push    = 'u'
    pr      = 'o'
    checks  = 'x'
    merge   = 'm'
    ship    = 'cxm'
    full    = 'cuoxm'
}

function Get-GitboxConfig {
    param([string]$RepoPath = (Get-Location))
    $cfgPath = Join-Path $RepoPath '.gitbox.json'
    $base = $null; $default = $null
    if (Test-Path $cfgPath) {
        $cfg     = Get-Content $cfgPath -Raw | ConvertFrom-Json
        $base    = $cfg.BaseBranch
        $default = $cfg.DefaultBranch
    }
    if (-not $default) {
        $default = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
        if (-not $default) { $default = 'main' }
    }
    if (-not $base) { $base = $default }
    return @{ BaseBranch = $base; DefaultBranch = $default }
}

function Get-GitRepoState {
    param([string]$RepoPath = (Get-Location))
    $branch = git -C $RepoPath branch --show-current 2>$null
    if (-not $branch) { return $null }

    $baseBranch = (Get-GitboxConfig -RepoPath $RepoPath).BaseBranch
    $repoName   = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null

    $ahead = 0; $behind = 0
    if (git -C $RepoPath rev-parse --verify "origin/$baseBranch" 2>$null) {
        $ahead  = (git -C $RepoPath rev-list "origin/${baseBranch}..HEAD" 2>$null | Measure-Object -Line).Lines
        $behind = (git -C $RepoPath rev-list "HEAD..origin/${baseBranch}" 2>$null | Measure-Object -Line).Lines
    }

    $dirtyFiles   = @(git -C $RepoPath status --porcelain 2>$null | Where-Object { $_ })
    $remoteBranch = git -C $RepoPath rev-parse --verify "origin/$branch" 2>$null
    $unpushed     = if ($remoteBranch) {
        (git -C $RepoPath rev-list "origin/${branch}..HEAD" 2>$null | Measure-Object -Line).Lines
    } else { -1 }

    $pr = $null
    if ($repoName) {
        $prJson = gh pr list --repo $repoName --head $branch --json number,state,title,reviewDecision,statusCheckRollup 2>$null | ConvertFrom-Json
        if ($prJson -and $prJson.Count -gt 0) { $pr = $prJson[0] }
    }

    return [pscustomobject]@{
        Branch       = $branch
        BaseBranch   = $baseBranch
        RepoName     = $repoName
        Ahead        = $ahead
        Behind       = $behind
        DirtyFiles   = $dirtyFiles
        RemoteBranch = $remoteBranch
        Unpushed     = $unpushed
        PR           = $pr
    }
}
