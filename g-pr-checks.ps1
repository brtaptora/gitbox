$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$repoName = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
if (-not $repoName) { Write-Host "could not resolve repo name"; exit 1 }

$prJson = gh pr list --repo $repoName --head $branch --json number,state,statusCheckRollup 2>$null | ConvertFrom-Json
if (-not $prJson -or $prJson.Count -eq 0) {
    Write-Host "no open PR for branch '$branch'"; exit 1
}

$pr = $prJson[0]

$checksJson = gh pr checks $pr.number --repo $repoName --json name,state,conclusion 2>$null | ConvertFrom-Json
if (-not $checksJson -or $checksJson.Count -eq 0) {
    Write-Host "PR #$($pr.number): no checks configured"; exit 0
}

$pass    = @($checksJson | Where-Object { $_.conclusion -eq 'SUCCESS' })
$fail    = @($checksJson | Where-Object { $_.conclusion -eq 'FAILURE' })
$pending = @($checksJson | Where-Object { $_.conclusion -notin @('SUCCESS','FAILURE') })

$total   = $checksJson.Count
$summary = "PR #$($pr.number) |$($pass.Count)/$total passed"
if ($fail.Count -gt 0)    { $summary += " |$($fail.Count) failed" }
if ($pending.Count -gt 0) { $summary += " |$($pending.Count) pending" }
Write-Host $summary

foreach ($c in $fail)    { Write-Host "  FAIL    $($c.name)" }
foreach ($c in $pending) { Write-Host "  PENDING $($c.name)" }
foreach ($c in $pass)    { Write-Host "  pass    $($c.name)" }

if ($fail.Count -gt 0) { exit 1 }
exit 0
