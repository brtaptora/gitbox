# Scans all g-*.ps1 scripts in $PSScriptRoot; extracts git/gh capabilities sequentially
# and scores each script against open gap requirements to surface extension candidates.
# Limitation: splatted calls (gh @args) are not resolved by static analysis.

. (Join-Path $PSScriptRoot "g-error-vectors.ps1")

# [ordered] ensures specific patterns match before their generic subsets (e.g. BRANCH_CREATE before CHECKOUT)
$CapabilityPatterns = [ordered]@{
    BRANCH_CREATE = 'git\b.+checkout\b.+-b\b'
    PUSH_DELETE   = 'git\b.+push\b.+--delete\b'
    BRANCH_RENAME = 'git\b.+branch\b.+-m\b'
    BRANCH_DELETE = 'git\b.+branch\b.+(-d|-D)\b'
    STAGE         = 'git\b.+add\b'
    COMMIT        = 'git\b.+commit\b'
    PUSH          = 'git\b.+push\b'
    PULL          = 'git\b.+pull\b'
    REBASE        = 'git\b.+rebase\b'
    CHECKOUT      = 'git\b.+checkout\b'
    MERGE         = 'git\b.+merge\b'
    PR_CREATE     = 'gh\b.+pr\s+create\b'
    PR_MERGE      = 'gh\b.+pr\s+merge\b'
    PR_READY      = 'gh\b.+pr\s+ready\b'
    PR_CHECKS     = 'gh\b.+pr\s+checks\b'
    PR_LIST       = 'gh\b.+pr\s+list\b'
}

function Get-ScriptCapabilities {
    param([string]$Path)
    $seen   = [System.Collections.Generic.HashSet[string]]::new()
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content $Path)) {
        $t = $line.Trim()
        # skip blank, full-line comments, and lines where git/gh appear only inside a string literal
        if (-not $t -or $t -match '^#' -or $t -match '^\$\w+\s*[+]?=\s*".*\b(git|gh)\b') { continue }
        foreach ($cap in $CapabilityPatterns.Keys) {
            if ($t -match $CapabilityPatterns[$cap]) {
                if ($seen.Add($cap)) { $result.Add($cap) }
                break
            }
        }
    }
    return [string[]]$result
}

$scripts = Get-ChildItem -Path $PSScriptRoot -Filter 'g-*.ps1' |
    Where-Object { $_.Name -ne 'g-capabilities.ps1' } |
    Sort-Object Name

$capMap = @{}
foreach ($s in $scripts) {
    $capMap[$s.Name] = Get-ScriptCapabilities -Path $s.FullName
}

# --- Script capabilities ---
Write-Host 'Script capabilities:'
foreach ($name in ($capMap.Keys | Sort-Object)) {
    $caps    = $capMap[$name]
    $capsStr = if ($caps.Count) { $caps -join ' -> ' } else { '(read-only)' }
    Write-Host ("  {0,-32} {1}" -f $name, $capsStr)
}

# --- Gap coverage ---
Write-Host "`nGap coverage:"
foreach ($dim in ($GapRequirements.Keys | Sort-Object)) {
    $required = $GapRequirements[$dim]
    Write-Host ("`n  GAP[{0}]  requires: {1}" -f $dim, ($required -join ', '))

    $unsorted = foreach ($name in $capMap.Keys) {
        $caps  = [string[]]$capMap[$name]
        $hit   = @($required | Where-Object { $_ -in $caps })
        $miss  = @($required | Where-Object { $_ -notin $caps })
        $score = if ($required.Count) { [double]$hit.Count / $required.Count } else { 0 }
        if ($score -gt 0) {
            [pscustomobject]@{ Script = $name; Score = $score; Hit = $hit; Miss = $miss }
        }
    }
    $scored = @($unsorted | Sort-Object Score -Descending)

    if (-not $scored) {
        Write-Host '    (no match -- new script needed)'
    } else {
        foreach ($c in $scored) {
            $pct     = [int]($c.Score * 100)
            $hitStr  = ($c.Hit  | ForEach-Object { "$_`:+" }) -join ' '
            $missStr = ($c.Miss | ForEach-Object { "$_`:-" }) -join ' '
            $detail  = (@($hitStr, $missStr) | Where-Object { $_ }) -join '  '
            Write-Host ("    {0,-32} {1,4}%  {2}" -f $c.Script, $pct, $detail)
        }
        if ($scored[0].Score -lt 1.0) {
            Write-Host '    (no full match -- new script or multi-script extension)'
        } else {
            Write-Host "    (extend $($scored[0].Script))"
        }
    }
}
