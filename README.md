# gitbox

PowerShell git workflow suite. Works standalone (call `.ps1` files directly) or as a module (`Import-Module .\gitbox.psd1`).

## Install as module

```powershell
Import-Module .\gitbox.psd1
```

Each script has a `g-` alias and a verb-noun function name. Either form works after import.

## Orchestrator

`gitbox.ps1` sequences flags into a pipeline. Lowercase flags are mutating and run in a fixed canonical order; uppercase flags are diagnostic and run after all mutating steps. The pipeline halts immediately on the first failure.

```powershell
gitbox <flags|workflow> [arg ...]
```

### Flags

| Flag | What it does | Needs arg |
|------|-------------|-----------|
| `b` | Create branch from base | branch name |
| `r` | Rename current branch | branch name |
| `s` | Fetch and rebase onto base | — |
| `c` | Stage all, commit, push | commit message |
| `p` | Push unpushed commits | — |
| `o` | Open PR against default branch | PR title |
| `x` | Report CI check results | — |
| `m` | Merge PR, delete branch, create `wip/` | — |
| `Q` | One-line repo status | — |
| `S` | Emit state hash and recommended action | — |
| `B` | List unhandled workflow states | — |
| `C` | Score script coverage | — |
| `W` | Print workflow registry | — |
| `O` | Print optimization scores | — |

Arguments are positional and consumed left-to-right by flags that need one.

### Named workflows

| Name | Flags | What it does |
|------|-------|-------------|
| `start` | `b` | Create branch |
| `rename` | `r` | Rename branch |
| `sync` | `s` | Rebase onto base |
| `commit` | `c` | Stage, commit, push |
| `push` | `p` | Push |
| `pr` | `o` | Open PR |
| `checks` | `x` | Check CI |
| `merge` | `m` | Merge and rotate |
| `ship` | `cxm` | Commit, check CI, merge |
| `full` | `cpom` | Commit, push, open PR, merge |

### Examples

```powershell
# create a branch
gitbox b "feat/my-feature"

# commit and push
gitbox c "fix the thing"

# commit, check CI, merge
gitbox ship "all done"

# commit and open PR in one step (two args: commit message then PR title)
gitbox co "fix the thing" "Fix the thing"

# show workflow registry
gitbox W
```

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
