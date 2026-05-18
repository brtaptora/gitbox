# Flag-stack orchestrator. Routes flag sequences to scripts in canonical order.
# Usage: gitbox <flags|workflow> [arg ...] [-AllowWip]
# Flags: b=branch-create r=rename s=sync c=commit v=revert u=push o=open-pr x=pr-checks m=merge-rotate g=branch-base z=release
#        H=health Q=status L=log D=diff P=pr-view
#        S=matrix-scan B=backlog C=capabilities W=workflow-registry O=optimize X=run-logs
# -AllowWip: skip the wip-branch rename prompt and commit on the wip branch as-is

param(
    [Parameter(Position=0)]
    [string]$Spec = '',
    [Parameter(ValueFromPipeline)]
    [string]$PipelineArg,
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Rest,
    [switch]$AllowWip
)

. (Join-Path $PSScriptRoot 'g-error-vectors.ps1')
. (Join-Path $PSScriptRoot 'g-spinner.ps1')

$_e = [char]27
$_d  = "${_e}[2m";  $_b  = "${_e}[1m"
$_cy = "${_e}[36m"; $_gn = "${_e}[32m"
$_yw = "${_e}[33m"; $_rd = "${_e}[31m"
$_rs = "${_e}[0m"
if ([Console]::IsOutputRedirected) { $_d=''; $_b=''; $_cy=''; $_gn=''; $_yw=''; $_rd=''; $_rs='' }

function Show-GitboxHelp {
    Write-Host ""
    Write-Host "  ${_b}${_cy}gitbox${_rs}  git workflow automation"
    Write-Host ""
    Write-Host "  ${_b}${_yw}USAGE${_rs}"
    Write-Host "    gitbox ${_cy}<flags|workflow>${_rs} [args] [-AllowWip]"
    Write-Host "    gb     ${_cy}<flags|workflow>${_rs} [args] [-AllowWip]"
    Write-Host ""
    Write-Host "  ${_b}${_yw}FLAGS${_rs}  ${_d}mutating, run in pipeline order${_rs}"
    @(
        'b|branch-create|<name>|Create a feature branch from base'
        'r|branch-rename|<name>|Rename current branch'
        's|branch-sync||Fetch and rebase onto base'
        'c|commit-push|[message]|Stage all, commit, and push'
        'v|revert|[ref]|Revert a commit (default: HEAD)'
        'u|push||Push unpushed commits'
        'o|open-pr|[title]|Open a PR against the base branch'
        'x|pr-checks||Check CI status'
        'm|merge-rotate|[name]|Merge PR, delete branch, create next'
        'g|branch-base||Checkout base branch and pull'
        'k|branch-checkout|<name>|Checkout any named branch with stash-and-pop'
        'n|unstack||Merge the full stacked PR chain bottom-to-top'
        'z|release|[version]|Tag and push; promotes develop to main first if applicable'
    ) | ForEach-Object {
        $p = $_ -split '\|', 4
        Write-Host ("    ${_cy}{0}${_rs}  {1,-14}  {2,-10}  {3}" -f $p[0], $p[1], $p[2], $p[3])
    }
    Write-Host ""
    Write-Host "  ${_d}       diagnostic${_rs}"
    @(
        'H|health|Unified health report'
        'Q|status|One-line repo status'
        'L|log|Commits ahead of base'
        'D|diff|Changed files and line counts'
        'P|pr-view|PR detail: title, state, reviews, checks'
        'S|matrix-scan|State hash and recommended next action'
        'B|backlog|360-combination gap sweep'
        'C|capabilities|Script coverage scores'
        'W|workflow-registry|Named workflows with capabilities'
        'O|optimization|Capability density per script'
        'X|run-logs|Most recent CI run logs'
        'T|stack|Stack topology: branch chain, PR numbers, CI status'
    ) | ForEach-Object {
        $p = $_ -split '\|', 3
        Write-Host ("    ${_cy}{0}${_rs}  {1,-20}  {2}" -f $p[0], $p[1], $p[2])
    }
    Write-Host ""
    Write-Host "  ${_b}${_yw}WORKFLOWS${_rs}"
    @(
        'start|b|Beginning a new ticket from the base branch'
        'rename|r|Promoting a wip branch before opening a PR'
        'sync|s|Branch is behind base'
        'commit|c|Saving incremental progress on an open PR'
        'push|u|Pushing commits made outside gitbox'
        'pr|o|Opening a PR on an already-pushed branch'
        'checks|x|Inspecting CI status'
        'merge|m|Merging an approved PR'
        'revert|v|Undoing a commit'
        'promote|rcuo|Promote a wip branch to a feature branch with a PR'
        'base|g|Return to base branch after merge or before release'
        'checkout|k|Switch to any named branch with stash-and-pop'
        'unstack|n|Merge the full stacked PR chain bottom-to-top'
        'stack|T|Show current stack topology'
        'submit|cuo|Commit, push, and open PR — stop before merge'
        'land|cxm|Final commit on a branch with an open PR'
        'ship|xm|Merging a clean, already-committed branch'
        'full|cuoxm|One-shot from commit through merge'
        'release|z|Promoting develop to main with a version tag'
    ) | ForEach-Object {
        $p = $_ -split '\|', 3
        Write-Host ("    ${_cy}{0,-8}${_rs}  ${_b}{1,-6}${_rs}  {2}" -f $p[0], $p[1], $p[2])
    }
    Write-Host ""
    Write-Host "  ${_b}${_yw}EXAMPLES${_rs}"
    @(
        'gitbox b "feat/my-feature"|create a feature branch'
        'gitbox c "fix the thing"|commit all changes'
        'gitbox co "fix the thing" "Fix the thing"|commit and open PR'
        'gitbox land "fix the thing"|commit, check CI, merge'
        'gitbox ship|check CI and merge'
    ) | ForEach-Object {
        $p = $_ -split '\|', 2
        Write-Host ("    ${_gn}{0,-46}${_rs}  ${_d}{1}${_rs}" -f $p[0], $p[1])
    }
    Write-Host ""
}

