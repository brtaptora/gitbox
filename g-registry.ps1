$GapRequirements = @{
    B_CLASS = @('BRANCH_CREATE')
    W_CLASS = @('BRANCH_RENAME')
    BEHIND  = @('REBASE', 'PULL')
    CHECKS  = @('PR_CHECKS')
    NO_PUSH = @('PUSH')
    NO_PR   = @('PR_CREATE')
}

# [ordered] so specific patterns match before generic subsets (e.g. BRANCH_CREATE before CHECKOUT)
$CapabilityPatterns = [ordered]@{
    FORK          = 'gh\b.+repo\s+fork\b'
    CLONE         = 'git\b.+clone\b'
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
    REVERT        = 'git\b.+revert\b'
    TAG           = 'git\b.+tag\b'
    PR_CREATE     = 'gh\b.+pr\s+create\b'
    PR_MERGE      = 'gh\b.+pr\s+merge\b'
    PR_READY      = 'gh\b.+pr\s+ready\b'
    PR_CHECKS     = 'gh\b.+pr\s+checks\b'
    PR_LIST       = 'gh\b.+pr\s+list\b'
}

function Get-ScriptCapabilities {
    param(
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$Visited = $null
    )
    if (-not $Visited) { $Visited = [System.Collections.Generic.HashSet[string]]::new() }
    if (-not $Visited.Add($Path)) { return [string[]]@() }
    $seen   = [System.Collections.Generic.HashSet[string]]::new()
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content $Path)) {
        $t = $line.Trim()
        if (-not $t -or $t -match '^#' -or $t -match '^\$\w+\s*[+]?=\s*".*\b(git|gh)\b') { continue }
        # Inherit caps from scripts called with & via Join-Path; excludes dot-source (.) infrastructure loads
        if ($t -match '&\s+.*\bJoin-Path\b' -and $t -match "'(g-[^']+\.ps1)'") {
            $refPath = Join-Path (Split-Path $Path) $Matches[1]
            if (Test-Path $refPath) {
                foreach ($cap in (Get-ScriptCapabilities -Path $refPath -Visited $Visited)) {
                    if ($seen.Add($cap)) { $result.Add($cap) }
                }
            }
        }
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
    f = 'g-fork-setup.ps1'
    b = 'g-branch-create.ps1'
    r = 'g-branch-rename.ps1'
    s = 'g-branch-sync.ps1'
    c = 'g-commit-push.ps1'
    u = 'g-push.ps1'
    o = 'g-open-pr.ps1'
    x = 'g-pr-checks.ps1'
    m = 'g-merge-rotate.ps1'
    g = 'g-branch-base.ps1'
    k = 'g-branch-checkout.ps1'
    n = 'g-unstack.ps1'
    z = 'g-release.ps1'
}
$FlagCapabilities = @{}
foreach ($flag in $FlagScripts.Keys) {
    $sp = Join-Path $PSScriptRoot $FlagScripts[$flag]
    if (Test-Path $sp) { $FlagCapabilities[$flag] = Get-ScriptCapabilities -Path $sp }
}

$AllCapabilities = [System.Collections.Generic.HashSet[string]]::new()
foreach ($caps in $FlagCapabilities.Values) {
    foreach ($cap in $caps) { [void]$AllCapabilities.Add($cap) }
}

# Named flag sequences for the gitbox orchestrator
$WorkflowRegistry = [ordered]@{
    fork    = 'f'
    start   = 'b'
    rename  = 'r'
    sync    = 's'
    commit  = 'c'
    push    = 'u'
    pr      = 'o'
    checks  = 'x'
    merge   = 'm'
    revert  = 'v'
    base     = 'g'
    checkout = 'k'
    unstack  = 'n'
    stack    = 'T'
    promote  = 'rcuo'
    submit   = 'cuo'
    land     = 'cxm'
    ship     = 'xm'
    full     = 'cuoxm'
    release  = 'z'
    health   = 'H'
    status   = 'S'
    log      = 'L'
}

function Get-GitboxConfig {
    param([string]$RepoPath = (Get-Location))
    $cfgPath = Join-Path $RepoPath '.gitbox.json'
    $base = $null; $default = $null; $mergeStrategy = $null; $editor = $null; $postMerge = $null; $upstream = $null; $neverStage = @()
    if (Test-Path $cfgPath) {
        $cfg     = Get-Content $cfgPath -Raw | ConvertFrom-Json
        $base    = $cfg.BaseBranch
        $default = $cfg.DefaultBranch
        if ($cfg.MergeStrategy)     { $mergeStrategy = $cfg.MergeStrategy.ToLower() }
        if ($null -ne $cfg.Editor)  { $editor        = [bool]$cfg.Editor }
        if ($cfg.PostMerge)         { $postMerge     = $cfg.PostMerge.ToLower() }
        if ($cfg.Upstream)          { $upstream      = $cfg.Upstream }
        if ($cfg.NeverStage)        { $neverStage    = [string[]]$cfg.NeverStage }
    } else {
        $default       = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
        if (-not $default) { $default = 'main' }
        $base          = $default
        $mergeStrategy = 'merge'
        $editor        = $false
    }
    # Partial-config fallbacks: fill any keys the config file omitted
    if (-not $default)             { $default       = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null; if (-not $default) { $default = 'main' } }
    if (-not $base)                { $base          = $default }
    if ($null -eq $mergeStrategy)  { $mergeStrategy = 'merge' }
    if ($null -eq $editor)         { $editor        = $false }
    if ($null -eq $postMerge)      { $postMerge     = 'wip' }
    return @{ BaseBranch = $base; DefaultBranch = $default; MergeStrategy = $mergeStrategy; Editor = $editor; PostMerge = $postMerge; Upstream = $upstream; NeverStage = $neverStage }
}

