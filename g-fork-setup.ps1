param(
    [Parameter(Position=0)]
    [string]$Upstream = ""
)

. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repoRoot = Get-Location
$inRepo   = (git -C $repoRoot rev-parse --is-inside-work-tree 2>$null) -eq 'true'

function Get-UpstreamBase {
    param([string]$UpstreamRepo)
    $defaultBase = gh repo view $UpstreamRepo --json defaultBranchRef -q .defaultBranchRef.name 2>$null
    if (-not $defaultBase) { $defaultBase = 'main' }
    $null = gh api "repos/$UpstreamRepo/branches/develop" 2>$null
    if ($LASTEXITCODE -eq 0) { return 'develop' }
    return $defaultBase
}

function Write-ForkConfig {
    param([string]$Dir, [string]$UpstreamRepo, [string]$BaseBranch)
    $cfg = [ordered]@{ BaseBranch = $BaseBranch; Upstream = $UpstreamRepo; MergeStrategy = 'squash' }
    $cfg | ConvertTo-Json | Set-Content (Join-Path $Dir '.gitbox.json') -Encoding UTF8
}

if ($inRepo) {
    $existingCfg = Get-GitboxConfig -RepoPath $repoRoot
    if ($existingCfg.Upstream -and -not $Upstream) {
        Write-Host "fork mode already configured; upstream = $($existingCfg.Upstream)"
        exit 0
    }

    $upRemoteUrl = git -C $repoRoot remote get-url upstream 2>$null
    if (-not $Upstream) {
        if ($upRemoteUrl -match 'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$') {
            $Upstream = $Matches[1]
        } else {
            $originUrl = git -C $repoRoot remote get-url origin 2>$null
            if ($originUrl -match 'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$') {
                $Upstream = $Matches[1]
            }
        }
    }
    if (-not $Upstream) {
        Write-Host "fork-setup: cannot detect upstream; pass it explicitly: gitbox fork owner/repo"
        exit 1
    }

    if (-not $upRemoteUrl) {
        Write-Host "forking $Upstream ..."
        $forkOut = gh repo fork --remote-name upstream 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "fork failed"
            $forkOut | ForEach-Object { Write-Host "  $_" }
            exit 1
        }
    } else {
        Write-Host "upstream remote already exists; skipping fork"
    }

    $baseBranch = Get-UpstreamBase -UpstreamRepo $Upstream
    Write-ForkConfig -Dir $repoRoot -UpstreamRepo $Upstream -BaseBranch $baseBranch
    Write-Host "fork ready  |origin = fork  |upstream = $Upstream  |base = $baseBranch"
    exit 0
}

# Outside a repo: fork + clone
if (-not $Upstream) {
    Write-Host "fork-setup: provide upstream repo: gitbox fork owner/repo"
    exit 1
}

Write-Host "forking and cloning $Upstream ..."
$forkOut = gh repo fork $Upstream --clone --remote-name upstream 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "fork failed"
    $forkOut | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$repoName   = $Upstream -split '/' | Select-Object -Last 1
$newDir     = Join-Path $repoRoot $repoName
$baseBranch = Get-UpstreamBase -UpstreamRepo $Upstream
Write-ForkConfig -Dir $newDir -UpstreamRepo $Upstream -BaseBranch $baseBranch

Write-Host "fork ready  |cd $repoName"
exit 0
