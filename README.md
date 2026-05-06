# gitbox

PowerShell git utility scripts. Run from a PowerShell prompt in any git repo.

| Script | Input | What it does |
|--------|-------|--------------|
| `git-state.ps1` | none (`-d` for PR body) | One-line repo status |
| `commit-push.ps1` | commit message via pipeline | Stage all, commit, push |
| `open-pr.ps1` | PR title via pipeline (`-Body` optional) | Open PR against default branch |
| `merge-rotate.ps1` | none | Merge current branch PR, delete branch, create new wip |
