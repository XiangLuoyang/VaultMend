---
name: loopen
description: Obsidian vault quality audit + auto-fix toolchain (R1-R6). Use when running vault lint, applying loop fixes, batch-fixing broken wikilinks or frontmatter, or reading Loopen run logs.
---

# Loopen Skill

Loopen = Loop Engineering for content vaults. Audits and auto-fixes Obsidian vaults against R1-R6 quality rules.

## What it does

- **R1** Frontmatter completeness (6 required fields)
- **R2** H1 position (must come after `> [!abstract]` callout)
- **R3** Broken wikilinks → `[TODO: 待补 X]`
- **R4** Cross-reference consistency (LLM-judged)
- **R5** UTF-8 BOM detection
- **R6** Semantic consistency (frontmatter ↔ body, LLM-judged)

## When to trigger

Run Loopen when the user:
- asks to "lint the vault" / "scan the vault" / "check for broken links"
- asks to "fix R1 / R2 / R3" / "apply loop fixes" / "auto-fix the vault"
- wants to inspect Loopen run history / progress
- wants to pack Loopen into a skill or upgrade its version

## Tools

Tools live in `scripts/`. All scripts must be **PowerShell 5.1 compatible** (no inline regex options — see `references/powershell-debt.md`).

| Script | Role | Usage |
|--------|------|-------|
| `scripts/phase1-auto.ps1` | Phase 1 vault scanner (R1/R2/R3/R5) | `powershell -File .\scripts\phase1-auto.ps1` |
| `scripts/phase2-batch.ps1` | Phase 2 batch apply (R2/R3/R1 content mode) | `powershell -File .\scripts\phase2-batch.ps1 -Limit 5 -DryRun` |
| `scripts/run-loop.ps1` | Full pipeline (v0.7+ execution_mode aware) | `powershell -File .\scripts\run-loop.ps1 -TaskDir <path> -Action all` |
| `scripts/sanity-check.ps1` | Verify environment + scripts load | `powershell -File .\scripts\sanity-check.ps1` |
| `scripts/phase1_scan.py` | Python scanner (UTF-8 safe) | `python scripts/phase1_scan.py --vault <path>` |
| `scripts/git_utf8.py` | Python git wrapper (PS 5.1 encoding workaround) | `from git_utf8 import *; git_status(...)` |

## execution_mode (v0.7+)

`.looprc.json` `execution.mode` controls how the loop behaves:

| Mode | Behavior |
|------|----------|
| `autonomous` (default) | verifier pass → auto-apply patches → write journal → exit 0 |
| `human-gate` | verifier pass → write summary → exit; human review + manual apply later |

**v0.8.2 multi-task concurrent** (new):
```powershell
# Single task (backward compatible)
run-loop.ps1 -TaskDir <path> -Action all

# Multi-task concurrent (TaskList uses \| separator, PS inter-process arrays are unreliable)
run-loop.ps1 -TaskList "path1\|path2\|path3" -MaxConcurrency 3
```

## R1-R6 rules

| Rule | Description | Auto-fix? |
|------|-------------|-----------|
| R1 | Frontmatter completeness (6 fields) | high risk (LLM-judge) |
| R2 | H1 must come after abstract callout | yes |
| R3 | No broken wikilinks | yes (→ `[TODO: 待补 X]`) |
| R4 | Cross-reference consistency | LLM-judged, 5 exemptions |
| R5 | No UTF-8 BOM | manual (rare) |
| R6 | Semantic consistency | 3-tier confidence LLM judge |

See `references/R1-R6-rules.md` for full definitions.

## PowerShell 5.1 system debt (4 hard rules)

1. **Get-Content reads UTF-8 Chinese as ANSI/GBK** → use `[System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))`
2. **Functions must be at script top** → `[CmdletBinding()]` must precede all function definitions
3. **Set-Location to Chinese paths is fragile** → use `git -C <path> <cmd>` instead
4. **inline regex `(?ms)` is zero-width in PS 5.1** → construct Regex object + named group

See `references/powershell-debt.md` for the full writeup.

## Repository structure

```
Loopen/
├── SKILL.md                      # this file
├── README.md                     # 3-step onboarding
├── LICENSE                       # MIT
├── .looprc.example.json          # copy to .looprc.json + edit vault_path
├── .gitignore                    # excludes _archive/, _log.jsonl, journals/
├── references/
│   ├── R1-R6-rules.md            # rule definitions
│   ├── powershell-debt.md        # PS 5.1 4 hard rules
│   ├── dogfood-results.md        # 9+ targets, 9 versions, 0 false negative
│   ├── r4-llm-judge.md           # R4 5 exemptions
│   └── r6-llm-judge.md           # R6 3-tier confidence
├── scripts/
│   ├── run-loop.ps1              # full pipeline
│   ├── phase1-auto.ps1           # vault scanner
│   ├── phase2-batch.ps1          # batch apply
│   ├── phase1_scan.py            # Python scanner (UTF-8 safe)
│   ├── git_utf8.py               # Python git wrapper
│   └── sanity-check.ps1          # env verification
└── examples/
    └── vault/                    # demo vault for dogfood
        ├── good-doc.md           # R1-R6 clean
        ├── missing-frontmatter.md  # R1 violation
        ├── h1-before-abstract.md   # R2 violation
        └── broken-wikilink.md    # R3 violation
```

## Quick start

1. `cp .looprc.example.json .looprc.json`
2. Edit `.looprc.json` → set `defaults.vault_path` to your Obsidian vault
3. `powershell -File .\scripts\sanity-check.ps1` (verify env)
4. `powershell -File .\scripts\phase1-auto.ps1 -DryRun` (preview)
5. `powershell -File .\scripts\phase1-auto.ps1` (real run → generates task dirs in `loopen-tasks/`)
6. `powershell -File .\scripts\run-loop.ps1 -TaskDir <task> -Action all` (apply)

## Loopen vs. Addy Osmani's Loop Engineering (community)

This project is a **coincidental name overlap** with Addy Osmani's 2026 community term for "code-generation loops." Loopen is for **content-quality loops** (vault audit), not code generation.

| Dimension | Community Loop Engineering | Loopen |
|-----------|----------------------------|--------|
| Core scenario | AI writes code overnight | AI audits + fixes vault content |
| Execution unit | Single loop, runs to completion | Multi-task batch (5-phase pipeline per task) |
| Verifier | Test suite | R1-R6 rule checks + R4/R6 LLM judges |
| Stop condition | `--completion-promise` / `--max-iterations` | `max_iter` (placeholder, v1.0 will implement iterative loop) |
| Isolation | git worktree | single task dir + `journal/{task}-{ts}.md` |
| Domain | code / repository | content (Obsidian vault) |

## License

MIT — see `LICENSE`.
