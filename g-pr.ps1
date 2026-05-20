[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('view','checks')]
    [string]$Action
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$branch = git branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

switch ($Action) {

    'view' {
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
            $pr.reviews | ForEach-Object { Write-Host "  $($_.author.login): $($_.state.ToLower() -replace '_',' ')" }
        }
        if ($pr.statusCheckRollup -and $pr.statusCheckRollup.Count -gt 0) {
            $pass    = @($pr.statusCheckRollup | Where-Object { $_.conclusion -eq 'SUCCESS' }).Count
            $fail    = @($pr.statusCheckRollup | Where-Object { $_.conclusion -in @('FAILURE','ERROR') }).Count
            $pending = @($pr.statusCheckRollup | Where-Object { $_.status -in @('QUEUED','IN_PROGRESS') }).Count
            $parts   = @()
            if ($pass)    { $parts += "$pass passed" }
            if ($fail)    { $parts += "$fail failed" }
            if ($pending) { $parts += "$pending pending" }
            Write-Host ''; Write-Host "  checks: $($parts -join ', ')"
        }
    }

    'checks' {
        $state = Get-GitRepoState
        if (-not $state) { Write-Host "not a git repo"; exit 1 }
        if (-not $state.RepoName) { Write-Host "could not resolve repo name"; exit 1 }
        if (-not $state.PR) { Write-Host "no open PR for branch '$($state.Branch)'"; exit 1 }
        Write-Host "checking PR #$($state.PR.number) ..."
        $checksJson = gh pr checks $state.PR.number --repo $state.RepoName --json name,state,conclusion 2>$null | ConvertFrom-Json
        if (-not $checksJson -or $checksJson.Count -eq 0) {
            Write-Host "PR #$($state.PR.number): no checks configured"; exit 0
        }
        $pass    = @($checksJson | Where-Object { $_.conclusion -eq 'SUCCESS' })
        $fail    = @($checksJson | Where-Object { $_.conclusion -eq 'FAILURE' })
        $pending = @($checksJson | Where-Object { $_.conclusion -notin @('SUCCESS','FAILURE') })
        $total   = $checksJson.Count
        $summary = "PR #$($state.PR.number) |$($pass.Count)/$total passed"
        if ($fail.Count -gt 0)    { $summary += " |$($fail.Count) failed" }
        if ($pending.Count -gt 0) { $summary += " |$($pending.Count) pending" }
        Write-Host $summary
        foreach ($c in $fail)    { Write-Host "  FAIL    $($c.name)" }
        foreach ($c in $pending) { Write-Host "  PENDING $($c.name)" }
        foreach ($c in $pass)    { Write-Host "  pass    $($c.name)" }
        if ($fail.Count -gt 0) { exit 1 }
    }
}
