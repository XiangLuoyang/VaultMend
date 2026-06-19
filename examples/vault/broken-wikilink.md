---
title: Broken Wikilink
created: 2026-06-19
updated: 2026-06-19
type: example
status: active
narrative: practical
tags: [example, vaultmend-demo]
summary: Demonstrates R3 violation: references [[nonexistent-doc]] which doesn't exist.
---

> [!abstract]
> This document links to [[nonexistent-doc]], but no such file exists in the vault.

# Broken Wikilink

See also: [[nonexistent-doc]] and [[another-missing-page]].

## Section

VaultMend will see this file as:
- R1: frontmatter complete ✓
- R2: H1 is after the abstract ✓
- R3: two broken wikilinks → R3 violation
- R4: no cross-references
- R5: no BOM
- R6: OK

After R3 auto-fix, the file should look like:
```
See also: [TODO: 待补 nonexistent-doc] and [TODO: 待补 another-missing-page].
```
