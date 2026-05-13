# Unified health report: gap sweep (360 states), workflow coverage, per-script inventory.
# Default output is pretty (colors + Unicode bars). Auto-switches to plain when stdout is
# redirected (CI). Pass -Plain to force plain text explicitly.

param([switch]$Plain)
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
    if ($caps -eq 0)         { return 'DarkGray' }
    if ($score -ge 0.08)     { return 'Green'    }
    if ($score -ge $threshold) { return 'Yellow'   }
    return 'Red'
}

# --- [1] Gap sweep (360 states) ---

$resolveScript = Join-Path $PSScriptRoot 'g-matrix-resolve.ps1'
$gapData = foreach ($cl in 'B','F','W') { foreach ($di in 'c','d1','s1') {
    foreach ($ah in 'a0','a1') { foreach ($be in 'b0','b1') {
        foreach ($pu in 'P','U') { foreach ($pr in 'PR-','PRD','PRO','PRX','PRA') {
            $hash = "$cl|$di|$ah|$be|$pu|$pr"
            ("$hash" | & $resolveScript 6>&1) | ForEach-Object { "$_" } | Where-Object { $_ -match 'GAP\[' }
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
                                    'g-registry.ps1','g-health.ps1','g-optimization.ps1') } |
    Sort-Object Name

$scriptRows = foreach ($s in $scripts) {
    $caps  = Get-ScriptCapabilities -Path $s.FullName
    $lines = @(Get-Content $s.FullName | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' }).Count
    $score = if ($lines -gt 0 -and $caps.Count -gt 0) { [Math]::Round($caps.Count / $lines, 3) } else { 0 }
    $dimsCovered = @(foreach ($dim in ($GapRequirements.Keys | Sort-Object)) {
        $req = $GapRequirements[$dim]
        if (@($req | Where-Object { $_ -in $caps }).Count -eq $req.Count) { $dim }
    })
    [pscustomobject]@{
        Name        = $s.Name
        Short       = ($s.Name -replace '^g-' -replace '\.ps1$')
        Caps        = $caps
        Lines       = $lines
        Score       = $score
        Dims        = $dimsCovered
        LowDensity  = ($caps.Count -gt 0 -and $score -lt $threshold)
    }
}

$lowDensityCount = @($scriptRows | Where-Object LowDensity).Count

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
    pw ('  {0,-18}  {1,4}  {2,-5}  {3,-5}  ' -f 'script','caps','bar','score') 'DarkGray'; pw 'dims' 'DarkGray'; Write-Host ''
    foreach ($row in $scriptRows) {
        $sc = Get-ScoreColor $row.Score $row.Caps.Count
        $nc = if ($row.Caps.Count -eq 0) { 'DarkGray' } else { 'White' }
        pw '  '; pw ('{0,-18}' -f $row.Short) $nc; pw '  '
        if ($row.Caps.Count -gt 0) {
            pw ('{0,4}' -f $row.Caps.Count) 'White'; pw '  '
            pw (Get-Bar $row.Score) $sc; pw '  '
            pw ('{0:0.000}' -f $row.Score) $sc
        } else {
            pw ('{0,4}' -f ([char]0x2014)) 'DarkGray'; pw '  '
            pw (([string][char]0x2591) * 5) 'DarkGray'; pw '  '
            pw ([char]0x2014) 'DarkGray'
        }
        pw '  '
        if ($row.Dims.Count) {
            foreach ($dim in $row.Dims) { pw $dim 'Cyan'; pw ' ' }
        } else { pw ([char]0x2014) 'DarkGray' }
        if ($row.LowDensity) { pw ("  " + [char]0x26A0 + " low density") 'Yellow' }
        Write-Host ''
    }

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
    Write-Host ('  {0,-34} {1,4}  {2,5}  {3,5}  {4}' -f 'Script', 'Caps', 'Lines', 'Score', 'Dims')
    foreach ($row in $scriptRows) {
        $dimsStr  = if ($row.Dims.Count) { $row.Dims -join ' ' } else { '-' }
        $scoreStr = if ($row.Score -gt 0) { ('{0:0.000}' -f $row.Score) } else { '-' }
        $capsStr  = if ($row.Caps.Count -gt 0) { "$($row.Caps.Count)" } else { '-' }
        $suffix   = if ($row.LowDensity) { '  (!)' } else { '' }
        Write-Host ('  {0,-34} {1,4}  {2,5}  {3,5}  {4}{5}' -f $row.Name, $capsStr, $row.Lines, $scoreStr, $dimsStr, $suffix)
    }
}
exit 0
