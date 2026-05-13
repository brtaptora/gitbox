# Flag-stack orchestrator. Routes flag sequences to scripts in canonical order.
# Usage: gitbox <flags|workflow> [arg ...] [-AllowWip]
# Flags: b=branch-create r=rename s=sync c=commit u=push o=open-pr x=pr-checks m=merge-rotate z=release
#        H=health Q=status S=matrix-scan B=backlog C=capabilities W=workflow-registry O=optimize X=run-logs
# -AllowWip: skip the wip-branch rename prompt and commit on the wip branch as-is

param(
    [Parameter(Position=0, Mandatory)]
    [string]$Spec,
    [Parameter(ValueFromPipeline)]
    [string]$PipelineArg,
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Rest,
    [switch]$AllowWip
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
$FlagMap['z'] = @{ Script = 'g-release.ps1';        NeedsArg = 'optional' }
$FlagMap['Q'] = @{ Script = 'g-status.ps1';         NeedsArg = $false }
$FlagMap['S'] = @{ Script = 'g-matrix-scan.ps1';    NeedsArg = $false }
$FlagMap['B'] = @{ Script = 'g-backlog.ps1';        NeedsArg = $false }
$FlagMap['C'] = @{ Script = 'g-capabilities.ps1';   NeedsArg = $false }
$FlagMap['W'] = @{ Script = $null;                  NeedsArg = $false }
$FlagMap['O'] = @{ Script = $null;                  NeedsArg = $false }
$FlagMap['H'] = @{ Script = 'g-health.ps1';         NeedsArg = $false }
$FlagMap['X'] = @{ Script = 'g-run-logs.ps1';       NeedsArg = $false }

$CanonicalOrder = [string[]]@('b','r','s','c','u','o','x','m','z','H','Q','S','B','C','W','O','X')

# Resolve workflow name, workflow-prefix+flags compound (e.g. shipX), or raw flag string
$flagStr = if ($WorkflowRegistry.Contains($Spec)) {
    $WorkflowRegistry[$Spec]
} else {
    $matched = $null
    foreach ($wf in ($WorkflowRegistry.Keys | Sort-Object { $_.Length } -Descending)) {
        if ($Spec.StartsWith($wf) -and $Spec.Length -gt $wf.Length) {
            $matched = $WorkflowRegistry[$wf] + $Spec.Substring($wf.Length)
            break
        }
    }
    if ($matched) { $matched } else { $Spec.TrimStart('-') }
}

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
$argCount  = ($Rest ? $Rest.Count : 0) + ($PipelineArg ? 1 : 0)
if ($argCount -lt $argSteps.Count) {
    $missing = $argSteps[$argCount]
    $name    = $missing.Info.Script -replace '\.ps1$','' -replace '^g-',''
    Write-Host ("gitbox: flag '$($missing.Flag)' ($name) needs an argument -- " +
                "$($argSteps.Count) required, $argCount provided")
    exit 1
}

# --- Execute mutating steps ---
$argQueue = [System.Collections.Generic.Queue[string]]::new()
if ($PipelineArg) { $argQueue.Enqueue($PipelineArg) }
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
    $needsPR = @($mutating | Where-Object { $_.Flag -in @('o','x') }).Count -gt 0
    if ($needsPR) { Write-Host "scanning state ..." }
    $scanOut = if ($needsPR) {
        & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') 2>$null 6>&1
    } else {
        & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') -GitOnly 2>$null 6>&1
    }
    $hashRaw = ($scanOut | Where-Object { "$_" -match '^[BFW]\|' }) | Select-Object -First 1
    if ($hashRaw -and "$hashRaw" -match '^([BFW])\|([^|]+)\|a\d+\|b\d+\|([PU])\|(PR[-DXOA]+)$') {
        $hClass = $Matches[1]; $hDirty = $Matches[2]; $hPush = $Matches[3]; $hPR = $Matches[4]
        $skipFlags['b'] = ($hClass -eq 'F')
        $skipFlags['c'] = ($hDirty -eq 'c')
        $skipFlags['u'] = ($hPush  -eq 'P')
        $skipFlags['o'] = ($hPR -in @('PRO','PRA'))
        $skipFlags['x'] = ($hPR -ne 'PRX')

        if ($hClass -eq 'W' -and ($steps | Where-Object { $_.Flag -eq 'c' })) {
            if (-not $AllowWip) {
                $wipBranch = git branch --show-current 2>$null
                $newName = Read-Host "gitbox: on wip branch '$wipBranch'. Enter new branch name (Enter to proceed as wip)"
                if ($newName) {
                    $newName | & (Join-Path $PSScriptRoot 'g-branch-rename.ps1')
                    if ($LASTEXITCODE -ne 0) { Write-Host "gitbox: rename failed"; exit $LASTEXITCODE }
                }
            }
        }
    }
}

