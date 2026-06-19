# Examples Vault (Demo for Loopen)

This is a **demo vault** for dogfooding Loopen. It contains 4 .md files that violate R1-R3 in different ways.

## Files

| File | Violation | Rule |
|------|-----------|------|
| `good-doc.md` | none (clean baseline) | — |
| `missing-frontmatter.md` | no frontmatter block | R1 |
| `h1-before-abstract.md` | `# Title` is the first line; abstract is below | R2 |
| `broken-wikilink.md` | references `[[nonexistent-doc]]` which doesn't exist | R3 |

## Try it

```powershell
# 1. Copy this example config
cp .looprc.example.json .looprc.json

# 2. Run Phase 1 (scanner) — should detect R1/R2/R3 violations
powershell -File ..\..\scripts\phase1-auto.ps1 -Scope "examples/vault"

# 3. Inspect generated task dir
ls loopen-tasks/   # default output dir; configurable via .looprc.json

# 4. Run Phase 2 (apply)
powershell -File ..\..\scripts\phase2-batch.ps1 -Limit 5 -DryRun
powershell -File ..\..\scripts\phase2-batch.ps1 -Limit 5   # real apply
```

## Expected result

After running phase2-batch, you should see:
- `missing-frontmatter.md` → frontmatter block added (R1 fix)
- `h1-before-abstract.md` → H1 moved to after the abstract callout (R2 fix)
- `broken-wikilink.md` → `[[nonexistent-doc]]` replaced with `[TODO: 待补 nonexistent-doc]` (R3 fix)
- `good-doc.md` → unchanged (verifier pass)
