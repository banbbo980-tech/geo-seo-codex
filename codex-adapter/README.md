# Codex adapter for geo-seo-claude

This directory integrates the canonical upstream toolkit with Codex without changing any upstream-owned file.

The author-provided Windows installer remains authoritative for the Claude installation under `~/.claude`. Codex sees those exact installed skill directories through Windows junctions under `~/.agents/skills`. Thin Codex agent wrappers under `~/.codex/agents` point back to the original Markdown agent prompts.

## First-time install or repair

Run from PowerShell in the repository root:

```powershell
.\codex-adapter\install-codex.ps1
```

This creates or verifies the Codex skill junctions, agent wrappers, minimal global compatibility instructions, and the isolated Python environment at `~/.claude/skills/geo/.venv`.

## Check for expert updates

```powershell
.\codex-adapter\check-upstream.ps1
```

This fetches `upstream/main` and reports SHAs, new commits, and changed files. It does not change branches or working files.

## Install/sync expert updates

```powershell
.\codex-adapter\sync-upstream.ps1
```

This updates `upstream-main`, safely merges it into `main`, reruns the original Windows installer, repairs/verifies the Codex integration, commits the sync, and atomically pushes both branches to `origin`. A merge conflict is reported and aborted; the script never guesses.

## Verification

```powershell
.\codex-adapter\verify-integrity.ps1
.\codex-adapter\verify-install.ps1
```

The first command verifies that every upstream-owned tracked file still matches `upstream-main` byte-for-byte. The second validates junctions, wrappers, installed copies, schemas/templates, Python dependencies, original scripts, and upstream tests.

## Using the toolkit

In any Codex project, invoke the main skill by name, for example:

```text
$geo quick https://example.com
```

You can also invoke any installed specialist skill directly, such as `$geo-citability`, `$geo-schema`, or `$geo-technical`.
