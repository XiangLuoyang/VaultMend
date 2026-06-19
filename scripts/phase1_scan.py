#!/usr/bin/env python3
"""
phase1_scan.py — UTF-8 safe vault scanner (v0.6).

Replaces phase1-auto.ps1 for the actual detection logic (R1/R2/R3/R5/R7).
Writes the same prd.json + loop-summary.md per task dir as phase1-auto.ps1 did.

Why Python:
- PowerShell 5.1 source code parser decodes non-ASCII literals as ANSI codepage,
  mangling regex patterns like `\\[TODO:\\s*待补\\s*([^\\]]+)\\]\`.
- Python reads/writes UTF-8 cleanly via subprocess + io.

Usage:
    python phase1_scan.py                # scan + write task dirs
    python phase1_scan.py --dry-run      # scan only, no writes
    python phase1_scan.py --skip-applied # skip files in _log.jsonl action=applied
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path


# Path defaults (overridable via .looprc.json or args)
SCRIPT_DIR = Path(__file__).parent
LOOP_RC = SCRIPT_DIR / '.looprc.json'
LOG_PATH = SCRIPT_DIR / '_log.jsonl'


def load_looprc():
    with open(LOOP_RC, encoding='utf-8') as f:
        return json.load(f)


def load_applied_files():
    """Read _log.jsonl, return set of relative paths with action=applied."""
    if not LOG_PATH.exists():
        return set()
    applied = set()
    with open(LOG_PATH, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('action') == 'applied' and entry.get('scope'):
                    applied.add(entry['scope'])
            except json.JSONDecodeError:
                pass
    return applied


def detect_r1(content):
    """R1: frontmatter completeness (6 fields)."""
    m = re.match(r'^---\r?\n(.*?)\r?\n---', content, re.DOTALL)
    if not m:
        return {'rule': 'R1', 'severity': 'error',
                'fix_action': 'create-frontmatter-block',
                'description': 'R1 no frontmatter block'}
    fm = m.group(1)
    required = ['title', 'created', 'updated', 'type', 'status', 'narrative']
    missing = [r for r in required if not re.search(rf'(?m)^{re.escape(r)}\s*:', fm)]
    if missing:
        return {'rule': 'R1', 'severity': 'warn',
                'fix_action': 'add-missing-frontmatter-fields',
                'description': f'R1 missing fields: {", ".join(missing)}'}
    return None


def detect_r2(lines):
    """R2: H1 must come after abstract callout."""
    dash_count = 0
    fm_end = -1
    for i, line in enumerate(lines):
        if re.match(r'^---\s*$', line):
            dash_count += 1
            if dash_count == 2:
                fm_end = i
                break
    if fm_end < 0:
        return None
    h1_idx = -1
    abstract_idx = -1
    for i in range(fm_end + 1, min(fm_end + 30, len(lines))):
        if h1_idx < 0 and re.match(r'^#\s+\S', lines[i]):
            h1_idx = i
        if abstract_idx < 0 and re.match(r'^\s*>\s*\[!abstract\]', lines[i]):
            abstract_idx = i
        if h1_idx >= 0 and abstract_idx >= 0:
            break
    if h1_idx >= 0 and abstract_idx >= 0 and h1_idx < abstract_idx:
        return {'rule': 'R2', 'severity': 'warn', 'line': h1_idx + 1,
                'fix_action': 'reorder-move-h1-after-abstract',
                'description': f'R2 H1 at L{h1_idx+1} before abstract callout at L{abstract_idx+1}'}
    return None


def detect_r3(content, vault_path):
    """R3: broken wikilinks."""
    pattern = re.compile(r'\[\[([^\]]+)\]\]')
    broken = []
    for m in pattern.finditer(content):
        wl = m.group(1)
        wl_clean = re.sub(r'\|.*$', '', wl).replace('\\', '/')
        candidates = [
            vault_path / f'{wl_clean}.md',
            vault_path / re.sub(r'^Wiki/', '', wl_clean, count=1)
        ]
        if not any(c.exists() for c in candidates):
            broken.append(wl)
    if broken:
        return {'rule': 'R3', 'severity': 'warn',
                'fix_action': 'convert-broken-wikilinks-to-todo',
                'description': f'R3 {len(broken)} broken wikilinks: {", ".join(broken[:5])}'}
    return None


def detect_r5(file_bytes):
    """R5: UTF-8 BOM."""
    if len(file_bytes) >= 3 and file_bytes[0] == 0xEF and file_bytes[1] == 0xBB and file_bytes[2] == 0xBF:
        return {'rule': 'R5', 'severity': 'warn',
                'fix_action': 'remove-bom', 'description': 'R5 UTF-8 BOM present'}
    return None


def detect_r7(content):
    """R7: content TODO inventory (R3 fix_action residue that should never be auto-fixed)."""
    pattern = re.compile(r'\[TODO:\s*待补\s*([^\]]+)\]')
    todos = []
    categories = {'sources': 0, 'attachments': 0, 'concept': 0, 'aliased': 0, 'other': 0}
    for m in pattern.finditer(content):
        raw = m.group(1).strip()
        todos.append(raw)
        if raw.startswith('Sources/'):
            categories['sources'] += 1
        elif raw.startswith('attachments/'):
            categories['attachments'] += 1
        elif raw.startswith('Wiki/'):
            categories['concept'] += 1
        elif '|' in raw:
            categories['aliased'] += 1
        else:
            categories['other'] += 1
    if todos:
        cat_desc = ', '.join(f'{k}={v}' for k, v in categories.items() if v > 0)
        sample = '; '.join(todos[:5])
        return {'rule': 'R7', 'severity': 'info',
                'fix_action': 'inventory-only-no-autofix',
                'description': f'R7 {len(todos)} content TODOs [{cat_desc}]: {sample}'}
    return None


def scan_file(file_path, vault_path):
    """Run all detectors on a single file, return list of items."""
    rel_path = str(file_path.relative_to(vault_path)).replace('\\', '/')
    raw_bytes = file_path.read_bytes()
    try:
        content = raw_bytes.decode('utf-8')
    except UnicodeDecodeError:
        content = raw_bytes.decode('utf-8', errors='replace')
    lines = content.split('\n')

    items = []
    detectors = [
        ('R1', lambda: detect_r1(content)),
        ('R2', lambda: detect_r2(lines)),
        ('R3', lambda: detect_r3(content, vault_path)),
        ('R5', lambda: detect_r5(raw_bytes)),
        ('R7', lambda: detect_r7(content)),
    ]
    for rule, detector in detectors:
        result = detector()
        if result is None:
            continue
        result.setdefault('id', f'item-{rule.lower()}')
        result.setdefault('type', f'{rule}-violation')
        result.setdefault('severity', 'warn')
        result.setdefault('file', rel_path)
        result.setdefault('line', 0)
        items.append(result)

    return rel_path, items


def main():
    parser = argparse.ArgumentParser(description='Phase 1 vault scanner (Python, UTF-8 safe)')
    parser.add_argument('--dry-run', action='store_true', help='scan only, no task dirs')
    parser.add_argument('--skip-applied', action='store_true', help='skip files in _log.jsonl applied')
    args = parser.parse_args()

    looprc = load_looprc()
    vault_path = Path(looprc['defaults']['vault_path'])
    wiki_dir = vault_path / 'Wiki' / 'concepts'

    if not wiki_dir.exists():
        sys.stderr.write(f'ERROR: {wiki_dir} does not exist\n')
        return 1

    applied = load_applied_files() if args.skip_applied else set()
    print(f'[phase1-scan] Applied files (will skip with --skip-applied): {len(applied)}')

    targets = sorted(wiki_dir.glob('*.md'))
    print(f'[phase1-scan] Scanning {len(targets)} .md files in {wiki_dir}')

    results = []
    skipped = 0
    for f in targets:
        rel, items = scan_file(f, vault_path)
        if args.skip_applied and rel in applied:
            skipped += 1
            continue
        if items:
            results.append((rel, items, len(f.read_text(encoding='utf-8').split('\n'))))

    print(f'[phase1-scan] Affected files: {len(results)}')
    print(f'[phase1-scan] Skipped (already applied): {skipped}')

    by_rule = {'R1': 0, 'R2': 0, 'R3': 0, 'R5': 0, 'R7': 0}
    for _, items, _ in results:
        for item in items:
            rule = item.get('rule')
            if rule in by_rule:
                by_rule[rule] += 1

    print()
    print('=== Rule breakdown ===')
    for k in ('R1', 'R2', 'R3', 'R5', 'R7'):
        print(f'  {k} : {by_rule[k]}')

    if args.dry_run:
        print()
        print('[DRY-RUN] No task dirs created')
        return 0

    ts_ms = int(time.time() * 1000)
    ts_iso = time.strftime('%Y-%m-%dT%H:%M:%S+08:00')
    gen_count = 0
    for rel, items, line_count in results:
        file_name = Path(rel).stem
        task_name = f'lint-auto-{file_name}'
        task_dir = SCRIPT_DIR / task_name / str(ts_ms)
        proposed_dir = task_dir / 'proposed-changes'
        proposed_dir.mkdir(parents=True, exist_ok=True)

        prd = {
            'task_id': f'{task_name}-{ts_ms}',
            'ts': ts_iso,
            'vault_path': str(vault_path).replace('\\', '/'),
            'rules_source': 'CLAUDE.md',
            'scope': rel,
            'items': items,
            'metadata': {
                'max_iter': 5,
                'max_tokens': 500000,
                'timeout_seconds': 1800,
                'verifier_required': True,
                'sources_protected': True,
            }
        }
        (task_dir / 'prd.json').write_text(
            json.dumps(prd, ensure_ascii=False, indent=2),
            encoding='utf-8'
        )

        item_lines = '\n'.join(f"- {it['id']}: {it['description']}" for it in items)
        summary = (
            f"# Loop Summary -- {task_name} (auto-generated)\n\n"
            f"> Generated: {ts_iso}\n"
            f"> Action: **AUTO_PHASE1**\n"
            f"> Source: phase1_scan.py (v0.6)\n"
            f"> Scope: {rel}\n"
            f"> Items: {len(items)}\n\n"
            f"## Items\n\n{item_lines}\n\n"
            f"## Next step\n\n"
            f"Run: phase2-batch.py --scope {rel}\n"
        )
        (task_dir / 'loop-summary.md').write_text(summary, encoding='utf-8')
        gen_count += 1

    print()
    print(f'[phase1-scan] Generated {gen_count} task dirs')
    print()
    print('Next step: process each task dir via run-loop.py, then apply/discard')
    return 0


if __name__ == '__main__':
    sys.exit(main())
