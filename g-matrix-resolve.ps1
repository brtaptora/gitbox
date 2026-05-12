# Accepts a status hash via pipeline and returns the recommended next action.
# Hash format: [B|F|W]|[c|dN|sN]|a[N]|b[N]|[P|U]|[PR-|PRD|PRO|PRX|PRA]
# Example:     F|d3|a2|b0|U|PR-

param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Hash
)

begin {
    . (Join-Path $PSScriptRoot "g-error-vectors.ps1")

    $allCaps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($caps in $FlagCapabilities.Values) {
        foreach ($cap in $caps) { [void]$allCaps.Add($cap) }
    }
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

    $action = $null
    $dim    = $null

    if ($class -eq "B") {
        $dim    = 'B_CLASS'
        $action = 'gitbox b "<feature-name>"'
    }
    elseif ($class -eq "W") {
        $dim    = 'W_CLASS'
        $action = 'gitbox r "<feature-name>"'
    }
    elseif ($class -eq "F") {
        if ($dirty -like "s*") {
            $action = "gitbox c is blocked -- remove secret-pattern files from working tree"
        }
        elseif ($behind -gt 0) {
            $dim    = 'BEHIND'
            $action = 'gitbox s'
        }
        elseif ($pr -eq "PRX") {
            $dim    = 'CHECKS'
            $action = 'fix CI failures, then: gitbox x'
        }
        elseif ($pr -eq "PRO" -or $pr -eq "PRA") {
            $action = if ($dirty -like "d*") { 'gitbox ship "<message>"' } else { 'gitbox m' }
        }
        elseif ($pr -eq "PRD") {
            $action = if ($dirty -like "d*") { 'gitbox c "<message>"  (draft PR open)' } else { 'mark PR ready: gh pr ready' }
        }
        elseif ($pr -eq "PR-") {
            if ($dirty -like "d*") {
                $action = 'gitbox c "<message>"'
            }
            elseif ($ahead -gt 0 -and $push -eq "P") {
                $action = 'gitbox o "<PR title>"'
            }
            elseif ($ahead -gt 0 -and $push -eq "U") {
                $dim    = 'NO_PUSH'
                $action = 'gitbox uo "<PR title>"'
            }
            elseif ($ahead -eq 0 -and $dirty -eq "c") {
                $action = 'nothing to do; make changes first'
            }
        }
    }
    else {
        $action = "unrecognised branch class '$class'"
    }

    if ($dim) {
        $req     = $GapRequirements[$dim]
        $covered = $req -and (@($req | Where-Object { $_ -in $allCaps }).Count -eq $req.Count)
        if (-not $covered) {
            Write-Host "  $(Format-GapLabel -Class $class -Dim $dim -Ahead $ahead -Behind $behind -Pr $pr)"
        }
    }
    if ($action) { Write-Host "  next: $action" }
    exit 0
}
