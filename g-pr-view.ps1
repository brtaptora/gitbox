$branch = git branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$prJson = gh pr view --json number,title,url,state,isDraft,body,reviewDecision,reviews,statusCheckRollup 2>$null
if (-not $prJson) { Write-Host "no PR for branch '$branch'"; exit 0 }

$pr          = $prJson | ConvertFrom-Json
$stateLabel  = if ($pr.isDraft) { 'draft' } elseif ($pr.state) { $pr.state.ToLower() } else { 'unknown' }
$reviewLabel = if ($pr.reviewDecision) { ($pr.reviewDecision -replace '_',' ').ToLower() } else { 'no review' }

Write-Host "PR #$($pr.number): $($pr.title)"
Write-Host "  $($pr.url)"
Write-Host "  $stateLabel | $reviewLabel"

if ($pr.body -and $pr.body.Trim()) {
    Write-Host ''
    $pr.body.Trim() -split "\r?\n" | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
}

if ($pr.reviews -and $pr.reviews.Count -gt 0) {
    Write-Host ''
    $pr.reviews | ForEach-Object {
        Write-Host "  $($_.author.login): $($_.state.ToLower() -replace '_',' ')"
    }
}

if ($pr.statusCheckRollup -and $pr.statusCheckRollup.Count -gt 0) {
    $pass    = @($pr.statusCheckRollup | Where-Object { $_.conclusion -eq 'SUCCESS' }).Count
    $fail    = @($pr.statusCheckRollup | Where-Object { $_.conclusion -in @('FAILURE','ERROR') }).Count
    $pending = @($pr.statusCheckRollup | Where-Object { $_.status -in @('QUEUED','IN_PROGRESS') }).Count
    $parts   = @()
    if ($pass)    { $parts += "$pass passed" }
    if ($fail)    { $parts += "$fail failed" }
    if ($pending) { $parts += "$pending pending" }
    Write-Host ''
    Write-Host "  checks: $($parts -join ', ')"
}
