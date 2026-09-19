[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    git rev-parse --verify upstream-main 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Branch upstream-main does not exist.' }

    git fetch upstream main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch upstream/main.' }

    $localSha = (git rev-parse upstream-main).Trim()
    $remoteSha = (git rev-parse upstream/main).Trim()
    $newCount = [int](git rev-list --count "upstream-main..upstream/main")

    Write-Host "Current local upstream SHA:  $localSha"
    Write-Host "Latest remote upstream SHA: $remoteSha"
    Write-Host "New upstream commits:        $newCount"

    if ($newCount -gt 0) {
        Write-Host "`nNew commit messages:"
        git log --oneline --decorate "upstream-main..upstream/main"
        Write-Host "`nChanged files:"
        git diff --name-status upstream-main upstream/main
    } else {
        Write-Host "`nupstream-main is current. No working files or local branches were changed."
    }
} finally {
    Pop-Location
}
