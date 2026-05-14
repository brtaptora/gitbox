# gitbox

PowerShell git workflow suite. Works standalone (call `.ps1` files directly) or as a module (`Import-Module .\gitbox.psd1`).

## Quick start

Each flag maps to one operation. Run them individually or stack them in a single call:

```powershell
# create a feature branch
gitbox b "feat/my-feature"

# commit all changes and push
gitbox c "fix the thing"

# open a PR
gitbox o "Fix the thing"

# check CI
gitbox x

# merge, delete branch, land on next wip branch
gitbox m
```

Stack multiple flags in one call. Args are consumed left-to-right:

```powershell
# commit then open PR (two args: one for c, one for o)
gitbox co "fix the thing" "Fix the thing"
```

Named workflows are pre-set flag sequences:

```powershell
# ship = c + x + m: commit, check CI, merge
gitbox ship "all done"

# full = c + u + o + x + m: commit, push, open PR, check CI, merge
gitbox full "all done" "Fix the thing"
```

### Complete feature branch cycle

Starting from the base branch:

```powershell
gitbox b "feat/my-feature"   # create feature branch

# ... make changes ...

gitbox c "fix the thing"     # stage all, commit, push
gitbox o "Fix the thing"     # open PR
gitbox x                     # check CI
gitbox m                     # merge, delete branch, land on wip
```

Steps 2–5 compress once a PR is open:

```powershell
gitbox ship "fix the thing"              # c + x + m
```

Or the full journey in one call when there is no PR yet:

```powershell
gitbox full "fix the thing" "Fix the thing"   # c + u + o + x + m
```

