[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$gitBashCandidates = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files\Git\usr\bin\bash.exe'
)
$gitBash = $gitBashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $gitBash) { throw 'Git Bash was not found. The original Windows installer requires Git Bash.' }

Push-Location $repoRoot
try {
    $branch = (git branch --show-current).Trim()
    if ($branch -ne 'main') { throw "Run this command from branch main (current: $branch)." }
    if (git status --porcelain) { throw 'Working tree is not clean. Commit or stash your work before syncing.' }

    git fetch upstream main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch upstream/main.' }

    $oldSha = (git rev-parse upstream-main).Trim()
    $newSha = (git rev-parse upstream/main).Trim()
    $newCommits = @(git log --oneline "$oldSha..$newSha")

    Write-Host "Local upstream-main: $oldSha"
    Write-Host "Remote upstream/main: $newSha"

    if ($oldSha -eq $newSha) {
        Write-Host 'No new upstream commits. Rechecking the local installation.'
        & $gitBash './install-win.sh'
        if ($LASTEXITCODE -ne 0) { throw 'The original Windows installer failed.' }
        & (Join-Path $PSScriptRoot 'install-codex.ps1') -SkipPlaywright
        if ($LASTEXITCODE -ne 0) { throw 'Codex integration verification failed.' }
        return
    }

    git update-ref refs/heads/upstream-main $newSha
    if ($LASTEXITCODE -ne 0) { throw 'Failed to update upstream-main.' }

    git merge --no-ff --no-commit upstream-main
    if ($LASTEXITCODE -ne 0) {
        $conflicts = @(git diff --name-only --diff-filter=U)
        git merge --abort
        throw "Upstream merge conflict detected and safely aborted. Conflicting files: $($conflicts -join ', ')"
    }

    & $gitBash './install-win.sh'
    if ($LASTEXITCODE -ne 0) {
        git merge --abort
        throw 'The original Windows installer failed; merge was aborted.'
    }

    & (Join-Path $PSScriptRoot 'install-codex.ps1') -SkipPlaywright
    if ($LASTEXITCODE -ne 0) {
        git merge --abort
        throw 'Codex integration verification failed; merge was aborted.'
    }

    & (Join-Path $PSScriptRoot 'verify-integrity.ps1')
    if ($LASTEXITCODE -ne 0) {
        git merge --abort
        throw 'Original-file integrity verification failed; merge was aborted.'
    }

    $shortSha = (git rev-parse --short $newSha).Trim()
    git commit -m "chore: sync upstream $shortSha"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the upstream sync commit.' }

    git push --atomic origin main upstream-main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to push main and upstream-main atomically.' }

    Write-Host "`nUpstream commits added:"
    $newCommits | ForEach-Object { Write-Host $_ }
    Write-Host "`nSynchronization complete at upstream commit $newSha"
} finally {
    Pop-Location
}
