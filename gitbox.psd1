@{
    ModuleVersion     = '2.1.1'
    GUID              = '0d39b38f-fe51-4c5e-8623-909379972344'
    Author            = 'brtaptora'
    Description       = 'Git workflow automation suite: branch, commit, PR, merge, and gap analysis.'
    PowerShellVersion = '5.1'
    RootModule        = 'gitbox.psm1'

    FunctionsToExport = @(
        'Get-GitStatus',
        'Push-GitCommit',
        'New-GitPullRequest',
        'Invoke-GitMergeRotate',
        'Get-GitMatrix',
        'Resolve-GitMatrix',
        'Get-GitBacklog',
        'Get-GitCapabilities',
        'Get-GitRunLogs',
        'Rename-GitBranch',
        'Sync-GitBranch',
        'Push-GitBranch',
        'New-GitBranch',
        'Get-GitPullRequestChecks',
        'Switch-GitBranch',
        'Switch-GitBaseBranch',
        'Undo-GitCommit',
        'Publish-GitRelease',
        'Invoke-GitUnstack',
        'Get-GitStack',
        'Initialize-Gitbox',
        'Get-GitHealth',
        'Get-GitOptimization',
        'Get-GitDiff',
        'Get-GitLog',
        'Show-GitPullRequest',
        'Invoke-Gitbox'
    )

    AliasesToExport = @(
        'g-status',
        'g-commit-push',
        'g-open-pr',
        'g-merge-rotate',
        'g-matrix-scan',
        'g-matrix-resolve',
        'g-backlog',
        'g-capabilities',
        'g-run-logs',
        'g-branch-rename',
        'g-branch-sync',
        'g-push',
        'g-branch-create',
        'g-pr-checks',
        'g-branch-checkout',
        'g-branch-base',
        'g-revert',
        'g-release',
        'g-unstack',
        'g-stack',
        'g-init',
        'g-health',
        'g-optimization',
        'g-diff',
        'g-log',
        'g-pr-view',
        'gitbox',
        'gb'
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('git', 'github', 'workflow', 'automation', 'cli')
            ProjectUri = 'https://github.com/brtaptora/gitbox'
        }
    }
}