The orchestrator section below covers all flags, stacking rules, and skip behavior in detail.

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
  "DefaultBranch": "main",
  "MergeStrategy": "squash",
  "Editor": true
}
```

| Field | Default | Purpose |
|-------|---------|---------|
| `BaseBranch` | value of `DefaultBranch` | Branch that feature branches are created from and PRs target |
| `DefaultBranch` | result of `gh repo view --json defaultBranchRef` | Release / trunk branch; fallback when `BaseBranch` is absent |
| `MergeStrategy` | `merge` | Merge strategy for `m`: `merge`, `squash`, or `rebase`. Overridden per call with `-Squash` / `-Rebase`. |
| `Editor` | `false` | When `true`, `c` and `o` open `$GIT_EDITOR` when called without an arg instead of prompting with `Read-Host` |

When no config file exists all fields fall back to defaults. Omit the file entirely for single-trunk repos where base and default are the same branch.

## Install as module

```powershell
Import-Module .\gitbox.psd1
```

Each script has a `g-` alias and a verb-noun function name. Either form works after import.

## Orchestrator

`gitbox.ps1` sequences flags into a pipeline. Lowercase flags are mutating and run in a fixed canonical order. Uppercase flags are diagnostic and run after all mutating steps. The pipeline halts immediately on the first failure.

```powershell
gitbox <flags|workflow> [arg ...] [-AllowWip]
```

### Flags

| Flag | What it does | Needs arg |
|------|-------------|-----------|
| `b` | Create branch from base | branch name |
| `r` | Rename current branch | branch name |
| `s` | Fetch and rebase onto base | — |
| `c` | Stage all, commit, push | commit message (optional, prompts if absent) |
| `v` | Revert a commit | ref (optional, defaults to HEAD) |
| `u` | Push unpushed commits | — |
| `o` | Open PR against base branch | PR title (optional, prompts or uses `--fill` if absent) |
| `x` | Report CI check results | — |
| `m` | Merge PR, delete branch, create next branch | branch name (optional) |
| `z` | Release: open PR to default branch, check CI, merge, tag, push tag | version (optional) |
| `H` | Unified health report | — |
| `Q` | One-line repo status | — |
| `L` | Log commits ahead of base | — |
| `D` | Diff stats for staged and unstaged changes | — |
| `P` | PR detail: title, state, reviews, checks | — |
| `S` | Emit state hash and recommended action | — |
| `B` | List unhandled workflow states | — |
| `C` | Score script coverage | — |
| `W` | Print workflow registry | — |
| `O` | Print optimization scores | — |
| `X` | Fetch CI run logs grouped by step | — |

Arguments are positional and consumed left-to-right by flags that need one.

### Named workflows

| Name | Flags | Use when |
|------|-------|---------|
| `start` | `b` | Beginning a new ticket from the base branch |
| `rename` | `r` | Promoting a wip branch to a feature branch before opening a PR |
| `sync` | `s` | Branch is behind base and needs to catch up before a PR |
| `commit` | `c` | Saving incremental progress on an in-progress PR |
| `push` | `u` | Pushing commits made outside gitbox |
| `pr` | `o` | Opening a PR on an already-pushed branch |
| `checks` | `x` | Inspecting CI status mid-review without merging |
| `merge` | `m` | Merging an approved PR and rotating to the next branch |
| `revert` | `v` | Undoing a commit. Pair with `push` as `gitbox vu` to also push the revert. |
| `draft` | `rcuo` | Starting a new feature from a wip branch. `r` is skipped automatically on feature branches. |
| `land` | `cxm` | Final commit on a branch with an open PR. CI is verified before merge. |
| `ship` | `xm` | Merging a clean, already-committed branch; CI must pass |
| `full` | `cuoxm` | One-shot first pass on a new feature: every step from commit through merge |
| `release` | `z` | Promoting develop to main with a version tag |
| `health` | `H` | Auditing script coverage and gap analysis |

### Workflow-prefix compounds

A workflow name can be used as a prefix: the orchestrator expands the workflow, then appends the remaining characters as raw flags. Names are matched longest-first so no short name shadows a longer one.

```powershell
gitbox mX        # m + X: merge and view CI logs ('m' is a raw flag, not a workflow prefix)
gitbox shipX     # ship → cxm, append X → cxmX: commit, check CI, merge, view CI logs
gitbox fullX     # full → cuoxm, append X → cuoxmX: full workflow then view CI logs
gitbox prX       # pr → o, append X → oX: open PR then view CI logs
```

### Skip behavior

Before executing mutating flags the orchestrator scans the current matrix state and skips any flag whose work is already done:

| Flag | Skipped when |
|------|-------------|
| `b` | Already on a feature branch |
| `r` | Already on a feature branch AND part of a compound sequence (standalone `gitbox r` always runs) |
| `c` | Nothing to commit or stage |
| `u` | All commits already pushed |
| `o` | PR already open or approved |
| `x` | No failing checks |

A skipped flag prints `skip <flag> (<name>): <reason>` and the pipeline continues to the next flag.

### Guards

The `c` flag (and any workflow containing `c`) detects when the current branch is an unnamed `wip/` branch and pauses to prompt for a new name. Enter a name to rename the branch and continue. Press Enter to proceed on the wip branch as-is.

The `draft` workflow handles this automatically: pass the feature branch name as the first arg and `r` runs before `c`, so the rename happens without a prompt. On a feature branch `r` is skipped and the remaining args flow straight to `c` and `o`.

To skip the prompt entirely and always commit on the wip branch, pass `-AllowWip`:

```powershell
gitbox ship "all done" -AllowWip
```

### Examples

```powershell
# create a branch
gitbox b "feat/my-feature"

# commit and push
gitbox c "fix the thing"

# commit, check CI, merge
gitbox ship "all done"

# commit, check CI, merge, then view CI logs
gitbox shipX "all done"

# merge and view CI logs
gitbox mX

# commit and open PR in one step (two args: commit message then PR title)
gitbox co "fix the thing" "Fix the thing"

# show workflow registry
gitbox W

# view CI run logs for the current branch (or base branch if no runs on current)
gitbox X
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
| `g-open-pr` | `New-GitPullRequest` | PR title via pipeline (`-Body` optional) | Open PR against base branch; exits 0 with existing PR URL if one is already open |
| `g-pr-checks` | `Get-GitPullRequestChecks` | none | Summarise check results for current branch PR |
| `g-merge-rotate` | `Invoke-GitMergeRotate` | branch name (optional, via pipeline) | Merge PR, delete branch, create next branch (defaults to `wip/MMDD-HHmm`) |

