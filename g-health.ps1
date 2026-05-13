# Unified health report: gap sweep (360 states), workflow coverage, per-script inventory.
# Default output is pretty (colors + Unicode bars). Auto-switches to plain when stdout is
# redirected (CI). Pass -Plain to force plain text explicitly.
# -Cov adds per-script gap coverage score; -Uni adds uniqueness score; -CapV lists capability names.

param([switch]$Plain, [switch]$Cov, [switch]$Uni, [switch]$CapV)
. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

$pretty    = -not $Plain -and -not [System.Console]::IsOutputRedirected
$threshold = 0.04
$sep       = ([string][char]0x2500) * 54   # ─ * 54

# Write colored segment. Always no-newline; caller adds Write-Host '' for EOL.
function pw {
    param([string]$text, [string]$color = 'Gray')
    Write-Host $text -ForegroundColor $color -NoNewline
}

function Get-Bar {
    param([double]$score)
    $filled = [Math]::Min(5, [Math]::Round($score / 0.10 * 5))
    return ([string][char]0x2588) * $filled + ([string][char]0x2591) * (5 - $filled)
}

function Get-ScoreColor {
    param([double]$score, [int]$caps)
    if ($caps -eq 0)             { return 'DarkGray' }
    if ($score -ge 0.08)         { return 'Green'    }
    if ($score -ge $threshold)   { return 'Yellow'   }
    return 'Red'
}

function Get-CovColor {
    param([double]$score)
    if ($score -ge 1.0) { return 'Green'  }
    if ($score -gt 0)   { return 'Yellow' }
    return 'DarkGray'
}

function Get-UniColor {
    param([double]$score)
    if ($score -ge 0.5) { return 'Green'  }
    if ($score -gt 0)   { return 'Yellow' }
    return 'DarkGray'
}

# --- [1] Gap sweep (360 states) ---

$gapData = foreach ($cl in 'B','F','W') { foreach ($di in 'c','d1','s1') {
    foreach ($ah in 'a0','a1') { foreach ($be in 'b0','b1') {
        foreach ($pu in 'P','U') { foreach ($pr in 'PR-','PRD','PRO','PRX','PRA') {
            $r = Resolve-MatrixAction -Hash "$cl|$di|$ah|$be|$pu|$pr"
            if ($r -and $r.Dim) {
                $req     = $GapRequirements[$r.Dim]
                $covered = $req -and (@($req | Where-Object { $_ -in $AllCapabilities }).Count -eq $req.Count)
                if (-not $covered) {
                    "  $(Format-GapLabel -Class $r.Class -Dim $r.Dim -Ahead $r.Ahead -Behind $r.Behind -Pr $r.Pr)"
                }
            }
        } } } } } }
$gaps = @($gapData | ForEach-Object { $_.Trim() } | Select-Object -Unique | Sort-Object)

# --- [2] Workflow coverage ---

$wfRows = foreach ($wfName in $WorkflowRegistry.Keys) {
    $wFlags = $WorkflowRegistry[$wfName]
    if ($wFlags -cnotmatch '[a-z]') { continue }   # skip diagnostic-only aliases (e.g. health=H); -c for case-sensitive
    $allCaps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($f in $wFlags.ToCharArray()) {
        $fc = $FlagCapabilities["$f"]
        if ($fc) { foreach ($cap in $fc) { [void]$allCaps.Add($cap) } }
    }
    $covered = @(foreach ($dim in ($GapRequirements.Keys | Sort-Object)) {
        $req = $GapRequirements[$dim]
        if (@($req | Where-Object { $_ -in $allCaps }).Count -eq $req.Count) { $dim }
    })
    [pscustomobject]@{ Name = $wfName; Flags = $wFlags; Dims = $covered }
}

# --- [3] Script inventory ---

$scripts = Get-ChildItem -Path $PSScriptRoot -Filter 'g-*.ps1' |
    Where-Object { $_.Name -notin @('g-capabilities.ps1','g-error-vectors.ps1',
                                    'g-registry.ps1','g-health.ps1','g-optimization.ps1',
                                    'g-matrix-resolve.ps1') } |
    Sort-Object Name

$totalDims = $GapRequirements.Keys.Count

