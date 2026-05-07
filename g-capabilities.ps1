# Scans all g-*.ps1 scripts in $PSScriptRoot; extracts git/gh capabilities sequentially
# and scores each script against open gap requirements to surface extension candidates.
# Limitation: splatted calls (gh @args) are not resolved by static analysis.

. (Join-Path $PSScriptRoot "g-error-vectors.ps1")

$scripts = Get-ChildItem -Path $PSScriptRoot -Filter 'g-*.ps1' |
    Where-Object { $_.Name -notin 'g-capabilities.ps1','g-error-vectors.ps1','g-registry.ps1' } |
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
exit 0
