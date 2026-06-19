# Loop Engineering Gap

**Status (2026-06-20):** Documented but not implemented. The R1-R6 vault repair ruleset is the core value; Loop Engineering paradigm borrowing is an inspiration, not a goal.

## Why this document exists

VaultMend originated as a learning vehicle for the Loop Engineering paradigm (Boris Cherny / Addy Osmani, 2026). After self-challenge, the project's core value was identified as the **R1-R6 rule set** (rule-driven vault repair), with the Loop Engineering execution paradigm (5-phase pipeline, autonomous/human-gate modes, verifier pattern, journal structure) as a borrowed execution means.

This document records the **specific Loop Engineering patterns that VaultMend has NOT adopted**, and the reasoning for not adopting them now.

## Gap 1: PRD / spec-first entry (most critical)

**What it is:** In every successful Loop Engineering case study (Ralph Wiggum, Geoffrey Huntly; Udacity Field Guide; Agent Skills by Addy Osmani), the loop entry point is a structured PRD (prd.json / spec.md / user_stories.md / acceptance_criteria.yaml). The agent iterates over user stories with pass/fail conditions until completion.

**VaultMend status:** ❌ Not implemented. Phase 1 scan goes directly to vault file detection, with no structured "what should be done" specification layer.

**Why not now:** Adding a PRD layer is a major schema addition that would require (a) defining the PRD schema for vault repair, (b) integrating it into Phase 0 of the pipeline, (c) updating all examples. The R1-R6 ruleset already provides sufficient structure for the current goal (rule-driven repair). The PRD layer would be valuable for cases where the user wants to specify which rules to apply and acceptance criteria — this can be added in a future major version if there's demand.

**Decision trigger for revisit:** If VaultMend is used in scenarios where the user wants to specify "fix only R3 and R5, leave R1 alone" or "stop when 95% of broken wikilinks are fixed, not 100%", that's a PRD entry requirement. Until then, R1-R6 ruleset is sufficient.

## Gap 2: Completion promise / verifier-natural-stop

**What it is:** Loop Engineering canonical pattern uses **verifier pass or completion tag** as the natural stop condition, not `max_iter`. The verifier must be independent of the generator (Parallax principle: cognitive-executive separation).

**VaultMend status:** ❌ Not implemented. `max_iter` is a placeholder in the loop config. The verifier (R1-R6 checks + LLM judges) runs in the same LLM context as the generator (Phase 2 batch).

**Why not now:** The R1-R6 ruleset has a **finite, well-defined fix space** (frontmatter fields, H1 position, broken wikilinks, BOM, semantic consistency). It does not require iterative "try until done" because each rule has a deterministic fix. Adding completion-promise machinery would add complexity without solving a real problem for vault repair. The Parallax warning (verifier and generator should be independent) is valid in principle but the current ruleset has zero hallucination risk — R2 "move H1 after abstract" doesn't have multiple correct answers.

**Decision trigger for revisit:** If R6 semantic consistency (LLM-judged content) expands to more ambiguous domains, or if user feedback indicates the loop should re-run when verifier reports partial success, this becomes critical.

## Gap 3: External harness integration

**What it is:** The loop paradigm assumes a "harness" environment (filesystem, sandbox, observability, state persistence, tool set). Mature Loop Engineering deployments (Gas Town, Agent Skills) integrate deeply with harness frameworks.

**VaultMend status:** 🟡 Partial. Journal is implemented (state persistence). No formal sandbox, no observability beyond journal, no external harness framework integration.

**Why not now:** VaultMend runs against a local Obsidian vault in the user's git workspace. The "harness" is the vault + git. Adding more harness machinery (sandbox, observability) would be over-engineering for the use case. The loop is meant to run, audit, apply, exit — not operate as a long-running autonomous service.

**Decision trigger for revisit:** If VaultMend is extended to support multi-user / remote vault scenarios, harness design becomes critical.

## Gap 4: Visual workflow orchestration (n8n / draw.io / Archon)

**What it is:** Visual tools that let users design the loop workflow via drag-and-drop, integrated into a harness framework. Targets "goal + boundary + means" simultaneously.

**VaultMend status:** ❌ Not implemented. VaultMend's pipeline is described in SKILL.md and runs via PowerShell scripts. No visual editor.

**Why not now:** Anthropic's own experiment (2026-03-31) on their agent harness showed that **most harness components are dead weight for current models**, and the **3-component core (planner + generator + evaluator) is sufficient**. Adding a visual editor would add UI complexity for marginal value. The power of Ralph (the most adopted Loop Engineering case) is its extreme simplicity — bash + prd.json + progress.txt. VaultMend follows this minimalism principle.

**Decision trigger for revisit:** If user feedback indicates that the current PowerShell pipeline is too opaque, or if non-technical users need to adopt VaultMend, a visual layer could be added as a wrapper around the existing pipeline (not a replacement).

## What VaultMend DOES borrow from Loop Engineering

For completeness, here is the explicit list of Loop Engineering elements that ARE implemented in VaultMend:

- ✅ **5-phase pipeline** (scan → batch → verify → apply → journal) — borrowed from agent harness engineering pattern
- ✅ **Verifier pattern** (R1-R6 rule checks + LLM judges) — borrowed from verifier-as-bottleneck principle
- ✅ **Autonomous / human-gate execution modes** — borrowed from autonomy dial concept
- ✅ **Journal pattern** (state persistence through files, not LLM context) — borrowed from progress.txt / Beads pattern
- ✅ **Decision attribution** (`decision_by: AI:autonomous` in journal entries) — borrowed from explicit decision auditability pattern
- ✅ **Multi-task concurrent execution** (v0.8.2) — borrowed from parallel thread pattern (IndyDevDan / Boris Cherny)

## Industry context (as of 2026-06-20)

The Loop Engineering paradigm is rapidly evolving but **production tools are not yet mature**. Survey of canonical cases:

| Case | Author | Core innovation | Production-ready? |
|------|--------|-----------------|-------------------|
| Ralph Wiggum | Geoffrey Huntly | bash + prd.json + progress.txt | ✅ Most adopted |
| Agent Skills | Addy Osmani | 24 SKILL.md files (define → ship) | ✅ Production-grade |
| Thread Based Engineering | IndyDevDan | 6 thread types (Boris Cherny workflow) | 🟡 Conceptual framework |
| Gas Town | Steve Yegge | Mayor + Polecats + Witnesses + Beads | 🟡 Powerful but high barrier |
| Archon Harness Builder | MindStudio | YAML workflow wrapping Claude Code/Codex CLI | 🟡 Early stage |

**Common thread:** All cases are **simple at the core** (1-3 components + a few files). The "loop" itself is almost trivially implemented (a while loop, a `/goal` slash command). The hard work is in the **PRD schema** and the **verifier design** — both of which are domain-specific and not productizable as a general tool.

This validates VaultMend's choice to focus on the R1-R6 ruleset (the reusable value) rather than chasing the Loop Engineering paradigm (the execution means).

## Conclusion

VaultMend is a **rule-driven vault repair toolchain** with a **Loop Engineering-inspired execution pipeline**. It does not aim to be a canonical Loop Engineering implementation; it borrows the pattern where it helps and skips it where it doesn't add value.

The four gaps above are documented for transparency, not as TODOs. They will be reconsidered if/when the underlying use case expands to demand them.

---

**Document version:** 2026-06-20 (initial)
**Decided by:** 项罗阳 (option A: document and don't act)
**Related decisions:** See `memory/decisions.log` 2026-06-20 entries