function Invoke-GitboxEditor {
    param([string]$Template = '')
    $editorCmd = git var GIT_EDITOR 2>$null
    if (-not $editorCmd) { $editorCmd = $env:EDITOR }
    if (-not $editorCmd) { Write-Host "no editor configured; set core.editor in git config"; return $null }
    $tmp = [System.IO.Path]::GetTempFileName() + ".txt"
    if ($Template) { Set-Content $tmp $Template -Encoding UTF8 }
    & $editorCmd $tmp
    if ($LASTEXITCODE -ne 0) { Remove-Item $tmp -ErrorAction SilentlyContinue; return $null }
    $content = ((Get-Content $tmp -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#' }) -join "`n").Trim()
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return if ($content) { $content } else { $null }
}

function Get-PRRollup {
    param($CheckRollup)
    if (-not $CheckRollup) { return $null }
    if ($CheckRollup -is [string]) { return $CheckRollup.ToUpper() }
    if ($CheckRollup.Count -eq 0)  { return $null }
    $fail    = @($CheckRollup | Where-Object { $_.conclusion -in @('FAILURE','ERROR') -or $_.state -eq 'FAILURE' })
    $pending = @($CheckRollup | Where-Object { $_.status -in @('QUEUED','IN_PROGRESS') -or $_.state -eq 'PENDING' })
    $pass    = @($CheckRollup | Where-Object { $_.conclusion -eq 'SUCCESS' -or $_.state -eq 'SUCCESS' })
    if ($fail.Count -gt 0)    { return 'FAILURE' }
    if ($pending.Count -gt 0) { return 'PENDING' }
    if ($pass.Count -gt 0)    { return 'SUCCESS' }
    return $null
}

function Get-GitRepoState {
    param(
        [string]$RepoPath = (Get-Location),
        [int]$RunLimit = 0,
        [switch]$GitOnly
    )
    $branch = git -C $RepoPath branch --show-current 2>$null
    if (-not $branch) { return $null }

    $cfg        = Get-GitboxConfig -RepoPath $RepoPath
    $baseBranch = $cfg.BaseBranch
    $upstream   = $cfg.Upstream
    $originUrl  = git -C $RepoPath remote get-url origin 2>$null
    $repoName   = if (-not $GitOnly -and $originUrl) { ($originUrl -replace ".*github\.com[:/]", "") -replace "\.git$", "" } else { $null }

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
    if (-not $GitOnly -and $repoName) {
        $prJson = gh pr list --repo $repoName --head $branch --json number,state,title,reviewDecision,statusCheckRollup 2>$null | ConvertFrom-Json
        if ($prJson -and $prJson.Count -gt 0) { $pr = $prJson[0] }
    }

    $runs = $null
    if ($RunLimit -gt 0 -and $repoName) {
        $runsJson = gh run list --repo $repoName --branch $branch --limit $RunLimit --json databaseId,name,status,conclusion,createdAt 2>$null
        if ($runsJson) { $runs = $runsJson | ConvertFrom-Json }
    }

    return [pscustomobject]@{
        Branch       = $branch
        BaseBranch   = $baseBranch
        RepoName     = $repoName
        Upstream     = $upstream
        Ahead        = $ahead
        Behind       = $behind
        DirtyFiles   = $dirtyFiles
        RemoteBranch = $remoteBranch
        Unpushed     = $unpushed
        PR           = $pr
        Runs         = $runs
    }
}

# Populate $GapRequirements for any dim Resolve-MatrixAction uses that isn't in the static map.
# Runs once at load time; pure in-memory — no I/O. Eliminates the manual step when adding a new dim.
foreach ($cl_ in 'B','F','W') { foreach ($di_ in 'c','d1','s1') {
    foreach ($ah_ in 'a0','a1') { foreach ($be_ in 'b0','b1') {
        foreach ($pu_ in 'P','U') { foreach ($pr_ in 'PR-','PRD','PRO','PRX','PRA') {
            $ar_ = Resolve-MatrixAction -Hash "$cl_|$di_|$ah_|$be_|$pu_|$pr_"
            if ($ar_ -and $ar_.Dim -and -not $GapRequirements.ContainsKey($ar_.Dim)) {
                if ($ar_.Action -match 'gitbox\s+([a-z])') {
                    $af_ = $Matches[1]
                    if ($FlagCapabilities.ContainsKey($af_)) {
                        $GapRequirements[$ar_.Dim] = [string[]]$FlagCapabilities[$af_]
                    }
                }
            }
        } } } } } }
