param(
    [switch]$d
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$state = Get-GitRepoState
if (-not $state) { Write-Host "not a git repo"; exit 1 }

$dirty = $state.DirtyFiles.Count

$aheadStr  = if ($state.Ahead  -gt 0) { "+$($state.Ahead) ahead" }  else { "up to date" }
$behindStr = if ($state.Behind -gt 0) { "-$($state.Behind) behind" } else { $null }
$dirtyStr  = if ($dirty -gt 0) { "$dirty dirty" } else { "clean" }

$prLabel = if ($state.PR) { "PR #$($state.PR.number) $($state.PR.state.ToUpper())" } else { "no PR" }

$parts = @($state.Branch, $aheadStr)
if ($behindStr) { $parts += $behindStr }
$parts += $dirtyStr
$parts += $prLabel

Write-Host ($parts -join " | ")

if ($d -and $state.PR) {
    $body = gh pr view $state.PR.number --json body -q .body 2>$null
    if ($body) { Write-Host ""; Write-Host $body }
}
exit 0
