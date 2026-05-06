param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Message
)

process {
    $repo = Get-Location

    $branch = git -C $repo branch --show-current 2>$null
    if (-not $branch) { Write-Host "not a git repo"; exit 1 }

    # stage all tracked + new files
    git -C $repo add -A 2>$null
    $staged = (git -C $repo diff --cached --name-only 2>$null | Measure-Object -Line).Lines
    if ($staged -eq 0) { Write-Host "nothing to commit"; exit 0 }

    # commit
    git -C $repo commit -m $Message 2>$null | Out-Null
    $sha = git -C $repo rev-parse --short HEAD 2>$null

    # push
    git -C $repo push -u origin $branch 2>$null | Out-Null

    Write-Host "staged $staged |committed $sha |pushed origin/$branch"
}
