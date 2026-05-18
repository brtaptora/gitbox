param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Name
)

begin {
    . (Join-Path $PSScriptRoot 'g-registry.ps1')
}

process {
    $repo = Get-Location

    $branch = git -C $repo branch --show-current 2>$null
    if (-not $branch) { Write-Host "not a git repo"; exit 1 }

    if ($branch -eq $Name) {
        Write-Host "already on $Name"
        exit 0
    }

    $stashed = $false
    if (@(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
        $stashOut = git -C $repo stash push -m 'gitbox-checkout' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "stash failed"
            $stashOut | ForEach-Object { Write-Host "  $_" }
            exit 1
        }
        $stashed = $true
    }

    $coOut = git -C $repo checkout $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "checkout $Name failed"
        $coOut | ForEach-Object { Write-Host "  $_" }
        if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
        exit 1
    }

    if ($stashed) {
        $popOut = git -C $repo stash pop 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "warning: stash pop failed -- run: git stash pop"
            $popOut | ForEach-Object { Write-Host "  $_" }
        }
    }

    Write-Host "on $Name"
    exit 0
}
