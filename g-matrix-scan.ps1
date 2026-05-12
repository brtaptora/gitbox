# Scans repo state and emits a status hash, then pipes it through g-matrix-resolve.
# Output: hash on line 1, recommended action on line 2.

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

$repo = Get-Location

$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

$repoMeta   = gh repo view --json nameWithOwner 2>$null | ConvertFrom-Json
$baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

# --- branch class ---
$class = if ($branch -eq $baseBranch)    { "B" }
         elseif ($branch -like "wip/*")  { "W" }
         else                            { "F" }

# --- dirty + secret detection ---
$dirtyFiles = git -C $repo status --porcelain 2>$null | Where-Object { $_ -ne "" }
$dirtyCount = $dirtyFiles.Count
$secretFiles = $dirtyFiles | Where-Object { $_ -match $SecretPattern }
$dirty = if ($secretFiles.Count -gt 0) { "s$dirtyCount" }
         elseif ($dirtyCount -gt 0)    { "d$dirtyCount" }
         else                          { "c" }

# --- ahead / behind base ---
$ahead  = 0
$behind = 0
$remoteBase = git -C $repo rev-parse --verify "origin/$baseBranch" 2>$null
if ($remoteBase) {
    $ahead  = (git -C $repo rev-list "origin/${baseBranch}..HEAD" 2>$null | Measure-Object -Line).Lines
    $behind = (git -C $repo rev-list "HEAD..origin/${baseBranch}" 2>$null | Measure-Object -Line).Lines
}

# --- push state ---
$remoteBranch = git -C $repo rev-parse --verify "origin/$branch" 2>$null
$push = if (-not $remoteBranch) { "U" }
        else {
            $unpushed = (git -C $repo rev-list "origin/${branch}..HEAD" 2>$null | Measure-Object -Line).Lines
            if ($unpushed -gt 0) { "U" } else { "P" }
        }

# --- PR state ---
$prState = "PR-"
if ($repoMeta) {
    $prJson = gh pr list --repo $repoMeta.nameWithOwner --head $branch --json number,state,reviewDecision,statusCheckRollup 2>$null | ConvertFrom-Json
    if ($prJson -and $prJson.Count -gt 0) {
        $pr = $prJson[0]
        $prState = if ($pr.state -eq "DRAFT")                                   { "PRD" }
                   elseif ($pr.reviewDecision -eq "APPROVED")                   { "PRA" }
                   elseif ($pr.statusCheckRollup -eq "FAILURE")                 { "PRX" }
                   elseif ($pr.state -eq "OPEN")                                { "PRO" }
                   else                                                          { "PR-" }
    }
}

$hash = "$class|$dirty|a$ahead|b$behind|$push|$prState"
Write-Host $hash
$hash | & "$PSScriptRoot\g-matrix-resolve.ps1"
exit $LASTEXITCODE
