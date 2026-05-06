# Derives the gap backlog by exercising g-matrix-resolve.ps1 against all valid state combinations.
# Gaps are discovered by running the logic, not by parsing source text.

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

$resolveScript = Join-Path $PSScriptRoot "g-matrix-resolve.ps1"

if (-not (Test-Path $resolveScript)) {
    Write-Host "g-matrix-resolve.ps1 not found at $resolveScript"; exit 1
}

$classes = 'B','F','W'
$dirties = 'c','d1','s1'
$aheads  = 'a0','a1'
$behinds = 'b0','b1'
$pushes  = 'P','U'
$prs     = 'PR-','PRD','PRO','PRX','PRA'

$gaps = foreach ($cl in $classes) {
    foreach ($di in $dirties) {
        foreach ($ah in $aheads) {
            foreach ($be in $behinds) {
                foreach ($pu in $pushes) {
                    foreach ($pr in $prs) {
                        $hash = "$cl|$di|$ah|$be|$pu|$pr"
                        # 6>&1 captures Write-Host (Information stream) into the pipeline for filtering
                        ("$hash" | & $resolveScript 6>&1) |
                            ForEach-Object { "$_" } |
                            Where-Object   { $_ -match 'GAP\[' }
                    }
                }
            }
        }
    }
}

$gaps = $gaps | ForEach-Object { $_.Trim() } | Select-Object -Unique | Sort-Object

if (-not $gaps) { Write-Host "no gaps found"; exit 0 }

$i = 1
foreach ($gap in $gaps) {
    Write-Host "$i. $gap"
    $i++
}

Write-Host ''
Write-Host 'Workflow coverage:'
$allGapDims = $GapRequirements.Keys | Sort-Object
foreach ($wfName in $WorkflowRegistry.Keys) {
    $wFlags  = $WorkflowRegistry[$wfName]
    $allCaps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($f in $wFlags.ToCharArray()) {
        $fc = $FlagCapabilities["$f"]
        if ($fc) { foreach ($cap in $fc) { [void]$allCaps.Add($cap) } }
    }
    $covers = foreach ($dim in $allGapDims) {
        $req = $GapRequirements[$dim]
        if (@($req | Where-Object { $_ -in $allCaps }).Count -eq $req.Count) { $dim }
    }
    $coversStr = if ($covers) { $covers -join ' ' } else { '(none)' }
    Write-Host ("  {0,-8} = {1,-6}  covers: {2}" -f $wfName, $wFlags, $coversStr)
}
