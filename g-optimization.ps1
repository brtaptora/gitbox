# Scores each g-*.ps1 script by capability density (caps / non-blank non-comment lines).
# Low-density scripts with >0 caps are consolidation candidates.

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

$scripts = Get-ChildItem -Path $PSScriptRoot -Filter 'g-*.ps1' |
    Where-Object { $_.Name -notin @('g-capabilities.ps1','g-error-vectors.ps1','g-registry.ps1',
                                    'g-optimization.ps1','g-health.ps1') } |
    Sort-Object Name
$scored = foreach ($s in $scripts) {
    $caps  = Get-ScriptCapabilities -Path $s.FullName
    $lines = @(Get-Content $s.FullName |
        Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' }).Count
    $score = if ($lines -gt 0) { [Math]::Round($caps.Count / $lines, 3) } else { 0 }
    [pscustomobject]@{ Script = $s.Name; Caps = $caps.Count; Lines = $lines; Score = $score }
}
Write-Host 'Optimization scores (caps / non-blank non-comment lines):'
Write-Host ('  {0,-34} {1,4}  {2,5}  {3,5}' -f 'Script', 'Caps', 'Lines', 'Score')
foreach ($r in ($scored | Sort-Object Score)) {
    Write-Host ('  {0,-34} {1,4}  {2,5}  {3,5}' -f $r.Script, $r.Caps, $r.Lines, $r.Score)
}
$threshold  = 0.04
$candidates = @($scored | Where-Object { $_.Score -lt $threshold -and $_.Caps -gt 0 })
if ($candidates) {
    Write-Host "`nConsolidation candidates (score < $threshold):"
    foreach ($c in $candidates) {
        Write-Host "  $($c.Script)  score $($c.Score) -- low cap density, review for folding"
    }
}
exit 0
