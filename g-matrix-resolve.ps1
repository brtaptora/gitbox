# Accepts a status hash via pipeline and returns the recommended next action.
# Hash format: [B|F|W]|[c|dN|sN]|a[N]|b[N]|[P|U]|[PR-|PRD|PRO|PRX|PRA]
# Example:     F|d3|a2|b0|U|PR-

param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Hash
)

begin {
    . (Join-Path $PSScriptRoot "g-error-vectors.ps1")
}

process {
    $parts = $Hash -split '\|'
    if ($parts.Count -ne 6) {
        Write-Host "invalid hash: expected 6 segments separated by |"; exit 1
    }

    $class  = $parts[0]
    $dirty  = $parts[1]
    $ahead  = [int]($parts[2] -replace 'a', '')
    $behind = [int]($parts[3] -replace 'b', '')
    $push   = $parts[4]
    $pr     = $parts[5]

    $action    = $null
    $gapStderr = $null

    if ($class -eq "B") {
        $gapStderr = "fatal: no feature branch; currently on base branch"
        $action    = "create a feature branch: git checkout -b <name>"
    }
    elseif ($class -eq "W") {
        $gapStderr = "fatal: no rename script; currently on wip branch"
        $action    = "rename wip branch: git branch -m <feature-name>"
    }
    elseif ($class -eq "F") {
        if ($dirty -like "s*") {
            $action = "g-commit-push is blocked -- remove secret-pattern files from working tree"
        }
        elseif ($behind -gt 0) {
            $gapStderr = "fatal: your branch is behind origin by $behind commit$(if ($behind -ne 1) {'s'}) and needs to be updated"
            $action    = "rebase onto base: git rebase origin/<base-branch>"
        }
        elseif ($pr -eq "PRX") {
            $gapStderr = "error: required status checks failed; check failed on this pull request"
            $action    = "fix failing checks: gh pr checks"
        }
        elseif ($pr -eq "PRO" -or $pr -eq "PRA") {
            if ($dirty -like "d*") {
                $action = "g-commit-push then g-merge-rotate"
            } else {
                $action = "g-merge-rotate"
            }
        }
        elseif ($pr -eq "PRD") {
            if ($dirty -like "d*") {
                $action = "g-commit-push  (draft PR open; push more commits)"
            } else {
                $action = "mark PR ready: gh pr ready"
            }
        }
        elseif ($pr -eq "PR-") {
            if ($dirty -like "d*") {
                $action = "g-commit-push"
            }
            elseif ($ahead -gt 0 -and $push -eq "P") {
                $action = "g-open-pr"
            }
            elseif ($ahead -gt 0 -and $push -eq "U") {
                $gapStderr = "nothing to stage; $ahead unpushed commit$(if ($ahead -ne 1) {'s'}) ahead of origin"
                $action    = "git push -u origin <branch>  then  g-open-pr"
            }
            elseif ($ahead -eq 0 -and $dirty -eq "c") {
                $action = "nothing to do; make changes first"
            }
        }
    }
    else {
        $action = "unrecognised branch class '$class'"
    }

    if ($gapStderr) {
        $dim = Resolve-StderrToVector -Stderr $gapStderr
        if ($dim) {
            Write-Host "  $(Format-GapLabel -Class $class -Dim $dim -Ahead $ahead -Behind $behind -Pr $pr)"
        } else {
            Write-Host "  GAP[UNCLASSIFIED]: $gapStderr"
        }
    }
    if ($action) { Write-Host "  next: $action" }
    exit 0
}
