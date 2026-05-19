# Phase 1 Report — Blank to Tagged Release

Session: 2026-05-19
PRs: #91 (init-todoapp), #92 (add-priority), #93 (release to main)
Tag: v2.0.2

---

## What was useful

**`gitbox b` from wip is frictionless.** After merge lands on wip, `gitbox b "feat/next"` pulls base and creates the new branch in one step. No manual `g` needed. This is the right default post-merge action.

**`gitbox full` is the real workhorse.** One line covers branch → commit → push → open PR → CI → merge. Feature B (priority) was done in a single command after writing the code. Nothing else to think about.

**`gitbox gz` from wip is the canonical release path.** After both merges left me on wip, `gitbox gz v2.0.2` went: escape wip → develop → open release PR → check CI → merge to main → tag. Zero manual steps.

**State hash is immediately actionable.** The `F|d1|a0|b0|U|PR-` header removes all ambiguity about what command to run. Decision tree is a direct lookup, not reasoning.

**Compound skip logic is forgiving.** `gitbox full` silently skipped `u` (already pushed after `c`) and `x` (no CI configured). No errors, no noise. Maximal compound = safest command.

**`gitbox z -View` before release is the right habit.** Tag collision is a real failure mode. Checking first is one extra command and avoids a hard error.

---

## What was not useful / confusing

**No selective staging.** `c` always does `git add -A`. If I had unrelated dirty files I didn't want to commit, there's no way to stage a subset. `git add -p` has no gitbox equivalent. This is a real gap for real dev sessions where scratch files accumulate.

**The `gz` vs `z` distinction is non-obvious.** You must use `gz` (not bare `z`) from any non-base branch to avoid BUG-006 auto-merging your open PR. There's no warning if you get it wrong — it just does the wrong thing. A new user will type `gitbox z v1.0.0` and be confused by the side effect.

**Release PR number not shown in output.** The completion line printed: `released v2.0.2 |PR # merged |tagged |back on develop` — the `#` has no number after it. Minor, but the PR URL or number would be useful for audit trail.

**Two-string argument order requires memorization.** `gitbox co "msg" "title"` — first string to `c`, second to `o`. Not labeled, not hinted. Once you know it's fine, but the first time it's guesswork.

**No PR description on creation.** `gitbox o "title"` opens with the title only. No body. For real PRs you want a description, test plan, etc. The auto-read of `.github/pull_request_template.md` helps if the template exists, but there's no inline way to add a body.

---

## Gaps identified

1. No selective staging (partial commits)
2. No inline PR body / description flag on `o`
3. `z` from a feature branch silently triggers BUG-006 instead of erroring or warning
4. Release output: PR number not interpolated ("PR #" with no number)
5. No `gitbox stash list` or stash name visibility — stash is automatic but opaque
6. No issue/ticket linking on PR creation (`--link-issue` or similar)

---

## Intuitive

- State hash and decision tree — read once, never need docs again
- `gitbox full` — the name says everything
- `gitbox b` from wip — works exactly as expected
- Idempotency — running `co` with PR already open just commits/pushes, no error

## Not intuitive

- Wip guard concept — a new user hitting "hard-halt in non-interactive mode" with no commits made will be confused without knowing the wip branch rule
- `gz` vs `z` — they look like the same thing with one letter difference
- Canonical flag order — composition works differently than reading order suggests (km vs mk)
