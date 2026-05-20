[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('create','rename','checkout','sync','base','fork-sync')]
    [string]$Action,

    [Parameter(ValueFromPipeline)]
    [string]$Name = "",

    [switch]$Force,
    [switch]$Stack,
    [switch]$NoStashPop
)

begin {
    . (Join-Path $PSScriptRoot 'g-registry.ps1')
}

process {
    $repo       = Get-Location
    $branch     = git -C $repo branch --show-current 2>$null
    if (-not $branch) { Write-Host "not a git repo"; exit 1 }
    $cfg        = Get-GitboxConfig -RepoPath $repo
    $baseBranch = $cfg.BaseBranch

    switch ($Action) {

        'create' {
            if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9/_\-\.]*$') {
                Write-Host "invalid branch name: $Name"; exit 1
            }
            $existsLocal  = git -C $repo branch --list $Name 2>$null
            $existsRemote = git -C $repo branch -r --list "origin/$Name" 2>$null
            if ($existsLocal -or $existsRemote) {
                Write-Host "branch '$Name' already exists"
                if (-not $Force) {
                    $confirm = $null
                    try { $confirm = Read-Host "check it out? [y/N]" } catch { }
                    if ($confirm -notmatch '^[yY]$') { exit 1 }
                }
                git -C $repo checkout $Name 2>&1 | Out-Null
                Write-Host "checked out $Name"; exit 0
            }
            $parentBranch = $baseBranch
            if ($Stack) {
                $parentBranch = $branch
            } else {
                if ($branch -ne $baseBranch) {
                    if ($branch -match '^wip/') {
                        $coOut = git -C $repo checkout $baseBranch 2>&1
                        if ($LASTEXITCODE -ne 0) { Write-Host "checkout $baseBranch failed: $($coOut -join ' ')"; exit 1 }
                    } else {
                        Write-Host "must be on base branch ($baseBranch); currently on '$branch'"; exit 1
                    }
                }
                $pullOut = git -C $repo pull origin $baseBranch 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "pull failed"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $pullOut | ForEach-Object { Write-Host "  $_" } }
                    exit 1
                }
            }
            $checkoutOut = git -C $repo checkout -b $Name 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "branch create failed: $($checkoutOut -join ' ')"; exit 1 }
            if ($Stack -and $cfg.MergeStrategy -eq 'squash') {
                Write-Host "  warning: MergeStrategy=squash causes rebase conflicts during 'gitbox n' -- set MergeStrategy to 'merge' for stacked PRs"
            }
            Write-Host "created $Name from $parentBranch"
        }

        'rename' {
            if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9/_\-\.]*$') {
                Write-Host "invalid branch name: $Name"; exit 1
            }
            if ($branch -eq $baseBranch) { Write-Host "rename-abort: cannot rename base branch '$branch'"; exit 1 }
            if ($branch -notlike 'wip/*') { Write-Host "warning: current branch '$branch' is not a wip/ branch" }
            $renameOut = git -C $repo branch -m $Name 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "rename failed: $($renameOut -join ' ')"; exit 1 }
            git -C $repo rev-parse --verify "origin/$branch" 2>$null | Out-Null
            $hadRemote = ($LASTEXITCODE -eq 0)
            $pushOut = git -C $repo push origin -u $Name 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "push failed: branch renamed locally to '$Name' but not pushed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $pushOut | ForEach-Object { Write-Host "  $_" } }
                exit 1
            }
            if ($hadRemote) {
                $delOut = git -C $repo push origin --delete $branch 2>&1
                if ($LASTEXITCODE -ne 0) { Write-Host "  warning: remote branch delete failed: $($delOut -join ' ')" }
            }
            Write-Host "renamed $branch -> $Name"
        }

        'checkout' {
            if ($branch -eq $Name) { Write-Host "already on $Name"; exit 0 }
            $stashed = $false
            if (@(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
                $stashOut = git -C $repo stash push -m 'gitbox-checkout' 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "stash failed"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $stashOut | ForEach-Object { Write-Host "  $_" } }
                    exit 1
                }
                $stashed = $true
            }
            $coOut = git -C $repo checkout $Name 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "checkout $Name failed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $coOut | ForEach-Object { Write-Host "  $_" } }
                if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                exit 1
            }
            if ($stashed) {
                $popOut = git -C $repo stash pop 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "warning: stash pop failed -- run: git stash pop"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $popOut | ForEach-Object { Write-Host "  $_" } }
                }
            }
            Write-Host "on $Name"
        }

        'sync' {
            if ($branch -eq $baseBranch) { Write-Host "already on base branch; run: git pull origin $baseBranch"; exit 1 }
            $fetchOut = git -C $repo fetch origin $baseBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "fetch failed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $fetchOut | ForEach-Object { Write-Host "  $_" } }
                exit 1
            }
            $behind = (git -C $repo rev-list "HEAD..origin/${baseBranch}" 2>$null | Measure-Object -Line).Lines
            if ($behind -eq 0) { Write-Host "already up to date with origin/$baseBranch"; exit 0 }
            $stashed = $false
            if (@(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
                $stashOut = git -C $repo stash push -m 'gitbox-sync' 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "stash failed"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $stashOut | ForEach-Object { Write-Host "  $_" } }
                    exit 1
                }
                $stashed = $true
            }
            $rebaseOut = git -C $repo rebase "origin/$baseBranch" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "rebase conflict: resolve manually then run: git rebase --continue"
                if ($VerbosePreference -ne 'SilentlyContinue') { $rebaseOut | ForEach-Object { Write-Host "  $_" } }
                git -C $repo rebase --abort 2>$null | Out-Null
                Write-Host "rebase aborted; working tree restored"
                if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                exit 1
            }
            if ($stashed) {
                $popOut = git -C $repo stash pop 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "warning: stash pop after rebase failed -- run: git stash pop"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $popOut | ForEach-Object { Write-Host "  $_" } }
                }
            }
            $ahead = (git -C $repo rev-list "origin/${baseBranch}..HEAD" 2>$null | Measure-Object -Line).Lines
            Write-Host "synced $branch onto origin/$baseBranch |+$ahead ahead |0 behind"
        }

        'base' {
            if ($branch -eq $baseBranch) { Write-Host "already on $baseBranch"; exit 0 }
            $stashed = $false
            if (@(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
                $stashOut = git -C $repo stash push -m 'gitbox-base' 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "stash failed"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $stashOut | ForEach-Object { Write-Host "  $_" } }
                    exit 1
                }
                $stashed = $true
            }
            $coOut = git -C $repo checkout $baseBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "checkout $baseBranch failed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $coOut | ForEach-Object { Write-Host "  $_" } }
                if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                exit 1
            }
            $pullOut = git -C $repo pull origin $baseBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "pull $baseBranch failed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $pullOut | ForEach-Object { Write-Host "  $_" } }
                if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                exit 1
            }
            if ($stashed) {
                if ($NoStashPop) {
                    Write-Host "  stash preserved -- run: git stash pop to restore changes"
                } else {
                    $popOut = git -C $repo stash pop 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "warning: stash pop failed -- run: git stash pop"
                        if ($VerbosePreference -ne 'SilentlyContinue') { $popOut | ForEach-Object { Write-Host "  $_" } }
                    }
                }
            }
            Write-Host "on $baseBranch | pulled origin/$baseBranch"
        }

        'fork-sync' {
            if (-not $cfg.Upstream) {
                Write-Host "fork-sync requires Upstream in .gitbox.json -- run: gitbox fork <owner/repo>"; exit 1
            }
            $upstreamUrl = git -C $repo remote get-url upstream 2>$null
            if (-not $upstreamUrl) {
                Write-Host "upstream remote not found -- run: git remote add upstream https://github.com/$($cfg.Upstream).git"; exit 1
            }
            $fetchOut = git -C $repo fetch upstream $baseBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "fetch upstream failed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $fetchOut | ForEach-Object { Write-Host "  $_" } }
                exit 1
            }
            $behind = (git -C $repo rev-list "origin/${baseBranch}..upstream/${baseBranch}" 2>$null | Measure-Object -Line).Lines
            if ($behind -eq 0) { Write-Host "already up to date with upstream/$baseBranch"; exit 0 }
            $stashed = $false
            if ($branch -ne $baseBranch -and @(git -C $repo status --porcelain 2>$null | Where-Object { $_ }).Count -gt 0) {
                $stashOut = git -C $repo stash push -m 'gitbox-fork-sync' 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "stash failed"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $stashOut | ForEach-Object { Write-Host "  $_" } }
                    exit 1
                }
                $stashed = $true
            }
            if ($branch -ne $baseBranch) {
                $coOut = git -C $repo checkout $baseBranch 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "checkout $baseBranch failed"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $coOut | ForEach-Object { Write-Host "  $_" } }
                    if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                    exit 1
                }
            }
            $mergeOut = git -C $repo merge --ff-only "upstream/$baseBranch" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "fork-sync failed: $baseBranch cannot fast-forward to upstream/$baseBranch"
                Write-Host "  hint: $baseBranch has commits not in upstream -- rebase manually then retry"
                if ($VerbosePreference -ne 'SilentlyContinue') { $mergeOut | ForEach-Object { Write-Host "  $_" } }
                if ($branch -ne $baseBranch) { git -C $repo checkout $branch 2>$null | Out-Null }
                if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                exit 1
            }
            $pushOut = git -C $repo push origin $baseBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "push origin/$baseBranch failed"
                if ($VerbosePreference -ne 'SilentlyContinue') { $pushOut | ForEach-Object { Write-Host "  $_" } }
                if ($branch -ne $baseBranch) { git -C $repo checkout $branch 2>$null | Out-Null }
                if ($stashed) { git -C $repo stash pop 2>$null | Out-Null }
                exit 1
            }
            if ($branch -ne $baseBranch) { git -C $repo checkout $branch 2>$null | Out-Null }
            if ($stashed) {
                $popOut = git -C $repo stash pop 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "warning: stash pop failed -- run: git stash pop"
                    if ($VerbosePreference -ne 'SilentlyContinue') { $popOut | ForEach-Object { Write-Host "  $_" } }
                }
            }
            Write-Host "synced origin/$baseBranch |+$behind from upstream/$baseBranch |pushed fork"
        }
    }
}