if (-not $Spec -or $Spec -in @('--help', '-h', '-?', 'help')) { Show-GitboxHelp; exit 0 }
if ($Spec -eq 'init') { & (Join-Path $PSScriptRoot 'g-init.ps1'); exit $LASTEXITCODE }
if ($Spec -in @('--version', 'version')) {
    $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'gitbox.psd1')
    Write-Host "gitbox $($manifest.ModuleVersion)"
    exit 0
}

# Case-sensitive: lowercase=mutating, uppercase=diagnostic; 's' and 'S' are distinct keys
$FlagMap = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
$FlagMap['b'] = @{ Script = 'g-branch-create.ps1';  NeedsArg = $true;  Force = $true; Switches = @('Stack') }
$FlagMap['r'] = @{ Script = 'g-branch-rename.ps1';  NeedsArg = $true  }
$FlagMap['s'] = @{ Script = 'g-branch-sync.ps1';    NeedsArg = $false }
$FlagMap['c'] = @{ Script = 'g-commit-push.ps1';    NeedsArg = 'optional'; Switches = @('Amend') }
$FlagMap['v'] = @{ Script = 'g-revert.ps1';         NeedsArg = 'optional' }
$FlagMap['u'] = @{ Script = 'g-push.ps1';           NeedsArg = $false }
$FlagMap['o'] = @{ Script = 'g-open-pr.ps1';        NeedsArg = 'optional'; Switches = @('Draft') }
$FlagMap['x'] = @{ Script = 'g-pr-checks.ps1';      NeedsArg = $false }
$FlagMap['m'] = @{ Script = 'g-merge-rotate.ps1';   NeedsArg = 'optional'; Switches = @('Squash','Rebase') }
$FlagMap['g'] = @{ Script = 'g-branch-base.ps1';    NeedsArg = $false; Switches = @('NoStashPop') }
$FlagMap['k'] = @{ Script = 'g-branch-checkout.ps1'; NeedsArg = $true }
$FlagMap['n'] = @{ Script = 'g-unstack.ps1';         NeedsArg = $false; Switches = @('Force','DryRun','Quiet') }
$FlagMap['z'] = @{ Script = 'g-release.ps1';        NeedsArg = 'optional'; Switches = @('View') }
$FlagMap['Q'] = @{ Script = 'g-status.ps1';         NeedsArg = $false }
$FlagMap['S'] = @{ Script = 'g-matrix-scan.ps1';    NeedsArg = $false }
$FlagMap['B'] = @{ Script = 'g-backlog.ps1';        NeedsArg = $false }
$FlagMap['C'] = @{ Script = 'g-capabilities.ps1';   NeedsArg = $false }
$FlagMap['W'] = @{ Script = $null;                  NeedsArg = $false }
$FlagMap['O'] = @{ Script = $null;                  NeedsArg = $false }
$FlagMap['H'] = @{ Script = 'g-health.ps1';         NeedsArg = $false }
$FlagMap['L'] = @{ Script = 'g-log.ps1';            NeedsArg = $false }
$FlagMap['D'] = @{ Script = 'g-diff.ps1';           NeedsArg = $false }
$FlagMap['P'] = @{ Script = 'g-pr-view.ps1';        NeedsArg = $false }
$FlagMap['X'] = @{ Script = 'g-run-logs.ps1';       NeedsArg = $false }
$FlagMap['T'] = @{ Script = 'g-stack.ps1';          NeedsArg = $false }

