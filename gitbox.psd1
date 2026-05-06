@{
    ModuleVersion     = '1.0.0'
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
        'Rename-GitBranch',
        'Sync-GitBranch',
        'Push-GitBranch',
        'New-GitBranch'
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
        'g-branch-rename',
        'g-branch-sync',
        'g-push',
        'g-branch-create'
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('git', 'github', 'workflow', 'automation', 'cli')
            ProjectUri = 'https://github.com/brtaptora/gitbox'
        }
    }
}
