[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    git rev-parse --verify upstream-main 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Branch upstream-main does not exist.' }

    $upstreamFiles = @(git ls-tree -r --name-only upstream-main)
    $errors = [System.Collections.Generic.List[string]]::new()

    $chartName = 'star' + '-history'
    $chartScriptName = 'star' + '_history.py'
    $intentionalProjectFiles = @(
        'README.md',
        ".github/workflows/$chartName.yml",
        ".github/scripts/$chartScriptName",
        "assets/$chartName.svg",
        "assets/$chartName-dark.svg"
    )

    foreach ($path in $upstreamFiles) {
        if ($intentionalProjectFiles -contains $path) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $errors.Add("Missing upstream file: $path")
            continue
        }
        $expected = (git rev-parse "upstream-main:$path").Trim()
        $actual = (git hash-object -- $path).Trim()
        if ($expected -ne $actual) { $errors.Add("Modified upstream file: $path") }
    }

    $allowedExact = @('.github/workflows/codex-upstream-check.yml')
    $allPresent = @()
    $allPresent += @(git ls-files)
    $allPresent += @(git ls-files --others --exclude-standard)
    $allPresent = $allPresent | Where-Object { $_ } | Sort-Object -Unique
    foreach ($path in $allPresent) {
        if ($upstreamFiles -contains $path) { continue }
        if ($path -like 'codex-adapter/*' -or $allowedExact -contains $path) { continue }
        $errors.Add("Unexpected non-adapter file: $path")
    }

    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Error $_ }
        throw 'Original-file integrity verification failed.'
    }

    $verifiedCount = $upstreamFiles.Count - $intentionalProjectFiles.Count
    Write-Host "UPSTREAM SOURCE FILES VERIFIED: $verifiedCount unchanged"
    Write-Host 'AUTHORIZED PROJECT OVERRIDES: README customized; optional popularity chart removed'
    Write-Host 'CODEX ADAPTER FILES: SEPARATE'
    Write-Host "upstream-main: $((git rev-parse upstream-main).Trim())"
} finally {
    Pop-Location
}