$CanonicalOrder = [string[]]@('b','r','s','c','v','u','o','x','m','g','k','n','z','H','Q','L','D','P','S','B','C','W','O','X','T')

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
        $flip = if ([char]::IsUpper($ch)) { [string][char]::ToLower($ch) } else { [string][char]::ToUpper($ch) }
        $hint = if ($FlagMap.Contains($flip)) { " (did you mean '$flip'?)" } else { '' }
        Write-Host "gitbox: unknown flag '$ch'${hint} -- valid flags: $($FlagMap.Keys -join '')"
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
$posArgs  = if ($Rest) { @($Rest | Where-Object { "$_" -notmatch '^-' }) } else { @() }
$argCount  = $posArgs.Count + ($PipelineArg ? 1 : 0)
if ($argCount -lt $argSteps.Count) {
    $missing = $argSteps[$argCount]
    $name    = $missing.Info.Script -replace '\.ps1$','' -replace '^g-',''
    Write-Host ("gitbox: flag '$($missing.Flag)' ($name) needs an argument -- " +
                "$($argSteps.Count) required, $argCount provided")
    exit 1
}

# --- Execute mutating steps ---
$argQueue    = [System.Collections.Generic.Queue[string]]::new()
$restSwitches = @{}
if ($PipelineArg) { $argQueue.Enqueue($PipelineArg) }
if ($Rest) {
    foreach ($a in $Rest) {
        if ("$a" -match '^-([A-Za-z]\w*)$') { $restSwitches[$Matches[1]] = $true }
        else { $argQueue.Enqueue($a) }
    }
}

$maxConsumable = @($steps | Where-Object { $_.Info.NeedsArg -in @($true, 'optional') }).Count
if ($argQueue.Count -gt $maxConsumable) {
    $tempArr   = $argQueue.ToArray()
    $extraList = for ($qi = $maxConsumable; $qi -lt $tempArr.Count; $qi++) { "'$($tempArr[$qi])'" }
    Write-Host "${_yw}gitbox: warning -- extra arg(s) ignored: $($extraList -join ', ') -- did you forget to quote the full value?${_rs}"
}

$mutating = @($steps | Where-Object { $_.Flag -cmatch '[a-z]' })
$ran      = [System.Collections.Generic.List[string]]::new()

