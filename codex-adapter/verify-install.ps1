[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$userHomePath = [Environment]::GetFolderPath('UserProfile')
$claudeRoot = Join-Path $userHomePath '.claude'
$claudeSkills = Join-Path $claudeRoot 'skills'
$codexSkills = Join-Path $userHomePath '.agents\skills'
$codexAgents = Join-Path $userHomePath '.codex\agents'
$venvPython = Join-Path $claudeSkills 'geo\.venv\Scripts\python.exe'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-SameFile {
    param([string]$Expected, [string]$Actual)
    Assert-True (Test-Path -LiteralPath $Expected -PathType Leaf) "Missing source file: $Expected"
    Assert-True (Test-Path -LiteralPath $Actual -PathType Leaf) "Missing installed file: $Actual"
    $expectedHash = (Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash
    $actualHash = (Get-FileHash -LiteralPath $Actual -Algorithm SHA256).Hash
    Assert-True ($expectedHash -eq $actualHash) "Installed canonical file was changed: $Actual"
}

function Get-RelativeChildPath {
    param([string]$BasePath, [string]$ChildPath)
    $separator = [IO.Path]::DirectorySeparatorChar
    $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd([char[]]@('\', '/')) + $separator
    $childFull = [IO.Path]::GetFullPath($ChildPath)
    Assert-True ($childFull.StartsWith($baseFull, [StringComparison]::OrdinalIgnoreCase)) "Path is outside expected root: $childFull"
    return $childFull.Substring($baseFull.Length)
}

$skillNames = @('geo') + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'skills') -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
foreach ($skillName in $skillNames) {
    $source = Join-Path $claudeSkills $skillName
    $link = Join-Path $codexSkills $skillName
    $item = Get-Item -LiteralPath $link -Force
    $expectedTarget = [IO.Path]::GetFullPath($source).TrimEnd('\')
    $actualTargets = @($item.Target | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    Assert-True ($item.LinkType -eq 'Junction' -and $actualTargets -contains $expectedTarget) "Invalid skill junction: $link"
    $repoSkill = if ($skillName -eq 'geo') { Join-Path $repoRoot 'geo\SKILL.md' } else { Join-Path $repoRoot "skills\$skillName\SKILL.md" }
    Assert-SameFile $repoSkill (Join-Path $source 'SKILL.md')
}

$copyGroups = @(
    @{ Source = 'scripts'; Destination = 'skills\geo\scripts' },
    @{ Source = 'schema'; Destination = 'skills\geo\schema' },
    @{ Source = 'templates'; Destination = 'skills\geo\templates' },
    @{ Source = 'agents'; Destination = 'agents' }
)
foreach ($group in $copyGroups) {
    $sourceRoot = Join-Path $repoRoot $group.Source
    foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File) {
        $relative = Get-RelativeChildPath $sourceRoot $sourceFile.FullName
        Assert-SameFile $sourceFile.FullName (Join-Path (Join-Path $claudeRoot $group.Destination) $relative)
    }
}

$originalAgents = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'agents') -Filter '*.md' -File | Sort-Object Name)
foreach ($agent in $originalAgents) {
    $wrapper = Join-Path $codexAgents ($agent.BaseName + '.toml')
    Assert-True (Test-Path -LiteralPath $wrapper -PathType Leaf) "Missing Codex agent wrapper: $wrapper"
    $wrapperText = Get-Content -LiteralPath $wrapper -Raw
    Assert-True ($wrapperText.Contains(".claude/agents/$($agent.Name)")) "Wrapper does not point to its canonical agent: $wrapper"
}

Assert-True (Test-Path -LiteralPath $venvPython -PathType Leaf) "Missing Python environment: $venvPython"

$syntaxCheck = @'
import ast, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = sorted(root.rglob('*.py'))
for path in files:
    ast.parse(path.read_text(encoding='utf-8-sig'), filename=str(path))
print(f'Parsed {len(files)} original Python files')
'@
& $venvPython -B -c $syntaxCheck (Join-Path $claudeSkills 'geo\scripts')
if ($LASTEXITCODE -ne 0) { throw 'Original Python syntax verification failed.' }

$moduleCheck = "import bs4, requests, lxml, PIL, playwright, validators, flask, rich; print('Python dependencies import successfully')"
& $venvPython -B -c $moduleCheck
if ($LASTEXITCODE -ne 0) { throw 'Python dependency import verification failed.' }

$safeCheck = @'
import pathlib, sys
scripts = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(scripts))
import fetch_page, citability_scorer, brand_scanner, llmstxt_generator, crm_dashboard
result = fetch_page.fetch_page('file:///codex-offline-check')
assert result['errors'] and result['status_code'] is None
score = citability_scorer.score_passage('Generative engine optimization improves machine-readable content with clear facts and definitions.', 'What is GEO?')
assert isinstance(score, dict)
print('Original script imports and offline checks passed')
'@
& $venvPython -B -c $safeCheck (Join-Path $claudeSkills 'geo\scripts')
if ($LASTEXITCODE -ne 0) { throw 'Original script offline verification failed.' }

& $venvPython -B -m pytest (Join-Path $repoRoot 'tests') -q
if ($LASTEXITCODE -ne 0) { throw 'Upstream tests failed.' }

$playwrightBrowsers = (& $venvPython -m playwright install --list | Out-String)
Assert-True ($playwrightBrowsers -match 'chromium-') 'Playwright Chromium is not installed.'

$pandocCandidates = @(
    (Get-Command pandoc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Pandoc\pandoc.exe'),
    'C:\Program Files\Pandoc\pandoc.exe'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
Assert-True (@($pandocCandidates).Count -gt 0) 'Pandoc is not installed.'

$chromeCandidates = @(
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Google\Chrome\Application\chrome.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
Assert-True (@($chromeCandidates).Count -gt 0) 'Google Chrome is not installed.'

foreach ($schema in Get-ChildItem -LiteralPath (Join-Path $claudeSkills 'geo\schema') -Filter '*.json' -File) {
    Get-Content -LiteralPath $schema.FullName -Raw | ConvertFrom-Json | Out-Null
}

Write-Host "Codex skills verified: $($skillNames.Count)"
Write-Host "Codex agents verified: $($originalAgents.Count)"
Write-Host "Python environment: $((Get-Item -LiteralPath $venvPython).FullName)"
Write-Host 'Schemas, templates, Playwright Chromium, Pandoc, and Chrome verified.'
