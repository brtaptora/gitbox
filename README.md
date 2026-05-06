# gitbox

PowerShell git workflow suite. Works standalone (call `.ps1` files directly) or as a module (`Import-Module .\gitbox.psd1`).

## Install as module

```powershell
Import-Module .\gitbox.psd1
```

Each script has a `g-` alias and a verb-noun function name. Either form works after import.

## Commands

### Branch

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-branch-create` | `New-GitBranch` | branch name via pipeline | Pull base, create and checkout feature branch |
| `g-branch-rename` | `Rename-GitBranch` | branch name via pipeline | Rename current branch locally and on remote |
| `g-branch-sync` | `Sync-GitBranch` | none | Fetch base and rebase current branch onto it |

### Commit and push

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-commit-push` | `Push-GitCommit` | commit message via pipeline | Secret guard, stage all, commit, push |
| `g-push` | `Push-GitBranch` | none | Push unpushed commits without staging |

### Pull request

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-open-pr` | `New-GitPullRequest` | PR title via pipeline (`-Body` optional) | Open PR against default branch |
| `g-pr-checks` | `Get-GitPullRequestChecks` | none | Summarise check results for current branch PR |
| `g-merge-rotate` | `Invoke-GitMergeRotate` | none | Merge PR, delete branch, create new `wip/` branch |

### Status and diagnostics

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-status` | `Get-GitStatus` | none (`-d` for PR body) | One-line repo status |
| `g-matrix-scan` | `Get-GitMatrix` | none | Emit state hash and recommended next action |
| `g-matrix-resolve` | `Resolve-GitMatrix` | state hash via pipeline | Resolve hash to recommended next action |
| `g-backlog` | `Get-GitBacklog` | none | List all unhandled workflow states |
| `g-capabilities` | `Get-GitCapabilities` | none | Score script coverage against known gap requirements |

## Typical workflow

```powershell
# start work
"feat/my-feature" | g-branch-create

# commit and push changes
"fix the thing" | g-commit-push

# open PR
"Fix the thing" | g-open-pr -Body "Closes #42"

# check CI
g-pr-checks

# merge, clean up, start next branch
g-merge-rotate
"feat/next-thing" | g-branch-rename
```