# --- Track B: matrix pre-check — skip flags whose work is already done ---
$skippableFlags = @('b','r','c','u','o','x','g')
$skipFlags = @{}
$skipReasons = @{
    'b' = 'already on feature branch'
    'r' = 'rename only applies to wip branches; use gitbox r standalone to rename any branch'
    'c' = 'nothing to commit'
    'u' = 'no unpushed commits'
    'o' = 'PR already open'
    'x' = 'PR open with passing checks'
    'g' = 'already on base branch'
}
if (@($mutating | Where-Object { $_.Flag -in $skippableFlags }).Count -gt 0) {
    $needsPR = @($mutating | Where-Object { $_.Flag -in @('o','x') }).Count -gt 0
    $spin = Start-Spinner "scanning state"
    $scanOut = if ($needsPR) {
        & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') 2>$null 6>&1
    } else {
        & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') -GitOnly 2>$null 6>&1
    }
    Stop-Spinner $spin
    $hashRaw = ($scanOut | Where-Object { "$_" -match '^[BFW]\|' }) | Select-Object -First 1
    if ($hashRaw -and "$hashRaw" -match '^([BFW])\|([^|]+)\|a\d+\|b\d+\|([PU])\|(PR[-DXOA]+)$') {
        $hClass = $Matches[1]; $hDirty = $Matches[2]; $hPush = $Matches[3]; $hPR = $Matches[4]
        $skipFlags['b'] = ($hClass -eq 'F') -and (-not $restSwitches.ContainsKey('Stack'))
        $skipFlags['r'] = ($hClass -ne 'W') -and ($mutating.Count -gt 1)
        $skipFlags['c'] = ($hDirty -eq 'c')
        $skipFlags['u'] = ($hPush  -eq 'P')
        $skipFlags['o'] = ($hPR -in @('PRO','PRA'))
        $skipFlags['x'] = ($hPR -in @('PRO','PRA'))
        $skipFlags['g'] = ($hClass -eq 'B')

        if ($hClass -eq 'B' -and ($steps | Where-Object { $_.Flag -eq 'c' }) -and -not ($steps | Where-Object { $_.Flag -eq 'b' })) {
            $_gcfg = Get-GitboxConfig
            if ($_gcfg.BaseBranch -ne $_gcfg.DefaultBranch) {
                $baseBranchName = git branch --show-current 2>$null
                Write-Host "gitbox: on base branch '$baseBranchName' -- create a feature branch first"
                Write-Host "  run: gitbox b `"<name>`""
                exit 1
            }
        }

        if ($hClass -eq 'W' -and ($steps | Where-Object { $_.Flag -eq 'c' })) {
            $hasRename = [bool]($steps | Where-Object { $_.Flag -in @('r','b') })
            if (-not $AllowWip -and -not $hasRename) {
                $wipBranch = git branch --show-current 2>$null
                $newName = $null
                try {
                    $newName = Read-Host "gitbox: on wip branch '$wipBranch'. Enter new branch name (Enter to proceed as wip)"
                } catch {
                    Write-Host "gitbox: on wip branch '$wipBranch' -- rename first (gitbox r) or pass -AllowWip to proceed as-is"
                    exit 1
                }
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
        Write-Host "${_d}  skip $flag ($name): $($skipReasons[$flag])${_rs}"
        if ($step.Info.NeedsArg -eq $true -and $argQueue.Count -gt 0) { [void]$argQueue.Dequeue() }
        $ran.Add($flag)
        $i++
        continue
    }

    $forceArg    = if ($step.Info.Force) { @{ Force = $true } } else { @{} }
    $stepSwitches = @{}
    if ($step.Info.Switches) {
        foreach ($sw in $step.Info.Switches) {
            if ($restSwitches.ContainsKey($sw)) { $stepSwitches[$sw] = $true }
        }
    }
    # g followed by z: stash must not be popped onto base — preserve it for the feature branch
    if ($flag -eq 'g' -and ($steps | Where-Object { $_.Flag -eq 'z' })) {
        $stepSwitches['NoStashPop'] = $true
    }
    $splatArgs = $forceArg + $stepSwitches
    $stepLines = [System.Collections.Generic.List[string]]::new()
    if ($step.Info.NeedsArg -eq $true) {
        $rawOut = $argQueue.Dequeue() | & $script @splatArgs 6>&1
    } elseif ($step.Info.NeedsArg -eq 'optional' -and $argQueue.Count -gt 0) {
        $rawOut = $argQueue.Dequeue() | & $script @splatArgs 6>&1
    } else {
        $rawOut = & $script @splatArgs 6>&1
    }
    $rawOut | ForEach-Object { Write-Host "$_"; [void]$stepLines.Add("$_") }

    $stepExit = $LASTEXITCODE
    if ($stepExit -ne 0) {
        # Consult matrix-resolve; each recovered flag is added to $ran so it cannot be reused (loop guard)
        $recovered   = $false
        $stepOut     = $stepLines -join "`n"
        $errorVector = if ($stepOut) { Resolve-OutputToVector -Output $stepOut } else { $null }

        $rSpin    = Start-Spinner "scanning state"
        $scanOut  = & (Join-Path $PSScriptRoot 'g-matrix-scan.ps1') 2>$null 6>&1
        Stop-Spinner $rSpin
        $hashLine = ($scanOut | Where-Object { "$_" -match '^[BFW]\|' }) | Select-Object -First 1
        if ($hashLine) {
            $r = Resolve-MatrixAction -Hash "$hashLine" -ErrorVector $errorVector
            if ($r -and $r.Action) {
                Write-Host "${_yw}  matrix suggests: next: $($r.Action)${_rs}"
                if ($r.Action -match 'gitbox\s+([a-z]+)') {
                    $suggestion   = $Matches[1]
                    $recovFlagStr = if ($WorkflowRegistry.Contains($suggestion)) { $WorkflowRegistry[$suggestion] } else { $suggestion }
                    $recoveryFlag = [string]($recovFlagStr.ToCharArray() |
                        Where-Object { $FlagMap.Contains([string]$_) -and [string]$_ -notin $ran.ToArray() } |
                        Select-Object -First 1)
                    if ($recoveryFlag) {
                        $rInfo   = $FlagMap[$recoveryFlag]
                        $rName   = $rInfo.Script -replace '\.ps1$','' -replace '^g-',''
                        $rScript = Join-Path $PSScriptRoot $rInfo.Script

                        # Interactive: confirm before proceeding (no silent action in attended sessions).
                        # Non-interactive: auto-proceed (no user to ask).
                        $confirmed   = $false
                        $interactive = $false
                        try {
                            $confirm     = Read-Host "  recover with $recoveryFlag ($rName)? [Y/n]"
                            $interactive = $true
                            $confirmed   = ($confirm -eq '' -or $confirm -match '^[Yy]')
                        } catch {
                            $confirmed = $true   # non-interactive: auto-proceed
                        }

                        if (-not $confirmed) {
                            $remaining = (@($mutating | Where-Object { $_.Flag -notin $ran.ToArray() }) | ForEach-Object { $_.Flag }) -join ''
                            Write-Host "${_yw}  recovery skipped -- remaining: $remaining${_rs}"
                        } else {
                            $rSkipped = $false
                            if ($rInfo.NeedsArg -eq $true) {
                                $rArg = $null
                                if ($interactive) {
                                    $rArg = Read-Host "  arg for $recoveryFlag ($rName)"
                                }
                                if ($rArg) {
                                    Write-Host "${_cy}  running $recoveryFlag ($rName) [interactive]${_rs} ..."
                                    $rArg | & $rScript
                                } else {
                                    # Running without a required arg throws ParameterBindingException which does
                                    # not set $LASTEXITCODE, producing a false-positive recovery and a retry loop.
                                    Write-Host "${_yw}  recovery skipped -- $recoveryFlag ($rName) requires an arg${_rs}"
                                    $rSkipped = $true
                                }
                            } else {
                                $modeTag = if ($interactive) { '' } else { ' [non-interactive]' }
                                Write-Host "${_cy}  running $recoveryFlag ($rName)${_rs}${modeTag} ..."
                                & $rScript
                            }
                            if (-not $rSkipped -and $LASTEXITCODE -eq 0) {
                                $recovered = $true
                                $ran.Add($recoveryFlag)
                                Write-Host "${_gn}  recovered -- retrying $flag ($name)${_rs}"
                            }
                        }
                    }
                }
            }
        }

        if (-not $recovered) {
            $notRun    = @($mutating | Where-Object { $_.Flag -notin $ran.ToArray() -and $_.Flag -ne $flag }) | ForEach-Object { $_.Flag }
            $notRunStr = if ($notRun) { " |not run: $($notRun -join '')" } else { '' }
            Write-Host "${_rd}gitbox $($Spec): step $flag ($name) failed${_rs}"
            Write-Host "${_rd}halted at $flag$notRunStr${_rs}"
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
        'H' {
            $switchArgs = @{}
            foreach ($a in $Rest) { if ("$a" -match '^-([A-Za-z]\w*)$') { $switchArgs[$Matches[1]] = $true } }
            & (Join-Path $PSScriptRoot $step.Info.Script) @switchArgs
        }
        default {
            & (Join-Path $PSScriptRoot $step.Info.Script)
        }
    }
}
exit 0
