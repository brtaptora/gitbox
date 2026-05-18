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
    NO_PR       = @('no pull requests', 'pull request not found', 'no open pull requests')
    PROTECTED   = @('protected branch', 'cannot force push', 'push declined')
    NOT_ON_BASE = @('must be on base branch', 'must be on base')
}

function Resolve-OutputToVector {
    param([string]$Output)
    # ToLower once; Contains is sufficient for these terse, unambiguous error strings
    $lower = $Output.ToLower()
    foreach ($dim in $ErrorVectors.Keys) {
        foreach ($token in $ErrorVectors[$dim]) {
            if ($lower.Contains($token)) { return $dim }
        }
    }
    return $null
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

function Resolve-MatrixAction {
    param([string]$Hash, [string]$ErrorVector = $null)
    $parts = $Hash -split '\|'
    if ($parts.Count -ne 6) { return $null }
    $class  = $parts[0]; $dirty = $parts[1]
    $ahead  = [int]($parts[2] -replace 'a', '')
    $behind = [int]($parts[3] -replace 'b', '')
    $push   = $parts[4]; $pr = $parts[5]
    $action = $null; $dim = $null
    if ($class -eq 'B') {
        $dim = 'B_CLASS'; $action = 'gitbox b "<feature-name>"'
    } elseif ($class -eq 'W') {
        $dim = 'W_CLASS'; $action = 'gitbox r "<feature-name>"'
    } elseif ($class -eq 'F') {
        if    ($dirty -like 's*')                    { $action = 'gitbox c is blocked -- remove secret-pattern files from working tree' }
        elseif ($behind -gt 0)                       { $dim = 'BEHIND'; $action = 'gitbox s' }
        elseif ($pr -eq 'PRX')                       { $dim = 'CHECKS'; $action = 'fix CI failures, then: gitbox x' }
        elseif ($pr -in @('PRO','PRA'))               { $action = if ($dirty -like 'd*') { 'gitbox land "<message>"' } else { 'gitbox ship' } }
        elseif ($pr -eq 'PRD')                        { $action = if ($dirty -like 'd*') { 'gitbox c "<message>"  (draft PR open)' } else { 'mark PR ready: gh pr ready' } }
        elseif ($pr -eq 'PR-') {
            if    ($dirty -like 'd*')                { $action = 'gitbox c "<message>"' }
            elseif ($ahead -gt 0 -and $push -eq 'P') { $dim = 'NO_PR'; $action = 'gitbox o "<PR title>"' }
            elseif ($ahead -gt 0 -and $push -eq 'U') { $dim = 'NO_PUSH'; $action = 'gitbox uo "<PR title>"' }
            elseif ($ahead -eq 0 -and $dirty -eq 'c') { $action = 'nothing to do; make changes first' }
        }
    } else { $action = "unrecognised branch class '$class'" }
    # Error vector overrides for failure classes the hash cannot express after re-scan
    if ($ErrorVector) {
        switch ($ErrorVector) {
            'AUTH'      { $action = 'fix auth: gh auth login'; $dim = $null }
            'CONFLICT'  { $action = 'resolve conflict: git status -> fix files -> git add -> git rebase --continue'; $dim = $null }
            'PROTECTED' { $action = 'branch is protected -- check branch protection rules'; $dim = $null }
            'NO_REMOTE' { $action = 'no remote: git remote add origin <url>'; $dim = $null }
            'NO_BRANCH'    { $action = 'branch not found -- check: git branch -a'; $dim = $null }
            'NOT_ON_BASE'  { $action = 'gitbox base'; $dim = $null }
        }
    }
    return [pscustomobject]@{ Action = $action; Dim = $dim; Class = $class; Ahead = $ahead; Behind = $behind; Pr = $pr }
}

. (Join-Path $PSScriptRoot 'g-registry.ps1')
