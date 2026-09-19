# Codex adapter

This directory contains the Windows installation, verification, agent-wrapper, and update tools for `banbbo980-tech/geo-seo-codex`.

## Install or repair

Run the toolkit installer first, then the Codex adapter from the repository root:

```powershell
& "C:\Program Files\Git\bin\bash.exe" ./install-win.sh
powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-adapter\install-codex.ps1
```

The adapter connects the installed toolkit to Codex by creating global skill junctions under `%USERPROFILE%\.agents\skills`, custom-agent wrappers under `%USERPROFILE%\.codex\agents`, and a minimal global `%USERPROFILE%\.codex\AGENTS.md`. Python packages are isolated in `%USERPROFILE%\.claude\skills\geo\.venv`.

Restart Codex after the first installation.

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-adapter\verify-install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-adapter\verify-integrity.ps1
```

The verifier checks skills, agents, junction targets, installed files, schemas, templates, Python imports, upstream tests, Playwright Chromium, Pandoc, and Chrome.

## Check for source updates

```powershell
.\codex-adapter\check-upstream.ps1
```

This fetches update metadata and reports the current and latest SHAs, commit messages, and changed files. It does not modify the working tree or branches.

## Synchronize a reviewed update

```powershell
.\codex-adapter\sync-upstream.ps1
```

The sync workflow updates `upstream-main`, merges into `main`, reinstalls the toolkit, verifies the Codex integration, creates a sync commit, and atomically pushes both branches. Any merge conflict is safely aborted for manual review.

## Use in Codex

```text
$geo quick https://example.com
$geo audit https://example.com
$geo report https://example.com
```

See the [main README](../README.md) for the complete command reference, installed skills and agents, reporting workflow, and troubleshooting guide.
