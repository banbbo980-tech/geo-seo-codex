[CmdletBinding()]
param(
    [switch]$SkipPython,
    [switch]$SkipPlaywright
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$userHomePath = [Environment]::GetFolderPath('UserProfile')
$claudeSkills = Join-Path $userHomePath '.claude\skills'
$codexSkills = Join-Path $userHomePath '.agents\skills'
$codexAgents = Join-Path $userHomePath '.codex\agents'
$codexHome = Join-Path $userHomePath '.codex'
$globalInstructions = Join-Path $codexHome 'AGENTS.md'

function Assert-SameFile {
    param([string]$Expected, [string]$Actual)
    if (-not (Test-Path -LiteralPath $Expected -PathType Leaf)) { throw "Missing source file: $Expected" }
    if (-not (Test-Path -LiteralPath $Actual -PathType Leaf)) { throw "Missing installed file: $Actual" }
    $expectedHash = (Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash
    $actualHash = (Get-FileHash -LiteralPath $Actual -Algorithm SHA256).Hash
    if ($expectedHash -ne $actualHash) { throw "Canonical file differs from upstream source: $Actual" }
}

function Ensure-Junction {
    param([string]$Path, [string]$Target)
    $resolvedTarget = [IO.Path]::GetFullPath($Target).TrimEnd('\')
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        $targets = @($item.Target | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
        if ($item.LinkType -ne 'Junction' -or $targets -notcontains $resolvedTarget) {
            throw "Refusing to replace existing non-matching path: $Path"
        }
        Write-Host "Verified junction: $Path -> $resolvedTarget"
        return
    }
    New-Item -ItemType Junction -Path $Path -Target $resolvedTarget | Out-Null
    Write-Host "Created junction:  $Path -> $resolvedTarget"
}

New-Item -ItemType Directory -Force -Path $codexSkills, $codexAgents, $codexHome | Out-Null

$skillNames = @('geo') + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'skills') -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
foreach ($skillName in $skillNames) {
    $source = Join-Path $claudeSkills $skillName
    if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) {
        throw "Original installed skill is missing: $source. Run install-win.sh first."
    }
    $repoSkill = if ($skillName -eq 'geo') { Join-Path $repoRoot 'geo\SKILL.md' } else { Join-Path $repoRoot "skills\$skillName\SKILL.md" }
    Assert-SameFile -Expected $repoSkill -Actual (Join-Path $source 'SKILL.md')
    Ensure-Junction -Path (Join-Path $codexSkills $skillName) -Target $source
}

foreach ($wrapper in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'agents') -Filter '*.toml' -File) {
    $destination = Join-Path $codexAgents $wrapper.Name
    if (Test-Path -LiteralPath $destination) {
        $existing = Get-Content -LiteralPath $destination -Raw
        $expected = Get-Content -LiteralPath $wrapper.FullName -Raw
        if ($existing -ne $expected) {
            $canonicalReference = ".claude/agents/$($wrapper.BaseName).md"
            $isManagedWrapper = $existing.Contains('# geo-seo-codex-adapter') -or $existing.Contains($canonicalReference)
            if (-not $isManagedWrapper) { throw "Refusing to overwrite a different Codex agent file: $destination" }
            Copy-Item -LiteralPath $wrapper.FullName -Destination $destination -Force
        }
    } else {
        Copy-Item -LiteralPath $wrapper.FullName -Destination $destination
    }
    Write-Host "Verified agent wrapper: $destination"
}

$globalSource = Join-Path $PSScriptRoot 'global-AGENTS.md'
if (Test-Path -LiteralPath $globalInstructions) {
    $existingGlobal = Get-Content -LiteralPath $globalInstructions -Raw
    $expectedGlobal = Get-Content -LiteralPath $globalSource -Raw
    if ($existingGlobal -ne $expectedGlobal) {
        if (-not $existingGlobal.Contains('<!-- geo-seo-codex-adapter -->')) {
            throw "Refusing to overwrite existing global Codex instructions: $globalInstructions"
        }
        Copy-Item -LiteralPath $globalSource -Destination $globalInstructions -Force
    }
} else {
    Copy-Item -LiteralPath $globalSource -Destination $globalInstructions
}
Write-Host "Verified global compatibility instructions: $globalInstructions"

$venvPath = Join-Path $claudeSkills 'geo\.venv'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
if (-not $SkipPython) {
    $pythonCommand = Get-Command python -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        & $pythonCommand.Source -m venv $venvPath
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create the isolated Python environment.' }
    }
    & $venvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upgrade pip in the isolated environment.' }
    & $venvPython -m pip install -r (Join-Path $repoRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install the canonical Python requirements.' }
    & $venvPython -m pip install pytest
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install the test-only pytest dependency.' }
    if (-not $SkipPlaywright) {
        & $venvPython -m playwright install chromium
        if ($LASTEXITCODE -ne 0) { throw 'Failed to install Playwright Chromium.' }
    }
    Write-Host "Verified isolated Python environment: $venvPath"
}

$pandocCandidates = @(
    (Get-Command pandoc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Pandoc\pandoc.exe'),
    'C:\Program Files\Pandoc\pandoc.exe'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
if (-not $pandocCandidates) {
    $winget = Get-Command winget -ErrorAction Stop
    & $winget.Source install --id JohnMacFarlane.Pandoc --exact --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install Pandoc, which the canonical PDF-report skill requires.' }
}

& (Join-Path $PSScriptRoot 'verify-install.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Codex integration verification failed.' }

Write-Host "Codex integration installed: $($skillNames.Count) skills and $((Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'agents') -Filter '*.toml').Count) agents."
