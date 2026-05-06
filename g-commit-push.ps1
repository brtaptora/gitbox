param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Message
)

process {
    $repo = Get-Location

    $branch = git -C $repo branch --show-current 2>$null
    if (-not $branch) { Write-Host "not a git repo"; exit 1 }

    # must run before git add -A; staged files cannot be selectively removed without resetting the index
    $secretPattern = '\.env$|\.key$|\.pem$|\.pfx$|\.p12$|credentials|secrets?\.|id_rsa|id_ed25519'
    $pending = git -C $repo status --porcelain 2>$null | Where-Object { $_ } | ForEach-Object { $_.Substring(3) }
    $blocked = $pending | Where-Object { $_ -match $secretPattern }
    if ($blocked) {
        Write-Host "secret guard: blocked -- remove these files before committing:"
        $blocked | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    git -C $repo add -A 2>$null
    $staged = (git -C $repo diff --cached --name-only 2>$null | Measure-Object -Line).Lines
    if ($staged -eq 0) { Write-Host "nothing to commit"; exit 0 }

    git -C $repo commit -m $Message 2>$null | Out-Null
    $sha = git -C $repo rev-parse --short HEAD 2>$null

    $pushOut = git -C $repo push -u origin $branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "push failed: origin/$branch"
        $pushOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    Write-Host "staged $staged |committed $sha |pushed origin/$branch"
}
