. (Join-Path $PSScriptRoot 'g-registry.ps1')

$repo    = Get-Location
$cfgPath = Join-Path $repo '.gitbox.json'

if (Test-Path $cfgPath) {
    $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $isInteractive) {
        Write-Host "config already exists at .gitbox.json — delete it first or edit manually"
        exit 1
    }
    try {
        $answer = Read-Host "config already exists at .gitbox.json -- overwrite? [y/N]"
    } catch {
        Write-Host "config already exists at .gitbox.json — delete it first or edit manually"
        exit 1
    }
    if ($answer -notmatch '^[yY]$') {
        Write-Host "init: aborted"
        exit 0
    }
}

$detectedDefault = gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null
if (-not $detectedDefault) { $detectedDefault = 'main' }

function Read-WithDefault {
    param([string]$Prompt, [string]$Default)
    try {
        $v = Read-Host "$Prompt [$Default]"
    } catch {
        return $Default
    }
    if (-not $v) { return $Default }
    return $v
}

$baseBranch    = Read-WithDefault "Base branch" $detectedDefault
$defaultBranch = Read-WithDefault "Default branch (Enter if same as base)" $baseBranch
$strategy      = Read-WithDefault "Merge strategy [merge/squash/rebase]" "merge"
try {
    $editorAnswer = Read-Host "Open editor for commit/PR messages? [y/N]"
} catch {
    $editorAnswer = 'n'
}
$editor = $editorAnswer -match '^[yY]$'
$postMerge = Read-WithDefault "After merge, go to [wip/base/stack]" "wip"

$cfg = [ordered]@{ BaseBranch = $baseBranch; MergeStrategy = $strategy.ToLower(); Editor = $editor; PostMerge = $postMerge.ToLower() }
if ($defaultBranch -ne $baseBranch) { $cfg['DefaultBranch'] = $defaultBranch }

$cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
Write-Host "wrote .gitbox.json"
exit 0
