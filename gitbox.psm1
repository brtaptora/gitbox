. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

function Get-GitStatus {
    param([switch]$d)
    & (Join-Path $PSScriptRoot 'g-status.ps1') @PSBoundParameters
}

function Push-GitCommit {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Message
    )
    process { $Message | & (Join-Path $PSScriptRoot 'g-commit-push.ps1') }
}

function New-GitPullRequest {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Title,
        [string]$Body = ''
    )
    process { $Title | & (Join-Path $PSScriptRoot 'g-open-pr.ps1') -Body $Body }
}

function Invoke-GitMergeRotate {
    & (Join-Path $PSScriptRoot 'g-merge-rotate.ps1')
}

function Get-GitMatrix {
    & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1')
}

function Resolve-GitMatrix {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Hash
    )
    process { $Hash | & (Join-Path $PSScriptRoot 'g-matrix-resolve.ps1') }
}

function Get-GitBacklog {
    & (Join-Path $PSScriptRoot 'g-backlog.ps1')
}

function Get-GitCapabilities {
    & (Join-Path $PSScriptRoot 'g-capabilities.ps1')
}

function Get-GitRunLogs {
    & (Join-Path $PSScriptRoot 'g-run-logs.ps1')
}

function Get-GitPullRequestChecks {
    & (Join-Path $PSScriptRoot 'g-pr.ps1') -Action checks
}

function New-GitBranch {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Name,
        [switch]$Stack
    )
    process { $Name | & (Join-Path $PSScriptRoot 'g-branch.ps1') -Action create -Stack:$Stack }
}

function Push-GitBranch {
    & (Join-Path $PSScriptRoot 'g-commit-push.ps1') -Action push
}

function Sync-GitBranch {
    & (Join-Path $PSScriptRoot 'g-branch.ps1') -Action sync
}

function Sync-GitFork {
    & (Join-Path $PSScriptRoot 'g-branch.ps1') -Action fork-sync
}

function Rename-GitBranch {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Name
    )
    process { $Name | & (Join-Path $PSScriptRoot 'g-branch.ps1') -Action rename }
}

function Switch-GitBranch {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Name
    )
    process { $Name | & (Join-Path $PSScriptRoot 'g-branch.ps1') -Action checkout }
}

function Switch-GitBaseBranch {
    param([switch]$NoStashPop)
    & (Join-Path $PSScriptRoot 'g-branch.ps1') -Action base -NoStashPop:$NoStashPop
}

function Undo-GitCommit {
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Ref
    )
    process { & (Join-Path $PSScriptRoot 'g-revert.ps1') @PSBoundParameters }
}

function Publish-GitRelease {
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Version,
        [switch]$View
    )
    process { & (Join-Path $PSScriptRoot 'g-release.ps1') @PSBoundParameters }
}

function Invoke-GitUnstack {
    param([switch]$Force)
    & (Join-Path $PSScriptRoot 'g-unstack.ps1') @PSBoundParameters
}

function Get-GitStack {
    & (Join-Path $PSScriptRoot 'g-stack.ps1')
}

function Initialize-Gitbox {
    & (Join-Path $PSScriptRoot 'g-init.ps1')
}

function Get-GitHealth {
    param([switch]$Plain, [switch]$Cov, [switch]$Uni, [switch]$CapV)
    & (Join-Path $PSScriptRoot 'g-health.ps1') @PSBoundParameters
}

function Get-GitOptimization {
    & (Join-Path $PSScriptRoot 'g-optimization.ps1')
}

function Get-GitDiff {
    & (Join-Path $PSScriptRoot 'g-diff.ps1')
}

function Get-GitLog {
    & (Join-Path $PSScriptRoot 'g-log.ps1')
}

function Show-GitPullRequest {
    & (Join-Path $PSScriptRoot 'g-pr.ps1') -Action view
}

Set-Alias -Name 'g-status'         -Value 'Get-GitStatus'
Set-Alias -Name 'g-commit-push'    -Value 'Push-GitCommit'
Set-Alias -Name 'g-open-pr'        -Value 'New-GitPullRequest'
Set-Alias -Name 'g-merge-rotate'   -Value 'Invoke-GitMergeRotate'
Set-Alias -Name 'g-matrix-scan'    -Value 'Get-GitMatrix'
Set-Alias -Name 'g-matrix-resolve' -Value 'Resolve-GitMatrix'
Set-Alias -Name 'g-backlog'        -Value 'Get-GitBacklog'
Set-Alias -Name 'g-capabilities'   -Value 'Get-GitCapabilities'
Set-Alias -Name 'g-run-logs'       -Value 'Get-GitRunLogs'
Set-Alias -Name 'g-branch-rename'  -Value 'Rename-GitBranch'
Set-Alias -Name 'g-branch-sync'    -Value 'Sync-GitBranch'
Set-Alias -Name 'g-fork-sync'      -Value 'Sync-GitFork'
Set-Alias -Name 'g-push'           -Value 'Push-GitBranch'
Set-Alias -Name 'g-branch-create'   -Value 'New-GitBranch'
Set-Alias -Name 'g-pr-checks'       -Value 'Get-GitPullRequestChecks'
Set-Alias -Name 'g-branch-checkout' -Value 'Switch-GitBranch'
Set-Alias -Name 'g-branch-base'     -Value 'Switch-GitBaseBranch'
Set-Alias -Name 'g-revert'          -Value 'Undo-GitCommit'
Set-Alias -Name 'g-release'         -Value 'Publish-GitRelease'
Set-Alias -Name 'g-unstack'         -Value 'Invoke-GitUnstack'
Set-Alias -Name 'g-stack'           -Value 'Get-GitStack'
Set-Alias -Name 'g-init'            -Value 'Initialize-Gitbox'
Set-Alias -Name 'g-health'          -Value 'Get-GitHealth'
Set-Alias -Name 'g-optimization'    -Value 'Get-GitOptimization'
Set-Alias -Name 'g-diff'            -Value 'Get-GitDiff'
Set-Alias -Name 'g-log'             -Value 'Get-GitLog'
Set-Alias -Name 'g-pr-view'         -Value 'Show-GitPullRequest'

