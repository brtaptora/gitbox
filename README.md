# gitbox

PowerShell git workflow suite. Install as a module to access the `gitbox` orchestrator and all `g-` aliases.

## Quick Start

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

Steps 2-5 compress once a PR is open:

```powershell
gitbox ship "fix the thing"              # c + x + m
```

Or the full journey in one call when there is no PR yet:

```powershell
gitbox full "fix the thing" "Fix the thing"   # c + u + o + x + m
```

The orchestrator section covers all flags, stacking rules, and skip behavior in detail.

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

## Install As Module

**From PSGallery (recommended):**

```powershell
Install-Module gitbox
```

Then add to your `$PROFILE` so it loads automatically each session:

```powershell
Add-Content $PROFILE "`nImport-Module gitbox"
```

To update from PSGallery:

```powershell
Update-Module -Name gitbox
```

**From source:**

```powershell
Import-Module .\gitbox.psd1
```

Each operation has a `g-` alias and a verb-noun function name; all are available after import. The `gitbox` orchestrator (and its `gb` alias) sequences them into pipelines and is the recommended entry point for all workflows.

## Configuration

Place `.gitbox.json` in the repo root to declare the branch topology for that repo:

```json
{
  "BaseBranch": "develop",
  "DefaultBranch": "main",
  "MergeStrategy": "squash",
  "Editor": true,
  "Upstream": "owner/repo",
  "NeverStage": ["*.env", "secrets/", "*.log"]
}
```

| Field | Default | Purpose |
|-------|---------|---------|
| `BaseBranch` | value of `DefaultBranch` | Branch that feature branches are created from and PRs target |
| `DefaultBranch` | result of `gh repo view --json defaultBranchRef` | Release / trunk branch; fallback when `BaseBranch` is absent |
| `MergeStrategy` | `merge` | Merge strategy for `m`: `merge`, `squash`, or `rebase`. Overridden per call with `-Squash` / `-Rebase`. |
| `Editor` | `false` | When `true`, `c` and `o` open `$GIT_EDITOR` when called without an arg instead of prompting with `Read-Host` |
| `Upstream` | `null` | When set, enables fork mode. Value is `owner/repo` of the upstream (original) repository. |
| `NeverStage` | `[]` | Glob patterns always excluded from staging on every `c` run. Equivalent to passing `-Exclude` every time. Applied after `git add -A`; use for files tracked by git but never meant to be committed (credentials, generated logs, local overrides). |

When no config file exists all fields fall back to defaults. Omit the file entirely for single-trunk repos where base and default are the same branch.

## Fork Workflow

Fork mode is for contributors who do not have direct push access to a repository. All commits land on a personal fork. PRs target the upstream repo only when explicitly requested.

### Setup

**From scratch** (no local clone yet):

```powershell
gitbox fork owner/repo
# forks to your account, clones the fork, writes .gitbox.json
# then: cd <reponame>
```

**Already cloned the upstream**:

```powershell
cd the-repo
gitbox fork owner/repo
# forks to your account, reconfigures remotes, writes .gitbox.json
```

Both paths write `.gitbox.json` with `Upstream` set to `owner/repo` and `BaseBranch` set to `develop` if that branch exists on the upstream, or the upstream's default branch otherwise.

After setup the remote layout is:

| Remote | Points to |
|--------|-----------|
| `origin` | your fork |
| `upstream` | original repo |

### Working in Fork Mode

The standard workflow is unchanged. `gitbox c`, `gitbox u`, and all compounds push to `origin` (your fork).

```powershell
gitbox b "feat/my-fix"
gitbox c "fix the thing"     # pushes to your fork
gitbox o "Fix the thing"     # PR opens on your fork against the fork's base branch
```

### Contributing to Upstream

When work is ready to propose to the upstream maintainers, pass `-Upstream` to `o`:

```powershell
gitbox o "Fix the thing" -Upstream
# opens a cross-fork PR: upstream-owner/repo ← yourfork:feat/my-fix
```

Without `-Upstream`, `gitbox o` always targets the fork. This prevents accidental upstream PRs.

### Keeping Your Fork Up to Date

When the upstream repository advances, sync its base branch into your fork before starting or continuing work:

```powershell
gitbox sync-fork    # or: gitbox e
# fetches upstream/<base>, merges into your local base, pushes to origin
```

This is equivalent to `git fetch upstream && git merge --ff-only upstream/<base> && git push origin <base>`. If your working tree is dirty or you are on a feature branch, `e` stashes, checks out base, syncs, pushes, returns to your branch, and pops the stash.

To sync the upstream and then immediately rebase your feature branch on top:

```powershell
gitbox es    # e (sync upstream) + s (rebase current branch onto base)
```

`e` requires `Upstream` in `.gitbox.json`. If the upstream remote does not exist locally, `e` exits with an error and a setup hint.

### Fork Guard

If `Upstream` is set in `.gitbox.json` and `origin` is misconfigured to point at the upstream repo, `gitbox c` and `gitbox u` will refuse to push:

```
fork guard: origin points to upstream 'owner/repo' -- reconfigure origin to your fork
```

Correct by setting `origin` to your fork's URL and retrying.

## Orchestrator

`gitbox.ps1` sequences flags into a pipeline. Lowercase flags are mutating and run in a fixed canonical order. Uppercase flags are diagnostic and run after all mutating steps. The pipeline halts immediately on the first failure.

```powershell
gitbox <flags|workflow> [arg ...] [-AllowWip]
gb     <flags|workflow> [arg ...] [-AllowWip]
```

`gb` is an alias for `gitbox`. Both commands are equivalent in all contexts.

### Built-in Commands

| Command | Output |
|---------|--------|
| `gitbox` or `gitbox --help` | Full flag and workflow reference |
| `gitbox --version` | Version string read from the module manifest |
| `gitbox init` | Scaffold `.gitbox.json` interactively; prompts for base branch, merge strategy, editor setting, and post-merge destination |

### Tab Completion

When loaded as a module, gitbox registers an argument completer for both `gitbox` and `gb`. Pressing Tab after either command offers all flags and named workflows. The completer runs a fast git-only state scan and surfaces the matrix-recommended next action as the first suggestion.

```powershell
gitbox <Tab>     # → ship (or whatever the matrix says is next), then all workflows and flags
gb lan<Tab>      # → land
```

### Operational Flags
<details>
<summary>Click to expand</summary>

| Flag | Operation | Argument |
|------|-------------|-----------|
| `f` | Fork upstream, clone, and configure gitbox | `owner/repo` (optional; detected from remotes if omitted) |
| `b` | Create branch from base | branch name |
| `r` | Rename current branch | branch name |
| `e` | Fetch upstream and fast-forward fork's base branch; requires `Upstream` in `.gitbox.json` | — |
| `s` | Fetch and rebase onto base | — |
| `c` | Stage all, commit, push | commit message (optional, prompts if absent) |
| `u` | Push unpushed commits | — |
| `o` | Open PR against base branch. In fork mode, targets the fork by default; pass `-Upstream` to open a cross-fork PR to the upstream repo. | PR title (optional, prompts or uses `--fill` if absent) |
| `m` | Merge PR, delete branch, create next branch | branch name (optional) |
</details>

### Additional Flags
<details>
<summary>Click to expand</summary>

| Flag | Operation | Argument |
|------|-------------|-----------|
| `v` | Revert a commit | ref (optional, defaults to HEAD) |
| `x` | Report CI check results | — |
| `g` | Checkout base branch and pull | — |
| `k` | Checkout any named branch with stash-and-pop; no-op if already on that branch | branch name |
| `n` | Merge the full stacked PR chain bottom-to-top, checking CI between each merge | — |
| `z` | Tag and push; on two-branch repos (base ≠ default), opens a PR to default branch, checks CI, and merges first. On single-trunk repos (base = default), tags HEAD directly. Omitting version auto-increments the patch (e.g. `v1.0.0` → `v1.0.1`). Pass `patch`, `minor`, or `major` to bump that segment. Pass an explicit string to pin the version. No existing tags starts at `v0.1.0`. | version, bump keyword, or omit |
</details>

### Diagnostic Flags
<details>
<summary>Click to expand</summary>

| Flag | Operation |
|------|-------------|
| `Q` | One-line repo status |
| `L` | Log commits ahead of base |
| `D` | Diff stats for staged and unstaged changes |
| `P` | PR detail: title, state, reviews, checks |
| `S` | Emit state hash and recommended action |
| `B` | List unhandled workflow states |
| `C` | Score script coverage |
| `W` | Print workflow registry |
| `O` | Print optimization scores |
| `X` | Fetch CI run logs grouped by step |
| `H` | Unified gitbox health report |
| `T` | Stack topology tree: show stacked PR chain with CI status |
</details>

Arguments are positional and consumed left to right by flags that need one.

### Named Compound Workflows
<details>
<summary>Click to expand</summary>

| Alias | Flags | Use Case |
|------|-------|---------|
| `promote` | `rcuo` | Promote a wip branch to a feature branch with a PR. `r` is skipped automatically on feature branches. |
| `land` | `cxm` | Final commit on a branch with an open PR. CI is verified before merge. |
| `ship` | `xm` | Merging a clean, already-committed branch. CI must pass |
| `full` | `cuoxm` | One-shot first pass on a new feature: every step from commit through merge |
</details>

### Named Single-Flag Workflows
<details>
<summary>Click to expand</summary>

| Alias | Flags | Use Case |
|------|-------|---------|
| `fork` | `f` | Setting up a fork-based contribution workflow |
| `start` | `b` | Beginning a new ticket from the base branch |
| `rename` | `r` | Promoting a wip branch to a feature branch before opening a PR |
| `sync` | `s` | Branch is behind base and needs to catch up before a PR |
| `commit` | `c` | Saving incremental progress on an in-progress PR |
| `push` | `u` | Pushing commits made outside gitbox |
| `pr` | `o` | Opening a PR on an already-pushed branch |
| `checks` | `x` | Inspecting CI status mid-review without merging |
| `merge` | `m` | Merging an approved PR and rotating to the next branch |
| `release` | `z` | Promoting develop to main with a version tag |
| `revert` | `v` | Undoing a commit. Pair with `push` as `gitbox vu` to also push the revert. |
| `base` | `g` | Return to base branch after merge or before release |
| `checkout` | `k` | Switch to any named branch with stash-and-pop |
| `unstack` | `n` | Merge the full stacked PR chain bottom-to-top |
| `stack` | `T` | Print the stacked PR chain for the current branch |
| `sync-fork` | `e` | Fetch upstream and fast-forward fork's base branch; requires `Upstream` in `.gitbox.json` |
| `health` | `H` | Auditing script coverage and gap analysis |
</details>

### Workflow-Prefix Compounds

A workflow name can be used as a prefix. The orchestrator expands the workflow, then appends the remaining characters as raw flags. Names are matched longest first so no short name prevents a longer one from being parsed.

#### Examples
```powershell
gitbox mX        # m + X: merge and view CI logs ('m' is a raw flag, not a workflow prefix)
gitbox shipX     # ship → cxm, append X → cxmX: commit, check CI, merge, view CI logs
gitbox fullX     # full → cuoxm, append X → cuoxmX: full workflow then view CI logs
gitbox prX       # pr → o, append X → oX: open PR then view CI logs
```

### Skip Behavior

Before executing mutating flags the orchestrator scans the current matrix state and skips any flag whose work is already done:

| Flag | Skipped when |
|------|-------------|
| `b` | Already on a feature branch (unless `-Stack` is passed) |
| `r` | Already on a feature branch AND part of a compound sequence (standalone `gitbox r` always runs) |
| `c` | Nothing to commit or stage |
| `u` | All commits already pushed |
| `o` | PR already open or approved |
| `x` | No failing checks |
| `g` | Already on base branch |

A skipped flag prints `skip <flag> (<name>): <reason>` and the pipeline continues to the next flag.

### Guards

The `c` flag (and any workflow containing `c`) detects when the current branch is an unnamed `wip/` branch and pauses to prompt for a new name. Enter a name to rename the branch and continue. Press Enter to proceed on the wip branch as-is.

The `promote` workflow handles this automatically: pass the feature branch name as the first arg and `r` runs before `c`, so the rename happens without a prompt. On a feature branch `r` is skipped and the remaining args flow straight to `c` and `o`.

To skip the prompt entirely and always commit on the wip branch, pass `-AllowWip`:

```powershell
gitbox ship "all done" -AllowWip
```

### Stacked PRs

To build a chain of PRs where each one targets the previous feature branch instead of base, pass `-Stack` to `b`:

```powershell
gitbox b "feat/A"             # from base (normal)
gitbox c "add part A"
gitbox b "feat/B" -Stack      # from feat/A
gitbox c "add part B"
gitbox b "feat/C" -Stack      # from feat/B
```

Each branch then gets its own PR: `feat/A` → base, `feat/B` → `feat/A`, `feat/C` → `feat/B`.

When `gitbox m` merges `feat/A`, it detects the downstream PR (`feat/B` → `feat/A`) and automatically:
1. Rebases `feat/B` onto base (`--onto`)
2. Force-pushes `feat/B`
3. Retargets the PR to base

The merge then proceeds and `feat/A` is deleted safely. `feat/B`'s PR now targets base. `feat/C`'s PR still targets `feat/B` and will be handled when `feat/B` is merged.

If the rebase produces a conflict, the merge is aborted. Resolve with `git rebase --continue`, push, then retry `gitbox m`.

Squash merge strategy can produce conflicts during stack rebase because individual commits from the merged branch are not in base history. `MergeStrategy: merge` in `.gitbox.json` avoids this.

### Additional Examples

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

## Module API

These are the individual commands exported by the module. All are available as `g-` aliases and verb-noun function names after import. For most workflows, prefer the `gitbox` orchestrator — these are useful when you need a single step in a script or pipeline.

### Branch
<details>
<summary>Click to expand</summary>

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-branch-create` | `New-GitBranch` | branch name via pipeline | Pull base, create and checkout feature branch |
| `g-branch-rename` | `Rename-GitBranch` | branch name via pipeline | Rename current branch locally and on remote |
| `g-branch-sync` | `Sync-GitBranch` | none | Fetch base and rebase current branch onto it |
| `g-branch-checkout` | `Switch-GitBranch` | branch name via pipeline | Stash, checkout named branch, pop stash; no-op if already on that branch |
| `g-branch-base` | `Switch-GitBaseBranch` | none | Stash, checkout base branch, pull, pop stash |
| `g-fork-sync` | `Sync-GitFork` | none | Fetch upstream base, fast-forward fork's base, push to origin |
</details>

