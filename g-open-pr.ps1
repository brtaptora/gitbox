param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Title,

    [string]$Body = ""
)

begin {
    . (Join-Path $PSScriptRoot 'g-registry.ps1')
}

process {
    $repo = Get-Location

    $remote = git -C $repo remote get-url origin 2>$null
    if ($remote -notmatch '[/@]github\.com[:/]') {
        Write-Host "remote is not GitHub: $remote"; exit 1
    }

    $repoName   = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    $branch     = git -C $repo branch --show-current 2>$null
    $baseBranch = (Get-GitboxConfig -RepoPath $repo).BaseBranch

    $existing = gh pr list --repo $repoName --head $branch --json number,url 2>$null | ConvertFrom-Json
    if ($existing -and $existing.Count -gt 0) {
        Write-Host "PR #$($existing[0].number) already open |$($existing[0].url)"
        exit 0
    }

    $bodyValue = if ($Body) { $Body } else { "" }
    $url = gh pr create --repo $repoName --title $Title --base $baseBranch --body $bodyValue 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "pr create failed"; exit 1 }
    $number = $url -replace ".*/pull/", ""

    Write-Host "PR #$number opened |$url"
    exit 0
}
