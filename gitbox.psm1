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
    & (Join-Path $PSScriptRoot 'g-pr-checks.ps1')
}

function New-GitBranch {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Name
    )
    process { $Name | & (Join-Path $PSScriptRoot 'g-branch-create.ps1') }
}

function Push-GitBranch {
    & (Join-Path $PSScriptRoot 'g-push.ps1')
}

function Sync-GitBranch {
    & (Join-Path $PSScriptRoot 'g-branch-sync.ps1')
}

function Rename-GitBranch {
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Name
    )
    process { $Name | & (Join-Path $PSScriptRoot 'g-branch-rename.ps1') }
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
Set-Alias -Name 'g-push'           -Value 'Push-GitBranch'
Set-Alias -Name 'g-branch-create'  -Value 'New-GitBranch'
Set-Alias -Name 'g-pr-checks'      -Value 'Get-GitPullRequestChecks'

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
