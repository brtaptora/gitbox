param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Name,

    [switch]$Force
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

    $existsLocal  = git -C $repo branch --list $Name 2>$null
    $existsRemote = git -C $repo branch -r --list "origin/$Name" 2>$null
    if ($existsLocal -or $existsRemote) {
        Write-Host "branch '$Name' already exists"
        if (-not $Force) {
            $confirm = Read-Host "check it out? [y/N]"
            if ($confirm -notmatch '^[yY]$') { exit 1 }
        }
        git -C $repo checkout $Name 2>&1 | Out-Null
        Write-Host "checked out $Name"
        exit 0
    }

    if ($branch -ne $baseBranch) {
        if ($branch -match '^wip/') {
            # wip/ is a known transitional state after merge-rotate; auto-checkout base
            $coOut = git -C $repo checkout $baseBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "checkout $baseBranch failed: $($coOut -join ' ')"; exit 1
            }
        } else {
            Write-Host "must be on base branch ($baseBranch); currently on '$branch'"; exit 1
        }
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
    exit 0
}
