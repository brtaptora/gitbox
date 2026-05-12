# gitbox

PowerShell git workflow suite. Works standalone (call `.ps1` files directly) or as a module (`Import-Module .\gitbox.psd1`).

## Prerequisites

| Requirement | Notes |
|---|---|
| PowerShell 5.1+ | Included in Windows 10+; available on macOS/Linux via `pwsh` |
| git | Must be on PATH |
| [GitHub CLI (gh)](https://cli.github.com/) | v2.20+ recommended (required for `--json` flag on `gh pr checks`) |
| gh authentication | Run `gh auth login` before first use; requires `repo` scope |
| GitHub remote named `origin` | PR and merge commands require the remote to be a GitHub repository |

Verify setup:

```powershell
git --version
gh auth status
```

## Configuration

Place `.gitbox.json` in the repo root to declare the branch topology for that repo:

```json
{
  "BaseBranch": "develop",
  "DefaultBranch": "main"
}
```

| Field | Default | Purpose |
|-------|---------|---------|
| `BaseBranch` | value of `DefaultBranch` | Branch that feature branches are created from and PRs target |
| `DefaultBranch` | result of `gh repo view --json defaultBranchRef` | Release / trunk branch; fallback when `BaseBranch` is absent |

When no config file exists both fields fall back to `gh repo view`. Omit the file entirely for single-trunk repos where base and default are the same branch.

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
| `u` | Push unpushed commits | — |
| `o` | Open PR against default branch | PR title |
| `x` | Report CI check results | — |
| `m` | Merge PR, delete branch, create next branch | branch name (optional) |
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
| `push` | `u` | Push |
| `pr` | `o` | Open PR |
| `checks` | `x` | Check CI |
| `merge` | `m` | Merge and rotate (to `wip/` or named branch) |
| `ship` | `cxm` | Commit, check CI, merge |
| `full` | `cuoxm` | Commit, push, open PR, check CI, merge |

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

## Matrix internals

`g-matrix-scan`, `g-matrix-resolve`, `g-backlog`, and `g-capabilities` operate on a compact state hash that encodes the full repo situation in one string.

### State hash format

```
<class>|<dirty>|a<N>|b<N>|<push>|<PR>
```

Example: `F|d3|a2|b0|U|PR-`

| Segment | Values | Meaning |
|---------|--------|---------|
| `class` | `B` `F` `W` | Branch class: **B**ase, **F**eature, **W**ip |
| `dirty` | `c` `dN` `sN` | Working tree: **c**lean, **d**irty N files, **s**ecret-pattern match N files |
| `a<N>` | `a0` `a1` … | Commits ahead of `origin/<base>` |
| `b<N>` | `b0` `b1` … | Commits behind `origin/<base>` |
| `push` | `P` `U` | Remote branch: **P**ushed (up to date), **U**npushed (ahead or no remote ref) |
| `PR` | `PR-` `PRD` `PRO` `PRX` `PRA` | PR state: none, **D**raft, **O**pen, checks failed (X), **A**pproved |

The full state space is the Cartesian product of all six dimensions:

```
S = C × D × A × B × P × R
  = {B,F,W} × {c,dN,sN} × {a0,a1,…} × {b0,b1,…} × {P,U} × {PR-,PRD,PRO,PRX,PRA}
```

### Resolve priority (`g-matrix-resolve`)

`g-matrix-resolve` accepts a hash and returns the recommended next action. Rules fire top-to-bottom; the first match wins:

1. Class `B` (on base branch) — prompt to create a feature branch
2. Class `W` (on wip branch) — prompt to rename to a feature branch
3. Class `F`:
   1. Secret files present (`sN`) — block until secrets removed
   2. Behind base (`b>0`) — rebase first
   3. Checks failed (`PRX`) — fix CI
   4. PR open or approved (`PRO` / `PRA`) — commit if dirty, then merge-rotate
   5. Draft PR (`PRD`) — commit if dirty, else mark ready
   6. No PR (`PR-`) — commit if dirty; push+open-PR if pushed ahead; push first if unpushed ahead; nothing to do if clean and not ahead

Priority order encodes a dependency graph: you cannot safely open a PR while behind, and you cannot merge while checks are failing. Each rule removes the precondition that blocks the next step.

### Backlog sweep (`g-backlog`)

`g-backlog` discovers gaps by running `g-matrix-resolve` against every valid state combination rather than parsing source text. Using two representative values per numeric dimension (0 and 1) the enumeration covers:

```
|S| = |C| × |D| × |A| × |B| × |P| × |R|
    =   3  ×   3  ×  2  ×  2  ×  2  ×  5
    = 360 combinations
```

Any combination that produces a `GAP[UNCLASSIFIED]` line is an unhandled state. The script also prints workflow coverage: for each named workflow it computes which gap dimensions its flag sequence satisfies.

Workflow W covers gap dimension G when the union of capability sets across all flags in W is a superset of G's requirements:

```
covers(W, G) = true  iff  ⋃_{f ∈ flags(W)} caps(f)  ⊇  requirements(G)
```

### Capabilities scan (`g-capabilities`)

`g-capabilities` reads every `g-*.ps1` script line by line, matches each non-comment line against the regex patterns in `$CapabilityPatterns`, and records which git/gh operations each script can perform.

Gap coverage score for a script S against gap dimension G:

```
score(S, G) = |caps(S) ∩ requirements(G)| / |requirements(G)|
```

A score of 1.0 means the script alone satisfies all requirements for that gap. Scores below 1.0 indicate partial coverage; the missing capabilities are shown inline.

The optimization score (`gitbox O`) measures capability density — how much work a script does relative to its size:

```
density(S) = |caps(S)| / non-blank-non-comment-lines(S)
```

Scripts with low density and non-zero capabilities are consolidation candidates.

Known limitation: splatted calls (`gh @args`) are not resolved by static analysis. Scripts that build argument arrays and splat them will show no capabilities in `gitbox W`. Prefer direct invocations (`gh pr create ...`) so the scanner can detect them.

## Error recovery

### Rebase conflict (g-branch-sync)

`g-branch-sync` aborts automatically on conflict and restores the working tree. Resolve the conflict manually then continue:

```powershell
# after g-branch-sync reports "rebase conflict"
git status                   # see conflicted files
# edit files to resolve conflicts
git add <resolved-files>
git rebase --continue
```

### Secret guard block (g-commit-push)

If `g-commit-push` reports `secret guard: blocked`, the listed files match a sensitive filename pattern. Remove or rename them before retrying:

```powershell
# after secret guard block
git status                   # confirm which files are present
# move or delete the flagged files
"your commit message" | g-commit-push
```

### Merge failure (g-merge-rotate)

If `g-merge-rotate` reports `merge failed`, the PR was not merged and the branch is preserved. Check the failure reason and retry:

```powershell
# after merge failed
g-pr-checks                  # inspect failing CI checks
gh pr view                   # read any merge blockers (review required, conflicts)
# resolve the blocker, then:
"next-branch-name" | g-merge-rotate
```

### gh authentication error

If any script reports `authentication failed` or `permission denied` on a `gh` call:

```powershell
gh auth login                # re-authenticate
gh auth status               # verify scope includes repo
```

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

# merge, clean up, and land on next feature branch in one step
"feat/next-thing" | g-merge-rotate
```
