# Flag-stack orchestrator. Routes flag sequences to scripts in canonical order.
# Usage: gitbox <flags|workflow> [arg ...]
# Flags: b=branch-create r=rename s=sync c=commit u=push o=open-pr x=pr-checks m=merge-rotate
#        Q=status S=matrix-scan B=backlog C=capabilities W=workflow-registry O=optimize

param(
    [Parameter(Position=0, Mandatory)]
    [string]$Spec,
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Rest
)

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')

# Case-sensitive: lowercase=mutating, uppercase=diagnostic; 's' and 'S' are distinct keys
$FlagMap = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
$FlagMap['b'] = @{ Script = 'g-branch-create.ps1';  NeedsArg = $true;  Force = $true }
$FlagMap['r'] = @{ Script = 'g-branch-rename.ps1';  NeedsArg = $true  }
$FlagMap['s'] = @{ Script = 'g-branch-sync.ps1';    NeedsArg = $false }
$FlagMap['c'] = @{ Script = 'g-commit-push.ps1';    NeedsArg = $true  }
$FlagMap['u'] = @{ Script = 'g-push.ps1';           NeedsArg = $false }
$FlagMap['o'] = @{ Script = 'g-open-pr.ps1';        NeedsArg = $true  }
$FlagMap['x'] = @{ Script = 'g-pr-checks.ps1';      NeedsArg = $false }
$FlagMap['m'] = @{ Script = 'g-merge-rotate.ps1';   NeedsArg = 'optional' }
$FlagMap['Q'] = @{ Script = 'g-status.ps1';         NeedsArg = $false }
$FlagMap['S'] = @{ Script = 'g-matrix-scan.ps1';    NeedsArg = $false }
$FlagMap['B'] = @{ Script = 'g-backlog.ps1';        NeedsArg = $false }
$FlagMap['C'] = @{ Script = 'g-capabilities.ps1';   NeedsArg = $false }
$FlagMap['W'] = @{ Script = $null;                  NeedsArg = $false }
$FlagMap['O'] = @{ Script = $null;                  NeedsArg = $false }

$CanonicalOrder = [string[]]@('b','r','s','c','u','o','x','m','Q','S','B','C','W','O')

# Resolve workflow name or raw flag string
$flagStr = if ($WorkflowRegistry.Contains($Spec)) { $WorkflowRegistry[$Spec] } else { $Spec.TrimStart('-') }

# Validate all flag characters
foreach ($ch in $flagStr.ToCharArray()) {
    if (-not $FlagMap.Contains([string]$ch)) {
        Write-Host "gitbox: unknown flag '$ch' -- valid flags: $($FlagMap.Keys -join '')"
        exit 1
    }
}

# Build ordered step list
$steps = [System.Collections.Generic.List[psobject]]::new()
foreach ($f in $CanonicalOrder) {
    if ($flagStr.Contains($f)) {
        $steps.Add([pscustomobject]@{ Flag = $f; Info = $FlagMap[$f] })
    }
}

# Verify arg count before executing anything; 'optional' flags are not counted as required
$argSteps = @($steps | Where-Object { $_.Info.NeedsArg -eq $true })
$argCount  = if ($Rest) { $Rest.Count } else { 0 }
if ($argCount -lt $argSteps.Count) {
    $missing = $argSteps[$argCount]
    $name    = $missing.Info.Script -replace '\.ps1$','' -replace '^g-',''
    Write-Host ("gitbox: flag '$($missing.Flag)' ($name) needs an argument -- " +
                "$($argSteps.Count) required, $argCount provided")
    exit 1
}

# --- Execute mutating steps ---
$argQueue = [System.Collections.Generic.Queue[string]]::new()
if ($Rest) { foreach ($a in $Rest) { $argQueue.Enqueue($a) } }

$mutating = @($steps | Where-Object { $_.Flag -cmatch '[a-z]' })
$ran      = [System.Collections.Generic.List[string]]::new()