### Commit and Push
<details>
<summary>Click to expand</summary>

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-commit-push` | `Push-GitCommit` | commit message via pipeline | Secret guard, stage all, commit, push |
| `g-push` | `Push-GitBranch` | none | Push unpushed commits without staging |
</details>

### Pull Request
<details>
<summary>Click to expand</summary>

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-open-pr` | `New-GitPullRequest` | PR title via pipeline (`-Body` optional) | Open PR against base branch; exits 0 with existing PR URL if one is already open |
| `g-pr-checks` | `Get-GitPullRequestChecks` | none | Summarise check results for current branch PR |
| `g-pr-view` | `Show-GitPullRequest` | none | Show PR detail: title, state, review decision, check rollup |
| `g-merge-rotate` | `Invoke-GitMergeRotate` | branch name (optional, via pipeline) | Merge PR, delete branch, create next branch (defaults to `wip/MMDD-HHmm`) |
</details>

### Status and Diagnostics
<details>
<summary>Click to expand</summary>

| Alias | Function | Input | What it does |
|-------|----------|-------|--------------|
| `g-status` | `Get-GitStatus` | none (`-d` for PR body) | One-line repo status |
| `g-matrix-scan` | `Get-GitMatrix` | none | Emit state hash and recommended next action |
| `g-matrix-resolve` | `Resolve-GitMatrix` | state hash via pipeline | Resolve hash to recommended next action |
| `g-backlog` | `Get-GitBacklog` | none | List all unhandled workflow states |
| `g-capabilities` | `Get-GitCapabilities` | none | Score script coverage against known gap requirements |
| `g-run-logs` | `Get-GitRunLogs` | none | Fetch most recent CI run logs grouped by step. Falls back to base branch when current branch has no runs |
</details>

