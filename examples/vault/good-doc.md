---
title: Good Document (R1-R6 clean)
created: 2026-06-19
updated: 2026-06-19
type: example
status: active
narrative: practical
tags: [example, vaultmend-demo]
summary: A baseline .md file that passes R1-R6 verifier.
---

> [!abstract]
> This document is a clean baseline. It has frontmatter (R1), H1 after abstract (R2), no broken wikilinks (R3), and a single H1 (R6).

# Good Document

This is a baseline .md file that should pass R1-R6 verifier.

## Section

VaultMend will see this file as:
- R1: frontmatter complete (6 fields)
- R2: H1 is after the `> [!abstract]` block ✓
- R3: no broken wikilinks (no `[[...]]` links)
- R4: no cross-references to other docs
- R5: no UTF-8 BOM
- R6: frontmatter `type: example` matches body
