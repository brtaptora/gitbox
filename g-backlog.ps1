# Derives the gap backlog by exercising g-matrix-resolve.ps1 against all valid state combinations.
# Gaps are discovered by running the logic, not by parsing source text.

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

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
                        $r = Resolve-MatrixAction -Hash "$cl|$di|$ah|$be|$pu|$pr"
                        if ($r -and $r.Dim) {
                            $req     = $GapRequirements[$r.Dim]
                            $covered = $req -and (@($req | Where-Object { $_ -in $AllCapabilities }).Count -eq $req.Count)
                            if (-not $covered) {
                                "  $(Format-GapLabel -Class $r.Class -Dim $r.Dim -Ahead $r.Ahead -Behind $r.Behind -Pr $r.Pr)"
                            }
                        }
                    }
                }
            }
        }
    }
}

$gaps = $gaps | ForEach-Object { $_.Trim() } | Select-Object -Unique | Sort-Object

if ($gaps) {
    $i = 1
    foreach ($gap in $gaps) {
        Write-Host "$i. $gap"
        $i++
    }
    Write-Host ''
} else {
    Write-Host "no gaps found"
    Write-Host ''
}

Write-Host 'Workflow coverage:'
$allGapDims = $GapRequirements.Keys | Sort-Object
foreach ($wfName in $WorkflowRegistry.Keys) {
    $wFlags  = $WorkflowRegistry[$wfName]
    if ($wFlags -cnotmatch '[a-z]') { continue }
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

$unclassified = @($gaps | Where-Object { $_ -match 'GAP\[UNCLASSIFIED\]' })
if ($unclassified.Count -gt 0) {
    Write-Host ''
    Write-Host "$($unclassified.Count) unclassified gap$(if ($unclassified.Count -ne 1) {'s'}) -- add resolve rules to g-matrix-resolve.ps1"
    exit 1
}
exit 0
