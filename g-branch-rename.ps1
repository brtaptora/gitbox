param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Name
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

process {
    $repo = Get-Location

    $oldName = git -C $repo branch --show-current 2>$null
    if (-not $oldName) { Write-Host "not a git repo"; exit 1 }

    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9/_\-\.]*$') {
        Write-Host "invalid branch name: $Name"; exit 1
    }

    $cfg = Get-GitboxConfig -RepoPath $repo
    if ($oldName -eq $cfg.BaseBranch) {
        Write-Host "rename-abort: cannot rename base branch '$oldName'"; exit 1
    }

    if ($oldName -notlike 'wip/*') {
        Write-Host "warning: current branch '$oldName' is not a wip/ branch"
    }

    $renameOut = git -C $repo branch -m $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "rename failed: $($renameOut -join ' ')"; exit 1
    }

    # capture before the ref check changes LASTEXITCODE
    git -C $repo rev-parse --verify "origin/$oldName" 2>$null | Out-Null
    $hadRemote = ($LASTEXITCODE -eq 0)

    $pushOut = git -C $repo push origin -u $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "push failed: branch renamed locally to '$Name' but not pushed"
        $pushOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    if ($hadRemote) {
        $delOut = git -C $repo push origin --delete $oldName 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "  warning: remote branch delete failed: $($delOut -join ' ')" }
    }

    Write-Host "renamed $oldName -> $Name"
    exit 0
}
