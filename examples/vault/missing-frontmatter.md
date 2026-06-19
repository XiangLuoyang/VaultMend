# Missing Frontmatter

This document has no frontmatter block, so R1 verifier will flag it.

## Section

VaultMend will see this file as:
- R1: missing frontmatter (no `---` block at top)
- R2: H1 is the first line; abstract callout is below → R2 violation too
- R3: no broken wikilinks
- R4: no cross-references
- R5: no BOM
- R6: missing frontmatter → R6 also flag

> [!abstract]
> Abstract for this document, after the H1. This violates R2.