# while loop (not foreach) so $i can hold position and retry the failed step after recovery
$i = 0
while ($i -lt $mutating.Count) {
    $step   = $mutating[$i]
    $flag   = $step.Flag
    $script = Join-Path $PSScriptRoot $step.Info.Script
    $name   = $step.Info.Script -replace '\.ps1$','' -replace '^g-',''

    if ($skipFlags.ContainsKey($flag) -and $skipFlags[$flag]) {
        Write-Host "skip $flag ($name): $($skipReasons[$flag])"
        $ran.Add($flag)
        $i++
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

    $stepExit = $LASTEXITCODE
    if ($stepExit -ne 0) {
        # Consult matrix-resolve for a recoverable next action; one attempt per step to prevent loops
        $recovered = $false
        $scanOut   = & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') 2>$null 6>&1
        $hashLine  = ($scanOut | Where-Object { "$_" -match '^[BFW]\|' }) | Select-Object -First 1
        if ($hashLine) {
            $resolveOut = "$hashLine" | & (Join-Path $PSScriptRoot 'g-matrix-resolve.ps1') 6>&1
            $nextLine   = ($resolveOut | Where-Object { "$_" -match '^\s+next:' }) | Select-Object -First 1
            if ($nextLine -and "$nextLine" -match 'gitbox\s+([a-z]+)') {
                $suggestion   = $Matches[1]
                $recovFlagStr = if ($WorkflowRegistry.Contains($suggestion)) { $WorkflowRegistry[$suggestion] } else { $suggestion }
                $recoveryFlag = [string]($recovFlagStr.ToCharArray() |
                    Where-Object { $FlagMap.Contains([string]$_) -and [string]$_ -notin $ran.ToArray() } |
                    Select-Object -First 1)
                if ($recoveryFlag) {
                    $rInfo = $FlagMap[$recoveryFlag]
                    $rName = $rInfo.Script -replace '\.ps1$','' -replace '^g-',''
                    Write-Host "  matrix suggests: $("$nextLine".Trim())"
                    $answer = Read-Host "  run $recoveryFlag ($rName) to recover? [Y/n]"
                    if ($answer -eq '' -or $answer -match '^[Yy]') {
                        $rScript = Join-Path $PSScriptRoot $rInfo.Script
                        if ($rInfo.NeedsArg -eq $true) {
                            $rArg = Read-Host "  arg for $recoveryFlag ($rName)"
                            $rArg | & $rScript
                        } else {
                            & $rScript
                        }
                        if ($LASTEXITCODE -eq 0) {
                            $recovered = $true
                            $ran.Add($recoveryFlag)
                            Write-Host "  recovered -- retrying $flag ($name)"
                        }
                    }
                }
            }
        }

        if (-not $recovered) {
            $notRun    = @($mutating | Where-Object { $_.Flag -notin $ran.ToArray() -and $_.Flag -ne $flag }) | ForEach-Object { $_.Flag }
            $notRunStr = if ($notRun) { " |not run: $($notRun -join '')" } else { '' }
            Write-Host "gitbox $($Spec): step $flag ($name) failed"
            Write-Host "halted at $flag$notRunStr"
            exit $stepExit
        }
        # $i intentionally not advanced — retry the failed step on next iteration
        continue
    }

    $ran.Add($flag)
    $i++
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
        'O' { & (Join-Path $PSScriptRoot 'g-optimization.ps1') }
        default {
            & (Join-Path $PSScriptRoot $step.Info.Script)
        }
    }
}
exit 0
