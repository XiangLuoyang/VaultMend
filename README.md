# VaultMend — Obsidian Vault Quality Audit + Auto-Fix

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**VaultMend** = rule-driven vault repair for Obsidian. Audits and auto-fixes vaults against R1-R6 quality rules (frontmatter, H1, broken wikilinks, BOM, semantic consistency). The execution pipeline is borrowed from the Loop Engineering paradigm, but the core value is the R1-R6 rule set, not the loop paradigm itself.

## What it does

| Rule | Description | Auto-fix? |
|------|-------------|-----------|
| R1 | Frontmatter completeness (6 required fields) | High-risk — LLM-judged |
| R2 | H1 must come after `> [!abstract]` callout | Yes |
| R3 | No broken wikilinks (`[[name]]` → `[TODO: 待补 name]`) | Yes |
| R4 | Cross-reference consistency | LLM-judged (5 exemptions) |
| R5 | No UTF-8 BOM | Manual |
| R6 | Semantic consistency (frontmatter ↔ body) | LLM-judged (3-tier confidence) |

## Quick start

```powershell
# 1. Clone
git clone https://github.com/XiangLuoyang/VaultMend.git
cd VaultMend

# 2. Configure
cp .looprc.example.json .looprc.json
# Edit .looprc.json → set defaults.vault_path to your Obsidian vault

# 3. Verify environment
powershell -File .\scripts\sanity-check.ps1

# 4. Scan your vault
powershell -File .\scripts\phase1-auto.ps1 -DryRun   # preview
powershell -File .\scripts\phase1-auto.ps1            # real run

# 5. Apply fixes
powershell -File .\scripts\run-loop.ps1 -TaskDir <task> -Action all
```

See [SKILL.md](SKILL.md) for the full skill definition (OpenClaw skill format).

## Architecture

```
VaultMend/
├── SKILL.md              ← OpenClaw skill entry
├── README.md             ← this file
├── .looprc.example.json  ← config template
├── references/           ← R1-R6 rules + PS5.1 debt + dogfood results
├── scripts/              ← PowerShell 5.1 + Python tools
└── examples/vault/        ← demo vault for dogfood
```

## execution_mode

`.looprc.json` `execution.mode`:

| Mode | Behavior |
|------|----------|
| `autonomous` (default) | verifier pass → auto-apply → journal → exit 0 |
| `human-gate` | verifier pass → write summary → exit; human reviews |

**Multi-task concurrent** (v0.8.2):
```powershell
run-loop.ps1 -TaskList "task1\|task2\|task3" -MaxConcurrency 3
```

## VaultMend vs. community Loop Engineering

Coincidental name overlap with [Addy Osmani's 2026 community term](https://addyosmani.com/blog) for "code-generation loops." VaultMend is for **content-quality loops** (Obsidian vault audit), not code generation.

| Dimension | Community Loop Engineering | VaultMend |
|-----------|---------------------------|--------|
| Core scenario | AI writes code overnight | AI audits + fixes vault content |
| Execution unit | Single loop, runs to completion | Multi-task batch (5-phase pipeline) |
| Verifier | Test suite | R1-R6 rules + LLM judges |
| Domain | Code / repository | Content (Obsidian vault) |

## Dogfood

9+ versions, 14+ independent targets, 0 false negatives. See [references/dogfood-results.md](references/dogfood-results.md).

## License

MIT — see [LICENSE](LICENSE).
