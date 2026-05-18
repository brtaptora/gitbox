param(
    [Parameter(ValueFromPipeline)]
    [string]$Ref
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo   = Get-Location
$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$target = if ($Ref) { $Ref } else { 'HEAD' }

$resolved = git -C $repo rev-parse --verify $target 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "ref '$target' not found"; exit 1 }

$shortHash = git -C $repo rev-parse --short $target 2>$null
$subject   = git -C $repo log -1 --pretty=%s $target 2>$null

$customMessage = $null
try {
    $confirm = Read-Host "  revert $shortHash ('$subject') -- use default message? [Y/n]"
    if ($confirm -match '^[Nn]') {
        $customMessage = Read-Host "  revert message"
    }
} catch { }

Write-Host "reverting $shortHash ..."
if ($customMessage) {
    $revertOut = git -C $repo revert $target --no-commit 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "revert failed"
        $revertOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    $commitOut = git -C $repo commit -m $customMessage 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "commit failed; revert staged but not committed -- run: git commit -m <message>"
        $commitOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
} else {
    $revertOut = git -C $repo revert $target --no-edit 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "revert failed"
        $revertOut | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
}

Write-Host "reverted $shortHash -- new commit on $branch"
exit 0
