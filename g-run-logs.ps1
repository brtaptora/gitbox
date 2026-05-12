. (Join-Path $PSScriptRoot 'g-registry.ps1')

$state = Get-GitRepoState -RunLimit 1
if (-not $state) { Write-Host "not a git repo"; exit 1 }
if (-not $state.RepoName) { Write-Host "could not resolve repo name"; exit 1 }

if (-not $state.Runs -or $state.Runs.Count -eq 0) {
    Write-Host "no recent runs found for branch '$($state.Branch)'"; exit 0
}

$run = $state.Runs[0]
$label = if ($run.conclusion) { $run.conclusion } else { $run.status }
Write-Host "run $($run.databaseId) -- $($run.name) -- $label"
Write-Host ""

$logLines = gh run view $run.databaseId --repo $state.RepoName --log 2>$null
if (-not $logLines) { Write-Host "no log available"; exit 0 }

# gh run view --log format: <job>\t<step>\t<timestamp> <text>
$stepOutputs = [ordered]@{}
foreach ($line in $logLines) {
    $parts = "$line" -split "`t", 3
    if ($parts.Count -lt 3) { continue }
    $step    = $parts[1].Trim()
    $content = $parts[2] -replace '^\d{4}-\d{2}-\d{2}T[\d:.]+Z ', ''
    if (-not $stepOutputs.ContainsKey($step)) {
        $stepOutputs[$step] = [System.Collections.Generic.List[string]]::new()
    }
    $stepOutputs[$step].Add($content)
}

foreach ($stepName in $stepOutputs.Keys) {
    Write-Host "=== $stepName ==="
    foreach ($l in $stepOutputs[$stepName]) { Write-Host $l }
    Write-Host ""
}
exit 0
