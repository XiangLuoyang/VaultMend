---
title: H1 Before Abstract
created: 2026-06-19
updated: 2026-06-19
type: example
status: active
narrative: practical
tags: [example, vaultmend-demo]
summary: Demonstrates R2 violation: H1 is the first line; abstract comes after.
---

# H1 Before Abstract (R2 violation)

> [!abstract]
> This abstract should come BEFORE the H1, but the H1 is at the top. R2 will flag this.

## Section

VaultMend will see this file as:
- R1: frontmatter complete ✓
- R2: H1 (line 11) is BEFORE the `> [!abstract]` block (line 13) → R2 violation
- R3: no broken wikilinks
- R4: no cross-references
- R5: no BOM
- R6: OK
