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
    $r = Resolve-MatrixAction -Hash $Hash
    if (-not $r) { Write-Host "invalid hash: expected 6 segments separated by |"; exit 1 }

    if ($r.Dim) {
        $req     = $GapRequirements[$r.Dim]
        $covered = $req -and (@($req | Where-Object { $_ -in $AllCapabilities }).Count -eq $req.Count)
        if (-not $covered) {
            Write-Host "  $(Format-GapLabel -Class $r.Class -Dim $r.Dim -Ahead $r.Ahead -Behind $r.Behind -Pr $r.Pr)"
        }
    }
    if ($r.Action) { Write-Host "  next: $($r.Action)" }
    exit 0
}
