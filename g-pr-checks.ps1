. (Join-Path $PSScriptRoot 'g-registry.ps1')

$state = Get-GitRepoState
if (-not $state) { Write-Host "not a git repo"; exit 1 }
if (-not $state.RepoName) { Write-Host "could not resolve repo name"; exit 1 }

if (-not $state.PR) {
    Write-Host "no open PR for branch '$($state.Branch)'"; exit 1
}

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
exit 0
