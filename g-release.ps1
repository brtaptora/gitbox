param(
    [Parameter(ValueFromPipeline)]
    [string]$Version,
    [switch]$View
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo   = Get-Location
$branch = git -C $repo branch --show-current 2>$null
if (-not $branch) { Write-Host "not a git repo"; exit 1 }

if ($View) {
    $tags = @(git -C $repo tag --sort=-version:refname 2>$null | Select-Object -First 10)
    if ($tags.Count -eq 0) { Write-Host "no releases found"; exit 0 }
    $tags | ForEach-Object { Write-Host $_ }
    exit 0
}

$state = Get-GitRepoState
$cfg   = Get-GitboxConfig -RepoPath $repo

if (-not $state) { Write-Host "not a git repo"; exit 1 }
if (-not $state.RepoName) { Write-Host "could not resolve repo name"; exit 1 }

if ($state.Branch -ne $cfg.BaseBranch) {
    Write-Host "must be on base branch ($($cfg.BaseBranch)); currently on '$($state.Branch)'"
    exit 1
}
if ($state.DirtyFiles.Count -gt 0) {
    Write-Host "working tree has $($state.DirtyFiles.Count) uncommitted file(s); commit or stash before releasing"
    exit 1
}
function Resolve-NextVersion {
    param([string]$Arg)

    $latest = git tag --sort=-version:refname 2>$null | Select-Object -First 1

    $bumpType = if ($Arg -in @('', 'patch', 'minor', 'major')) { if ($Arg) { $Arg } else { 'patch' } } else { $null }

    if (-not $bumpType) { return $Arg }

    if (-not $latest) { return 'v0.1.0' }

    if ($latest -match '^(v?)(\d+)\.(\d+)\.(\d+)$') {
        $prefix = $Matches[1]
        [int]$maj = $Matches[2]; [int]$min = $Matches[3]; [int]$pat = $Matches[4]
        switch ($bumpType) {
            'major' { $maj++; $min = 0; $pat = 0 }
            'minor' { $min++; $pat = 0 }
            'patch' { $pat++ }
        }
        return "${prefix}${maj}.${min}.${pat}"
    }

    if ($latest -match '^\d{4}\.\d{2}\.\d{2}') {
        $candidate = Get-Date -Format 'yyyy.MM.dd'
        $n = 1
        while (git tag --list $candidate 2>$null) { $n++; $candidate = "$(Get-Date -Format 'yyyy.MM.dd').$n" }
        return $candidate
    }

    Write-Host "unrecognized tag scheme '$latest'; pass an explicit version string"
    exit 1
}

$resolved = Resolve-NextVersion -Arg $Version

if ($Version -and $Version -notin @('patch','minor','major') -and
    $resolved -notmatch '^v?\d+\.\d+\.\d+$' -and
    $resolved -notmatch '^\d{4}\.\d{2}\.\d{2}(\.\d+)?$') {
    Write-Host "invalid version '$Version' -- use vMAJOR.MINOR.PATCH or: patch | minor | major"
    exit 1
}

if (-not $Version) {
    $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if ($isInteractive) {
        try { $answer = Read-Host "  release $resolved? [y/N]" } catch { $answer = 'n' }
        if ($answer -notmatch '^[yY]$') { Write-Host "release aborted"; exit 0 }
    }
}

if (git tag --list $resolved 2>$null) {
    Write-Host "tag '$resolved' already exists -- use a different version or: gitbox z -View to list existing tags"
    exit 1
}

Write-Host "releasing $resolved ..."

$prNumber = $null
if ($cfg.BaseBranch -ne $cfg.DefaultBranch) {
    $prOut = "release $resolved" | & (Join-Path $PSScriptRoot 'g-open-pr.ps1') -Base $cfg.DefaultBranch
    $prOut | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { exit 1 }

    foreach ($line in $prOut) {
        if ("$line" -match 'PR #(\d+)') { $prNumber = $Matches[1]; break }
    }

    & (Join-Path $PSScriptRoot 'g-pr-checks.ps1')
    if ($LASTEXITCODE -ne 0) { Write-Host "release blocked: checks failing on PR #$prNumber"; exit 1 }

    & (Join-Path $PSScriptRoot 'g-merge-rotate.ps1') -Steps 2
    if ($LASTEXITCODE -ne 0) { Write-Host "merge failed; branch '$($cfg.BaseBranch)' preserved"; exit 1 }

    $coOut = git -C $repo checkout $cfg.DefaultBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "checkout $($cfg.DefaultBranch) failed"; $coOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
    $pullOut = git -C $repo pull origin $cfg.DefaultBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "pull $($cfg.DefaultBranch) failed"; $pullOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
}

$tagOut = git -C $repo tag $resolved 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "tag failed: $($tagOut -join ' ')"; exit 1 }

$pushOut = git -C $repo push origin $resolved 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "push tag failed"; $pushOut | ForEach-Object { Write-Host "  $_" }; exit 1 }

if ($cfg.BaseBranch -ne $cfg.DefaultBranch) {
    $coBackOut = git -C $repo checkout $cfg.BaseBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "checkout $($cfg.BaseBranch) failed"; $coBackOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
    $pullBackOut = git -C $repo pull origin $cfg.BaseBranch 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "pull $($cfg.BaseBranch) failed"; $pullBackOut | ForEach-Object { Write-Host "  $_" }; exit 1 }
    Write-Host "released $resolved |PR #$prNumber merged |tagged |back on $($cfg.BaseBranch)"
} else {
    Write-Host "released $resolved |tagged |on $($cfg.BaseBranch)"
}
exit 0