function Invoke-Gitbox {
    param(
        [Parameter(Position=0)]
        [string]$Spec = '',
        [Parameter(ValueFromPipeline)]
        [string]$PipelineArg,
        [Parameter(Position=1, ValueFromRemainingArguments)]
        [string[]]$Rest,
        [switch]$AllowWip
    )
    process {
        if ($PipelineArg) {
            $PipelineArg | & (Join-Path $PSScriptRoot 'gitbox.ps1') $Spec @Rest -AllowWip:$AllowWip
        } else {
            & (Join-Path $PSScriptRoot 'gitbox.ps1') $Spec @Rest -AllowWip:$AllowWip
        }
    }
}

Set-Alias -Name 'gitbox' -Value 'Invoke-Gitbox'
Set-Alias -Name 'gb'     -Value 'Invoke-Gitbox'

$_gbRoot = $PSScriptRoot
$_wfDescs = [ordered]@{
    start   = 'Beginning a new ticket from the base branch'
    rename  = 'Promoting a wip branch before opening a PR'
    sync       = 'Branch is behind base'
    'sync-fork' = 'Syncing fork base branch from upstream'
    commit  = 'Saving incremental progress on an open PR'
    push    = 'Pushing commits made outside gitbox'
    pr      = 'Opening a PR on an already-pushed branch'
    checks  = 'Inspecting CI status'
    merge   = 'Merging an approved PR'
    revert  = 'Undoing a commit'
    draft   = 'Starting a new feature from a wip branch'
    land    = 'Final commit on a branch with an open PR'
    ship    = 'Merging a clean, already-committed branch'
    full    = 'One-shot from commit through merge'
    release = 'Promoting develop to main with a version tag'
    health  = 'Auditing script coverage'
}
# Ordinal (case-sensitive) ordered dict avoids [ordered]@{} treating s/S, b/B etc. as duplicate keys
$_flagDescs = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
$_flagDescs.Add('b','branch-create'); $_flagDescs.Add('r','branch-rename')
$_flagDescs.Add('e','fork-sync');     $_flagDescs.Add('s','branch-sync')
$_flagDescs.Add('c','commit-push')
$_flagDescs.Add('v','revert');        $_flagDescs.Add('u','push')
$_flagDescs.Add('o','open-pr');       $_flagDescs.Add('x','pr-checks')
$_flagDescs.Add('m','merge-rotate');  $_flagDescs.Add('z','release')
$_flagDescs.Add('H','health');        $_flagDescs.Add('Q','status')
$_flagDescs.Add('L','log');           $_flagDescs.Add('D','diff')
$_flagDescs.Add('P','pr-view');       $_flagDescs.Add('S','matrix-scan')
$_flagDescs.Add('B','backlog');       $_flagDescs.Add('C','capabilities')
$_flagDescs.Add('W','workflow-registry'); $_flagDescs.Add('O','optimization')
$_flagDescs.Add('X','run-logs')
$_gbCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (-not $_gbRoot) { return }

    $recommended = $null
    try {
        $scan = & (Join-Path $_gbRoot 'g-matrix-scan.ps1') -GitOnly 2>$null 6>&1
        $next = $scan | Where-Object { "$_" -match 'next:\s+gitbox\s+([a-z]+)' } | Select-Object -First 1
        if ($next -and "$next" -match 'gitbox\s+([a-z]+)') { $recommended = $Matches[1] }
    } catch {}

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $out  = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    if ($recommended -and $recommended -like "$wordToComplete*") {
        $rdesc = if ($_wfDescs.ContainsKey($recommended))  { $_wfDescs[$recommended] }
                 elseif ($_flagDescs.Contains($recommended)) { $_flagDescs[$recommended] }
                 else { $recommended }
        $out.Add([System.Management.Automation.CompletionResult]::new(
            $recommended, $recommended, 'ParameterValue', "matrix: next ($rdesc)"))
        [void]$seen.Add($recommended)
    }
    foreach ($wf in $_wfDescs.Keys) {
        if (-not $seen.Contains($wf) -and $wf -like "$wordToComplete*") {
            $out.Add([System.Management.Automation.CompletionResult]::new(
                $wf, $wf, 'ParameterValue', $_wfDescs[$wf]))
            [void]$seen.Add($wf)
        }
    }
    foreach ($f in $_flagDescs.Keys) {
        if (-not $seen.Contains($f) -and $f -like "$wordToComplete*") {
            $out.Add([System.Management.Automation.CompletionResult]::new(
                $f, $f, 'ParameterValue', $_flagDescs[$f]))
        }
    }
    $out
}.GetNewClosure()
Register-ArgumentCompleter -CommandName @('gitbox', 'gb') -ParameterName 'Spec' -ScriptBlock $_gbCompleter