# --- Track B: matrix pre-check — skip flags whose work is already done ---
$skippableFlags = @('b','c','u','o','x')
$skipFlags = @{}
$skipReasons = @{
    'b' = 'already on feature branch'
    'c' = 'nothing to commit'
    'u' = 'no unpushed commits'
    'o' = 'PR already open'
    'x' = 'checks not failing'
}
if (@($mutating | Where-Object { $_.Flag -in $skippableFlags }).Count -gt 0) {
    $scanOut = & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') 2>$null 6>&1
    $hashRaw = ($scanOut | Where-Object { "$_" -match '^[BFW]\|' }) | Select-Object -First 1
    if ($hashRaw -and "$hashRaw" -match '^([BFW])\|([^|]+)\|a\d+\|b\d+\|([PU])\|(PR[-DXOA]+)$') {
        $hClass = $Matches[1]; $hDirty = $Matches[2]; $hPush = $Matches[3]; $hPR = $Matches[4]
        $skipFlags['b'] = ($hClass -eq 'F')
        $skipFlags['c'] = ($hDirty -eq 'c')
        $skipFlags['u'] = ($hPush  -eq 'P')
        $skipFlags['o'] = ($hPR -in @('PRO','PRA'))
        $skipFlags['x'] = ($hPR -ne 'PRX')
    }
}

foreach ($step in $mutating) {
    $flag   = $step.Flag
    $script = Join-Path $PSScriptRoot $step.Info.Script
    $name   = $step.Info.Script -replace '\.ps1$','' -replace '^g-',''

    if ($skipFlags.ContainsKey($flag) -and $skipFlags[$flag]) {
        Write-Host "skip $flag ($name): $($skipReasons[$flag])"
        $ran.Add($flag)
        continue
    }

    $forceArg = if ($step.Info.Force) { @{ Force = $true } } else { @{} }
    if ($step.Info.NeedsArg -eq $true) {
        $argQueue.Dequeue() | & $script @forceArg
    } elseif ($step.Info.NeedsArg -eq 'optional' -and $argQueue.Count -gt 0) {
        $argQueue.Dequeue() | & $script @forceArg
    } else {
        & $script @forceArg
    }

    $ran.Add($flag)

    if ($LASTEXITCODE -ne 0) {
        $notRun    = @($mutating | Where-Object { $_.Flag -notin $ran.ToArray() }) | ForEach-Object { $_.Flag }
        $notRunStr = if ($notRun) { " |not run: $($notRun -join '')" } else { '' }
        Write-Host "gitbox $($Spec): step $flag ($name) failed"
        Write-Host "halted at $flag$notRunStr"
        exit $LASTEXITCODE
    }
}

# --- Execute diagnostic steps ---
$diag = @($steps | Where-Object { $_.Flag -cmatch '[A-Z]' })
foreach ($step in $diag) {
    switch ($step.Flag) {
        'W' {
            Write-Host 'Workflow registry:'
            foreach ($wfName in $WorkflowRegistry.Keys) {
                $wFlags  = $WorkflowRegistry[$wfName]
                $allCaps = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($f in $wFlags.ToCharArray()) {
                    $si = $FlagMap["$f"]
                    if ($si.Script) {
                        $sp = Join-Path $PSScriptRoot $si.Script
                        if (Test-Path $sp) {
                            foreach ($cap in (Get-ScriptCapabilities -Path $sp)) { [void]$allCaps.Add($cap) }
                        }
                    }
                }
                $covers = foreach ($dim in ($GapRequirements.Keys | Sort-Object)) {
                    $req = $GapRequirements[$dim]
                    if (@($req | Where-Object { $_ -in $allCaps }).Count -eq $req.Count) { $dim }
                }
                $capsStr   = if ($allCaps.Count) { ($allCaps | Sort-Object) -join ' ' } else { '(none)' }
                $coversStr = if ($covers)         { $covers -join ' '                 } else { '(none)' }
                Write-Host ("  {0,-8} = {1,-6}  caps: {2}" -f $wfName, $wFlags, $capsStr)
                Write-Host ("  {0,-8}   {1,-6}  covers: {2}" -f '', '', $coversStr)
            }
        }
        'O' {
            $scripts = Get-ChildItem -Path $PSScriptRoot -Filter 'g-*.ps1' |
                Where-Object { $_.Name -notin 'g-capabilities.ps1','g-error-vectors.ps1','g-registry.ps1' } |
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
        }
        default {
            & (Join-Path $PSScriptRoot $step.Info.Script)
        }
    }
}
exit 0
