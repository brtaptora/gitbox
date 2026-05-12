. (Join-Path $PSScriptRoot 'g-registry.ps1')

$state = Get-GitRepoState -RunLimit 1
if (-not $state) { Write-Host "not a git repo"; exit 1 }
if (-not $state.RepoName) { Write-Host "could not resolve repo name"; exit 1 }

$runBranch = $state.Branch
if (-not $state.Runs -or $state.Runs.Count -eq 0) {
    $runBranch = $state.BaseBranch
    $runsJson  = gh run list --repo $state.RepoName --branch $runBranch --limit 1 --json databaseId,name,status,conclusion,createdAt 2>$null
    if ($runsJson) { $state.Runs = $runsJson | ConvertFrom-Json }
}

if (-not $state.Runs -or $state.Runs.Count -eq 0) {
    Write-Host "no recent runs found for branch '$($state.Branch)' or base '$($state.BaseBranch)'"; exit 0
}

$run = $state.Runs[0]

# Poll until the run leaves queued/in_progress, up to ~90 seconds
$pollMax = 9; $pollSec = 10; $pollCount = 0
while ($run.status -in @('queued','in_progress') -and $pollCount -lt $pollMax) {
    Write-Host "run $($run.databaseId) -- $runBranch -- $($run.status) (waiting ${pollSec}s...)"
    Start-Sleep -Seconds $pollSec
    $pollCount++
    $refreshed = gh run view $run.databaseId --repo $state.RepoName --json databaseId,name,status,conclusion 2>$null | ConvertFrom-Json
    if ($refreshed) { $run = $refreshed }
}

$label = if ($run.conclusion) { $run.conclusion } else { $run.status }
Write-Host "run $($run.databaseId) -- $runBranch -- $($run.name) -- $label"
Write-Host ""

if ($run.status -notin @('completed')) {
    Write-Host "run did not complete within $($pollMax * $pollSec)s"; exit 1
}

$logLines = gh run view $run.databaseId --repo $state.RepoName --log 2>$null
if (-not $logLines) { Write-Host "no log available"; exit 0 }

# gh run view --log format: <job>\t<step>\t<timestamp> <text>
$stepOutputs = [ordered]@{}
foreach ($line in $logLines) {
    $parts = "$line" -split "`t", 3
    if ($parts.Count -lt 3) { continue }
    $step    = $parts[1].Trim()
    $content = $parts[2] -replace '^\d{4}-\d{2}-\d{2}T[\d:.]+Z ', ''
    if (-not $stepOutputs.Contains($step)) {
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
