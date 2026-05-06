# Accepts a status hash via pipeline and returns the recommended next action.
# Hash format: [B|F|W]|[c|dN|sN]|a[N]|b[N]|[P|U]|[PR-|PRD|PRO|PRX|PRA]
# Example:     F|d3|a2|b0|U|PR-

param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Hash
)

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

    $action = $null
    $gap    = $null

    if ($class -eq "B") {
        $gap    = "GAP: no script for base branch state"
        $action = "create a feature branch: git checkout -b <name>"
    }
    elseif ($class -eq "W") {
        $gap    = "GAP: no rename script"
        $action = "rename wip branch: git branch -m <feature-name>"
    }
    elseif ($class -eq "F") {
        if ($dirty -like "s*") {
            $gap    = "GAP: no secret guard in g-commit-push"
            $action = "remove secrets from working tree before staging"
        }
        elseif ($behind -gt 0) {
            $gap    = "GAP: no sync script"
            $action = "rebase onto base: git rebase origin/<base-branch>"
        }
        elseif ($pr -eq "PRX") {
            $gap    = "GAP: no check-status script"
            $action = "fix failing checks: gh pr checks"
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
                $gap    = "GAP: g-commit-push exits early when clean; no push-only script"
                $action = "git push -u origin <branch>  then  g-open-pr"
            }
            elseif ($ahead -eq 0 -and $dirty -eq "c") {
                $action = "nothing to do; make changes first"
            }
        }
    }
    else {
        $action = "unrecognised branch class '$class'"
    }

    if ($gap)    { Write-Host "  $gap" }
    if ($action) { Write-Host "  next: $action" }
}
