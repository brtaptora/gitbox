param(
    [Parameter(ValueFromPipeline)]
    [string]$Title = "",

    [string]$Body = "",
    [string]$Base = "",
    [switch]$Draft
)

begin {
    . (Join-Path $PSScriptRoot 'g-registry.ps1')
}

process {
    $repo = Get-Location

    $remote = git -C $repo remote get-url origin 2>$null
    if ($remote -notmatch '[/@]github\.com[:/]') {
        Write-Host "remote is not GitHub: $remote"; exit 1
    }

    $repoName   = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    $branch     = git -C $repo branch --show-current 2>$null
    $baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

    $existing = gh pr list --repo $repoName --head $branch --json number,url 2>$null | ConvertFrom-Json
    if ($existing -and $existing.Count -gt 0) {
        Write-Host "PR #$($existing[0].number) already open |$($existing[0].url)"
        exit 0
    }

    if (-not $Body) {
        $tplPaths = @(
            (Join-Path $repo '.github/pull_request_template.md'),
            (Join-Path $repo '.github/PULL_REQUEST_TEMPLATE.md')
        )
        foreach ($p in $tplPaths) {
            if (Test-Path $p) { $Body = Get-Content $p -Raw; break }
        }
    }

    if (-not $Title) {
        $cfg = Get-GitboxConfig -RepoPath $repo
        if ($cfg.Editor) {
            $editorOut = Invoke-GitboxEditor -Template "# PR Title (first line)`n# PR Body (remaining lines)`n# Lines starting with # are stripped"
            if ($editorOut) {
                $editorLines = $editorOut -split "`n" | Where-Object { $_ }
                $Title = $editorLines[0]
                $Body  = ($editorLines[1..($editorLines.Count - 1)]) -join "`n"
            }
        } else {
            try { $Title = Read-Host "  PR title (Enter for --fill)" } catch { }
        }
    }

    # Auto-detect stack parent: find the open PR branch that is the closest git ancestor of HEAD
    if (-not $Base) {
        $allOpenPRs = gh pr list --repo $repoName --state open --json headRefName 2>$null | ConvertFrom-Json
        if ($allOpenPRs) {
            $bestParent = $null; $bestCount = [int]::MaxValue
            foreach ($c in $allOpenPRs) {
                if ($c.headRefName -eq $branch) { continue }
                git -C $repo merge-base --is-ancestor "origin/$($c.headRefName)" HEAD 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $cnt = (git -C $repo rev-list "origin/$($c.headRefName)..HEAD" 2>$null | Measure-Object -Line).Lines
                    if ($cnt -lt $bestCount) { $bestCount = $cnt; $bestParent = $c.headRefName }
                }
            }
            if ($bestParent) { $Base = $bestParent }
        }
    }

    $target    = if ($Base) { $Base } else { $baseBranch }
    $draftFlag = if ($Draft) { '--draft' } else { $null }
    Write-Host "opening PR ..."
    $url = if ($Title) {
        gh pr create --repo $repoName --title $Title --base $target --body $Body @(if ($draftFlag) { $draftFlag }) 2>&1
    } else {
        gh pr create --repo $repoName --fill --base $target @(if ($draftFlag) { $draftFlag }) 2>&1
    }
    if ($LASTEXITCODE -ne 0) { Write-Host "pr create failed"; $url | ForEach-Object { Write-Host "  $_" }; exit 1 }
    $number = $url -replace ".*/pull/", ""

    Write-Host "PR #$number opened |$url"
    exit 0
}
