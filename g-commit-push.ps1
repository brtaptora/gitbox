param(
    [Parameter(ValueFromPipeline)]
    [string]$Message,
    [string]$Action = '',
    [switch]$Amend,
    [string[]]$Include,
    [string[]]$Exclude
)

begin {
    . (Join-Path $PSScriptRoot 'g-error-vectors.ps1')
}

process {
    $repo = Get-Location

    $branch = git -C $repo branch --show-current 2>$null
    if (-not $branch) { Write-Host "not a git repo"; exit 1 }

    $cfg        = Get-GitboxConfig -RepoPath $repo
    $baseBranch = $cfg.BaseBranch

    if ($Action -eq 'push') {
        if ($branch -eq $baseBranch) {
            Write-Host "on base branch; push is for feature branches only"; exit 1
        }
        if ($cfg.Upstream) {
            $originUrl = git -C $repo remote get-url origin 2>$null
            if ($originUrl -and $originUrl.Contains($cfg.Upstream)) {
                Write-Host "fork guard: origin points to upstream '$($cfg.Upstream)' -- reconfigure origin to your fork"
                exit 1
            }
        }
        $remoteRef = git -C $repo rev-parse --verify "origin/$branch" 2>$null
        $noRemote  = ($LASTEXITCODE -ne 0)
        $countBase = if ($noRemote) { "origin/${baseBranch}" } else { "origin/${branch}" }
        $ahead     = (git -C $repo rev-list "${countBase}..HEAD" 2>$null | Measure-Object -Line).Lines
        if (-not $noRemote -and $ahead -eq 0) {
            Write-Host "nothing to push; origin/$branch is up to date"; exit 0
        }
        $pushOut = git -C $repo push origin -u $branch 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "push failed"
            if ($VerbosePreference -ne 'SilentlyContinue') { $pushOut | ForEach-Object { Write-Host "  $_" } }
            exit 1
        }
        Write-Host "pushed $ahead commit$(if ($ahead -ne 1) {'s'}) to origin/$branch"
        exit 0
    }

    if ($branch -eq $cfg.BaseBranch) {
        Write-Host "commit-abort: on base branch '$branch' -- create a feature branch first: gitbox b ""feat/name"""
        exit 1
    }
    if ($cfg.Upstream) {
        $originUrl = git -C $repo remote get-url origin 2>$null
        if ($originUrl -and $originUrl.Contains($cfg.Upstream)) {
            Write-Host "fork guard: origin points to upstream '$($cfg.Upstream)' -- reconfigure origin to your fork"
            exit 1
        }
    }

    # must run before git add -A; staged files cannot be selectively removed without resetting the index
    $pending = git -C $repo status --porcelain 2>$null | Where-Object { $_ } | ForEach-Object { $_.Substring(3) }
    $blocked = $pending | Where-Object { $_ -match $SecretPattern }
    if ($blocked) {
        Write-Host "secret guard: blocked -- remove these files before committing:"
        $blocked | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    $allExcludes = @()
    if ($Exclude)                         { $allExcludes += $Exclude }
    if ($cfg.NeverStage -and $cfg.NeverStage.Count -gt 0) { $allExcludes += $cfg.NeverStage }

    if ($Include) {
        $addOut = git -C $repo add -- @Include 2>&1
    } else {
        $addOut = git -C $repo add -A 2>&1
        if ($LASTEXITCODE -eq 0 -and $allExcludes.Count -gt 0) {
            foreach ($pat in $allExcludes) {
                git -C $repo restore --staged -- $pat 2>$null | Out-Null
            }
        }
    }
    if ($LASTEXITCODE -ne 0) { Write-Host "stage failed"; if ($VerbosePreference -ne 'SilentlyContinue') { $addOut | ForEach-Object { Write-Host "  $_" } }; exit 1 }
    $staged = (git -C $repo diff --cached --name-only 2>$null | Measure-Object -Line).Lines
    if ($staged -eq 0) { Write-Host "nothing to commit"; exit 0 }

    if (-not $Message) {
        $cfg = Get-GitboxConfig -RepoPath $repo
        if ($cfg.Editor) {
            $Message = Invoke-GitboxEditor -Template "# Commit message (first line is subject)`n# Lines starting with # are stripped"
            if (-not $Message) { Write-Host "no commit message; aborting"; exit 1 }
        } else {
            try {
                $Message = Read-Host "  commit message"
            } catch {
                Write-Host "no commit message; pass a message or enable Editor in .gitbox.json"
                exit 1
            }
            if (-not $Message) { Write-Host "no commit message; aborting"; exit 1 }
        }
    }

    if ($Amend) {
        $commitOut = if ($Message) {
            git -C $repo commit --amend -m $Message 2>&1
        } else {
            git -C $repo commit --amend --no-edit 2>&1
        }
        if ($LASTEXITCODE -ne 0) { Write-Host "amend failed"; if ($VerbosePreference -ne 'SilentlyContinue') { $commitOut | ForEach-Object { Write-Host "  $_" } }; exit 1 }
        $sha = git -C $repo rev-parse --short HEAD 2>$null

        $pushOut = git -C $repo push -u origin $branch --force-with-lease 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "push failed: origin/$branch"
            if ($VerbosePreference -ne 'SilentlyContinue') { $pushOut | ForEach-Object { Write-Host "  $_" } }
            exit 1
        }

        Write-Host "staged $staged |amended $sha |pushed origin/$branch (force)"
    } else {
        $commitOut = git -C $repo commit -m $Message 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "commit failed"; if ($VerbosePreference -ne 'SilentlyContinue') { $commitOut | ForEach-Object { Write-Host "  $_" } }; exit 1 }
        $sha = git -C $repo rev-parse --short HEAD 2>$null

        $pushOut = git -C $repo push -u origin $branch 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "push failed: origin/$branch"
            if ($VerbosePreference -ne 'SilentlyContinue') { $pushOut | ForEach-Object { Write-Host "  $_" } }
            exit 1
        }

        Write-Host "staged $staged |committed $sha |pushed origin/$branch"
    }
    exit 0
}