## Error Recovery

### Rebase Conflict

`gitbox s` aborts automatically on conflict and restores the working tree. Resolve the conflict manually then continue:

```powershell
# after gitbox s reports "rebase conflict"
git status                   # see conflicted files
# edit files to resolve conflicts
git add <resolved-files>
git rebase --continue
```

### Secret Guard Block

If `gitbox c` reports `secret guard: blocked`, the listed files match a sensitive filename pattern. Remove or rename them before retrying:

```powershell
# after secret guard block
git status                   # confirm which files are present
# move or delete the flagged files
gitbox c "your commit message"
```

### Merge Failure

If `gitbox m` reports `merge failed`, the PR was not merged and the branch is preserved. Check the failure reason and retry:

```powershell
# after merge failed
gitbox x                     # inspect failing CI checks
gitbox P                     # read merge blockers (review decision, check rollup)
# resolve the blocker, then:
gitbox m "next-branch-name"
```

### gh Authentication Error

If any gitbox command reports `authentication failed` or `permission denied` on a `gh` call:

```powershell
gh auth login                # re-authenticate
gh auth status               # verify scope includes repo
```

## Matrix Internals

`gitbox S`, `gitbox B`, and `gitbox C` (and the underlying `g-matrix-resolve` pipeline utility) operate on a compact state hash that encodes the full repo situation in one string.

### State Hash Format

```
<class>|<dirty>|a<N>|b<N>|<push>|<PR>
```

Example: `F|d3|a2|b0|U|PR-`

| Segment | Values | Definition |
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

### Resolve Priority

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

### Backlog Sweep

> *The following sections are only relevant to gitbox development. They are not useful for general operation.*

`gitbox B` discovers gaps by running `g-matrix-resolve` against every valid state combination rather than parsing source text. Using two representative values per numeric dimension (0 and 1) the enumeration covers:

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

### Capabilities Scan

`gitbox C` reads every `g-*.ps1` script line by line, matches each non-comment line against the regex patterns in `$CapabilityPatterns`, and records which git/gh operations each script can perform.

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
