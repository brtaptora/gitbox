param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Name
)

process {
    $repo = Get-Location

    $branch = git -C $repo branch --show-current 2>$null
    if (-not $branch) { Write-Host "not a git repo"; exit 1 }

    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9/_\-\.]*$') {
        Write-Host "invalid branch name: $Name"; exit 1
    }

    $baseBranch = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
    if (-not $baseBranch) { $baseBranch = "main" }

    if ($branch -ne $baseBranch) {
        Write-Host "must be on base branch ($baseBranch); currently on '$branch'"; exit 1
    }

    $pullOut = git -C $repo pull origin $baseBranch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pull failed"
        $pullOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    $checkoutOut = git -C $repo checkout -b $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "branch create failed: $($checkoutOut -join ' ')"; exit 1
    }

    Write-Host "created $Name from $baseBranch"
}
