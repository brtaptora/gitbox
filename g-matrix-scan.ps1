# Scans repo state and emits a status hash, then pipes it through g-matrix-resolve.
# Output: hash on line 1, recommended action on line 2.

param([switch]$GitOnly)

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

$state = Get-GitRepoState -GitOnly:$GitOnly
if (-not $state) { Write-Host "not a git repo"; exit 1 }

$class = if ($state.Branch -eq $state.BaseBranch) { "B" }
         elseif ($state.Branch -like "wip/*")      { "W" }
         else                                       { "F" }

$secretFiles = $state.DirtyFiles | Where-Object { $_ -match $SecretPattern }
$dirty = if ($secretFiles.Count -gt 0)         { "s$($state.DirtyFiles.Count)" }
         elseif ($state.DirtyFiles.Count -gt 0) { "d$($state.DirtyFiles.Count)" }
         else                                    { "c" }

$push = if (-not $state.RemoteBranch -or $state.Unpushed -gt 0) { "U" } else { "P" }

$prState = if (-not $state.PR)                                { "PR-" }
           elseif ($state.PR.state -eq "DRAFT")               { "PRD" }
           elseif ($state.PR.reviewDecision -eq "APPROVED")   { "PRA" }
           elseif ($state.PR.statusCheckRollup -eq "FAILURE") { "PRX" }
           elseif ($state.PR.state -eq "OPEN")                { "PRO" }
           else                                                { "PR-" }

$hash = "$class|$dirty|a$($state.Ahead)|b$($state.Behind)|$push|$prState"
Write-Host $hash
$hash | & "$PSScriptRoot\g-matrix-resolve.ps1"
exit $LASTEXITCODE
