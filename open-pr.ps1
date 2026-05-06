param(
    [Parameter(ValueFromPipeline, Mandatory)]
    [string]$Title,

    [string]$Body = ""
)

process {
    $repo = Get-Location

    $remote = git -C $repo remote get-url origin 2>$null
    if ($remote -notmatch "brtaptora/") {
        Write-Host "wrong remote: $remote"; exit 1
    }

    $repoName = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    $branch   = git -C $repo branch --show-current 2>$null

    $prArgs = @("pr", "create", "--repo", $repoName, "--title", $Title, "--base", "production")
    if ($Body) {
        $prArgs += @("--body", $Body)
    } else {
        $prArgs += @("--body", "")
    }

    $url = gh @prArgs 2>$null
    $number = $url -replace ".*/pull/", ""

    Write-Host "PR #$number opened · $url"
}
