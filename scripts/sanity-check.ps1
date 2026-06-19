# Loopen — Obsidian vault quality audit + auto-fix toolchain
# https://github.com/XiangLuoyang/Loopen
#
# Licensed under the MIT License. See LICENSE in the project root.

# loopen sanity check (v0.1)
# Verifies directory structure + apply/discard paths work as designed.
# Does NOT actually run a lint loop — only tests the plumbing.

$ErrorActionPreference = "Stop"
$root = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ts = [DateTimeOffset]::Parse("2026-06-16 01:30:00+08:00").ToUnixTimeMilliseconds()

Write-Host "=== Loop Sanity Check v0.1 ===" -ForegroundColor Cyan
Write-Host "Root: $root"
Write-Host ""

# 1. directory structure (auto-create runtime dirs if missing)
Write-Host "[1] Directory structure" -ForegroundColor Yellow
$expectedDirs = @(
    $root,
    "$root\_archive",
    "$root\_archive\_discarded",
    "$root\journals"
)
foreach ($d in $expectedDirs) {
    if (Test-Path $d) {
        Write-Host "  OK  $d"
    } else {
        # Auto-create runtime dirs (治本: 首次跑不 fail)
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host "  CREATED  $d (runtime dir)" -ForegroundColor Yellow
    }
}

# 2. .looprc.json (warn if missing — first-run artifact)
Write-Host ""
Write-Host "[2] .looprc.json" -ForegroundColor Yellow
$looprcPath = "$root\.looprc.json"
$looprcExample = "$root\..\.looprc.example.json"
if (Test-Path $looprcPath) {
    $size = (Get-Item $looprcPath).Length
    Write-Host "  OK  $looprcPath ($size bytes)"
} else {
    Write-Host "  WARN  $looprcPath (missing — first-run artifact)" -ForegroundColor Yellow
    if (Test-Path $looprcExample) {
        Write-Host "        Tip: Copy $looprcExample to $looprcPath and edit vault_path" -ForegroundColor Yellow
    }
}

# 3. _log.jsonl (warn if missing — first-run artifact, created on first run)
Write-Host ""
Write-Host "[3] _log.jsonl" -ForegroundColor Yellow
$logPath = "$root\_log.jsonl"
if (Test-Path $logPath) {
    $size = (Get-Item $logPath).Length
    Write-Host "  OK  $logPath ($size bytes, append-only)"
} else {
    Write-Host "  WARN  $logPath (missing — will be created on first run)" -ForegroundColor Yellow
}

# 4. create a fake task directory (NOT commit, just verify path works)
Write-Host ""
Write-Host "[4] Create fake task dir (loopen-test)" -ForegroundColor Yellow
$taskName = "loopen-sanity-test"
$taskDir = "$root\$taskName\$ts"
$paths = @(
    "$taskDir",
    "$taskDir\proposed-changes"
)
foreach ($p in $paths) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Force -Path $p | Out-Null
    }
}

# write fake prd.json (manual JSON, not ConvertTo-Json)
$prdJson = '{"task_id":"sanity-test-' + $ts + '","ts":"2026-06-16T01:30:00+08:00","vault_path":"sanity-test","rules_source":"CLAUDE.md","scope":"full","items":[],"metadata":{"max_iter":5,"max_tokens":500000,"timeout_seconds":1800,"verifier_required":true,"sources_protected":true}}'
$prdPath = "$taskDir\prd.json"
[System.IO.File]::WriteAllText($prdPath, $prdJson, [System.Text.UTF8Encoding]::new($false))
Write-Host "  OK  fake prd.json: $prdPath"

# write fake progress.txt
$progPath = "$taskDir\progress.txt"
[System.IO.File]::WriteAllText($progPath, "[2026-06-16T01:30:00+08:00] ITER=0 PHASE=summary ACTION=sanity-test RESULT=ok NOTE=plumbing verified`r`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "  OK  fake progress.txt: $progPath"

# write fake loop-summary.md
$summaryPath = "$taskDir\loop-summary.md"
$summary = @"
# Loop Summary — sanity-test-$ts

> Generated: 2026-06-16T01:30:00+08:00
> Status: **SANITY_TEST**

## Overview

- **Task**: sanity-test-$ts
- **Items found**: 0
- **Note**: This is a sanity test, not a real run.
"@
[System.IO.File]::WriteAllText($summaryPath, $summary, [System.Text.UTF8Encoding]::new($false))
Write-Host "  OK  fake loop-summary.md: $summaryPath"

# 5. test DISCARD path: move to _archive/_discarded/
Write-Host ""
Write-Host "[5] Test DISCARD path (move to _archive/_discarded/)" -ForegroundColor Yellow
$discardDest = "$root\_archive\_discarded\$taskName-$ts"
if (Test-Path $discardDest) {
    Remove-Item -Recurse -Force $discardDest
}
Move-Item -Path "$root\$taskName\$ts" -Destination $discardDest
if (Test-Path $discardDest) {
    Write-Host "  OK  moved to: $discardDest"
} else {
    Write-Host "  FAIL  discard move failed" -ForegroundColor Red
    exit 1
}

# also remove the empty task name dir
Remove-Item -Recurse -Force "$root\$taskName" -ErrorAction SilentlyContinue

# 6. append to _log.jsonl (simulating discard event)
Write-Host ""
Write-Host "[6] Append to _log.jsonl (discard event)" -ForegroundColor Yellow
$entry = '{"ts":"2026-06-16T01:30:00+08:00","task":"' + $taskName + '","run_id":"sanity-test-' + $ts + '","action":"discarded","status":"ok","items_total":0,"items_verified":0,"max_iter":5,"max_tokens":500000,"decision_by":"sanity-check","note":"plumbing test, NOT a real loop run"}' + "`n"
# Use .NET API for UTF-8 no-BOM (治本: 避免 BOM 污染 JSONL parser — 6/13 lesson)
# Handle missing _log.jsonl (first run): treat as empty content
if (Test-Path $logPath) {
    $existingContent = [System.IO.File]::ReadAllText($logPath, [System.Text.UTF8Encoding]::new($false))
} else {
    $existingContent = ""
    Write-Host "  NOTE  _log.jsonl did not exist — created fresh" -ForegroundColor Yellow
}
[System.IO.File]::WriteAllText($logPath, $existingContent + $entry, [System.Text.UTF8Encoding]::new($false))
$logContent = [System.IO.File]::ReadAllText($logPath, [System.Text.UTF8Encoding]::new($false))
Write-Host "  OK  _log.jsonl content:"
Write-Host "  ---"
Write-Host "  $logContent"
Write-Host "  ---"

# 7. verify git commit would be safe (only workspace/loop/ path)
Write-Host ""
Write-Host "[7] Verify git commit scope" -ForegroundColor Yellow
Set-Location (Split-Path -Parent $root)
$gitStatus = git status --short 2>&1
$loopChanges = $gitStatus | Where-Object { $_ -match "scripts/loopen|scripts/" }
Write-Host "  Files changed under loop/: $($loopChanges.Count)"
foreach ($c in $loopChanges) {
    Write-Host "    $c"
}

Write-Host ""
Write-Host "=== Sanity Check PASSED ===" -ForegroundColor Green
Write-Host ""
Write-Host "v0.1 plumbing is working. Ready for first real dogfood run."
Write-Host "To dogfood: sessions_spawn the loopen skill against the current vault."
Write-Host ""