$scriptRows = foreach ($s in $scripts) {
    $caps  = Get-ScriptCapabilities -Path $s.FullName
    $lines = @(Get-Content $s.FullName | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' }).Count
    $score = if ($lines -gt 0 -and $caps.Count -gt 0) { [Math]::Round($caps.Count / $lines, 3) } else { 0 }
    $dimsCovered = @(foreach ($dim in ($GapRequirements.Keys | Sort-Object)) {
        $req = $GapRequirements[$dim]
        if (@($req | Where-Object { $_ -in $caps }).Count -eq $req.Count) { $dim }
    })
    $covScore = if ($totalDims -gt 0) { [Math]::Round($dimsCovered.Count / $totalDims, 3) } else { 0 }
    [pscustomobject]@{
        Name        = $s.Name
        Short       = ($s.Name -replace '^g-' -replace '\.ps1$')
        Caps        = $caps
        Lines       = $lines
        Score       = $score
        Dims        = $dimsCovered
        CovScore    = $covScore
        LowDensity  = ($caps.Count -gt 0 -and $score -lt $threshold)
    }
}

# --- Uniqueness scores (cross-script cap frequency; cap present in exactly one script = unique) ---

if ($Uni) {
    $capFreq = @{}
    foreach ($row in $scriptRows) { foreach ($cap in $row.Caps) { $capFreq[$cap] = ($capFreq[$cap] ?? 0) + 1 } }
    foreach ($row in $scriptRows) {
        $uniq     = @($row.Caps | Where-Object { $capFreq[$_] -eq 1 }).Count
        $uniScore = if ($row.Caps.Count -gt 0) { [Math]::Round($uniq / $row.Caps.Count, 3) } else { 0 }
        Add-Member -InputObject $row -NotePropertyName UniScore -NotePropertyValue $uniScore
    }
}

$lowDensityCount = @($scriptRows | Where-Object LowDensity).Count

# --- Footer stats ---

$coveredDims = @($GapRequirements.Keys | Where-Object {
    $req = $GapRequirements[$_]
    (@($req | Where-Object { $_ -in $AllCapabilities }).Count -eq $req.Count)
}).Count
$overallCov = if ($totalDims -gt 0) { [Math]::Round($coveredDims / $totalDims, 3) } else { 0 }
$scoredRows = @($scriptRows | Where-Object { $_.Score -gt 0 })
$avgDensity = if ($scoredRows.Count -gt 0) { [Math]::Round(($scoredRows | Measure-Object Score -Average).Average, 3) } else { 0 }
$composite  = [Math]::Round($avgDensity * $overallCov, 3)

# --- Summary badge ---

$badge = if ($gaps.Count -gt 0) {
    @{ Text = ([char]0x2717 + " $($gaps.Count) gap$(if ($gaps.Count -ne 1){'s'})"); Color = 'Red' }
} elseif ($lowDensityCount -gt 0) {
    @{ Text = ([char]0x26A0 + " $lowDensityCount low-density"); Color = 'Yellow' }
} else {
    @{ Text = ([char]0x2713 + ' no gaps'); Color = 'Green' }
}

# ══════════════════════════ OUTPUT ══════════════════════════

if ($pretty) {
    # Title
    $pad = ' ' * [Math]::Max(2, 48 - 'Gitbox Health'.Length)
    pw '  Gitbox Health' 'White'; pw $pad; pw $badge.Text $badge.Color; Write-Host ''
    Write-Host ''

    # ── Gaps ──
    $gapStatus      = if ($gaps.Count -gt 0) { [char]0x2717 + " $($gaps.Count) gap$(if($gaps.Count-ne 1){'s'})" } else { [char]0x2713 + ' clean' }
    $gapStatusColor = if ($gaps.Count -gt 0) { 'Red' } else { 'Green' }
    pw '  Gaps  ' 'White'; pw '(360 states)' 'DarkGray'
    pw (' ' * [Math]::Max(2, 28 - '(360 states)'.Length)); pw "  $gapStatus" $gapStatusColor; Write-Host ''
    pw "  $sep" 'DarkGray'; Write-Host ''
    if ($gaps.Count -gt 0) {
        foreach ($gap in $gaps) { pw "  $gap" 'Red'; Write-Host '' }
    }
    Write-Host ''

    # ── Workflows ──
    pw '  Workflows' 'White'; Write-Host ''
    pw "  $sep" 'DarkGray'; Write-Host ''
    pw ('  {0,-10}  {1,-7}  ' -f 'name','flags') 'DarkGray'; pw 'dims' 'DarkGray'; Write-Host ''
    foreach ($row in $wfRows) {
        pw '  '; pw ('{0,-10}' -f $row.Name) 'White'
        pw '  '; pw ('{0,-7}' -f $row.Flags) 'White'
        pw '  '
        if ($row.Dims.Count) {
            foreach ($dim in $row.Dims) { pw $dim 'Cyan'; pw '  ' }
        } else { pw ([char]0x2014) 'DarkGray' }
        Write-Host ''
    }
    Write-Host ''

    # ── Scripts ──
    pw '  Scripts' 'White'; Write-Host ''
    pw "  $sep" 'DarkGray'; Write-Host ''
    $hdr = '  {0,-18}  {1,4}  {2,-5}  {3,-5}' -f 'script','caps','bar','score'
    if ($Cov) { $hdr += '  {0,-5}' -f 'cov' }
    if ($Uni) { $hdr += '  {0,-5}' -f 'uni' }
    $hdr += '  '
    pw $hdr 'DarkGray'; pw 'dims' 'DarkGray'; Write-Host ''
    foreach ($row in $scriptRows) {
        $sc = Get-ScoreColor $row.Score $row.Caps.Count
        $nc = if ($row.Caps.Count -eq 0) { 'DarkGray' } else { 'White' }
        pw '  '; pw ('{0,-18}' -f $row.Short) $nc; pw '  '
        if ($row.Caps.Count -gt 0) {
            pw ('{0,4}' -f $row.Caps.Count) 'White'; pw '  '
            pw (Get-Bar $row.Score) $sc; pw '  '
            pw ('{0:0.000}' -f $row.Score) $sc
            if ($Cov) { pw '  '; pw ('{0:0.000}' -f $row.CovScore) (Get-CovColor $row.CovScore) }
            if ($Uni) { pw '  '; pw ('{0:0.000}' -f $row.UniScore) (Get-UniColor $row.UniScore) }
        } else {
            pw ('{0,4}' -f ([char]0x2014)) 'DarkGray'; pw '  '
            pw (([string][char]0x2591) * 5) 'DarkGray'; pw '  '
            pw ([char]0x2014) 'DarkGray'
            if ($Cov) { pw '  '; pw ([char]0x2014) 'DarkGray' }
            if ($Uni) { pw '  '; pw ([char]0x2014) 'DarkGray' }
        }
        pw '  '
        if ($row.Dims.Count) {
            foreach ($dim in $row.Dims) { pw $dim 'Cyan'; pw ' ' }
        } else { pw ([char]0x2014) 'DarkGray' }
        if ($row.LowDensity) { pw ("  " + [char]0x26A0 + " low density") 'Yellow' }
        Write-Host ''
        if ($CapV -and $row.Caps.Count -gt 0) {
            pw '    '; pw ($row.Caps -join '  ') 'DarkGray'; Write-Host ''
        }
    }

    # ── Footer ──
    Write-Host ''
    pw "  $sep" 'DarkGray'; Write-Host ''
    $covColor  = if ($overallCov -ge 1.0) { 'Green' } elseif ($overallCov -gt 0) { 'Yellow' } else { 'Red' }
    $compColor = if ($composite -ge 0.05) { 'Green' } elseif ($composite -gt 0) { 'Yellow' } else { 'Red' }
    pw '  '; pw 'coverage ' 'DarkGray'; pw "$coveredDims/$totalDims" $covColor
    pw '   '; pw 'avg density ' 'DarkGray'; pw ('{0:0.000}' -f $avgDensity) 'White'
    pw '   '; pw 'composite ' 'DarkGray'; pw ('{0:0.000}' -f $composite) $compColor
    Write-Host ''

} else {
    # ── Plain output ──
    Write-Host 'Gaps  (360 states)'
    if ($gaps.Count -gt 0) {
        foreach ($gap in $gaps) { Write-Host "  $gap" }
    } else { Write-Host '  no gaps found' }
    Write-Host ''

    Write-Host 'Workflows'
    foreach ($row in $wfRows) {
        $dimsStr = if ($row.Dims.Count) { $row.Dims -join ' ' } else { '-' }
        Write-Host ('  {0,-8}  {1,-6}  {2}' -f $row.Name, $row.Flags, $dimsStr)
    }
    Write-Host ''

    Write-Host 'Scripts'
    $scriptHdr = '  {0,-34} {1,4}  {2,5}  {3,5}' -f 'Script','Caps','Lines','Score'
    if ($Cov) { $scriptHdr += '    cov' }
    if ($Uni) { $scriptHdr += '    uni' }
    $scriptHdr += '  Dims'
    Write-Host $scriptHdr
    foreach ($row in $scriptRows) {
        $dimsStr  = if ($row.Dims.Count) { $row.Dims -join ' ' } else { '-' }
        $scoreStr = if ($row.Score -gt 0) { ('{0:0.000}' -f $row.Score) } else { '-' }
        $capsStr  = if ($row.Caps.Count -gt 0) { "$($row.Caps.Count)" } else { '-' }
        $suffix   = if ($row.LowDensity) { '  (!)' } else { '' }
        $line     = '  {0,-34} {1,4}  {2,5}  {3,5}' -f $row.Name, $capsStr, $row.Lines, $scoreStr
        if ($Cov) { $cs = $row.CovScore -gt 0 ? ('{0:0.000}' -f $row.CovScore) : '-'; $line += '  {0,-5}' -f $cs }
        if ($Uni) { $us = $row.UniScore -gt 0 ? ('{0:0.000}' -f $row.UniScore) : '-'; $line += '  {0,-5}' -f $us }
        $line += "  $dimsStr$suffix"
        Write-Host $line
        if ($CapV -and $row.Caps.Count -gt 0) { Write-Host "    caps: $($row.Caps -join ' ')" }
    }
    Write-Host ''
    Write-Host "coverage $coveredDims/$totalDims  avg-density $avgDensity  composite $composite"
}
exit 0