### Status and diagnostics

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-status` | `Get-GitStatus` | none (`-d` for PR body) | One-line repo status |
| `g-matrix-scan` | `Get-GitMatrix` | none | Emit state hash and recommended next action |
| `g-matrix-resolve` | `Resolve-GitMatrix` | state hash via pipeline | Resolve hash to recommended next action |
| `g-backlog` | `Get-GitBacklog` | none | List all unhandled workflow states |
| `g-capabilities` | `Get-GitCapabilities` | none | Score script coverage against known gap requirements |
| `g-run-logs` | `Get-GitRunLogs` | none | Fetch most recent CI run logs grouped by step; falls back to base branch when current branch has no runs |

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

1. Class `B` (on base branch): create a feature branch
2. Class `W` (on wip branch): rename to a feature branch
3. Class `F`:
   1. Secret files present (`sN`): block until secrets removed
   2. Behind base (`b>0`): rebase first
   3. Checks failed (`PRX`): fix CI
   4. PR open or approved (`PRO` / `PRA`): commit if dirty, then merge-rotate
   5. Draft PR (`PRD`): commit if dirty, else mark ready
   6. No PR (`PR-`): commit if dirty. Push and open PR if pushed ahead. Push first if unpushed ahead. Nothing to do if clean and not ahead.

Priority order encodes a dependency graph: you cannot safely open a PR while behind, and you cannot merge while checks are failing. Each rule removes the precondition that blocks the next step.

### Backlog sweep (`g-backlog`)

`g-backlog` discovers gaps by running `g-matrix-resolve` against every valid state combination rather than parsing source text. Using two representative values per numeric dimension (0 and 1) the enumeration covers:

```
|S| = |C| × |D| × |A| × |B| × |P| × |R|
    =   3  ×   3  ×  2  ×  2  ×  2  ×  5
    = 360 combinations
```

Any combination that produces a `GAP[UNCLASSIFIED]` line is an unhandled state; `g-backlog` exits non-zero and CI fails. Classified gaps are suppressed automatically when the registered capabilities cover them (see below). The workflow coverage table is always printed regardless of gap count.

Workflow W covers gap dimension G when the union of capability sets across all flags in W is a superset of G's requirements:

```
covers(W, G) = true  iff  ⋃_{f ∈ flags(W)} caps(f)  ⊇  requirements(G)
```

`g-matrix-resolve` applies the same check at runtime: before emitting `GAP[dim]` it tests whether the union of all registered `$FlagCapabilities` satisfies `$GapRequirements[dim]`. If coverage exists the label is suppressed. Adding a new script with the right capabilities automatically closes the gap with no edits to `g-matrix-resolve` required.

### Capabilities scan (`g-capabilities`)

`g-capabilities` reads every `g-*.ps1` script line by line, matches each non-comment line against the regex patterns in `$CapabilityPatterns`, and records which git/gh operations each script can perform.

Gap coverage score for a script S against gap dimension G:

```
score(S, G) = |caps(S) ∩ requirements(G)| / |requirements(G)|
```

A score of 1.0 means the script alone satisfies all requirements for that gap. Scores below 1.0 indicate partial coverage; the missing capabilities are shown inline.

The optimization score (`gitbox O`) measures capability density: how much work a script does relative to its size:

```
density(S) = |caps(S)| / non-blank-non-comment-lines(S)
```

Scripts with low density and non-zero capabilities are consolidation candidates.

When a script calls another `g-*.ps1` via `& (Join-Path $PSScriptRoot '...')`, the referenced script's capabilities are inherited recursively. A cycle guard prevents infinite loops. Composite scripts like `g-release.ps1` therefore automatically surface the capabilities of every script they invoke, with no manual bookkeeping.

Known limitation: splatted calls (`gh @args`) are not resolved by static analysis. Scripts that build argument arrays and splat them will show no capabilities in `gitbox W`. Prefer direct invocations (`gh pr create ...`) so the scanner can detect them.
