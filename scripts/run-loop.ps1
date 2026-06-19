# Loopen — Obsidian vault quality audit + auto-fix toolchain
# https://github.com/XiangLuoyang/Loopen
#
# Licensed under the MIT License. See LICENSE in the project root.

# loopen runner (v0.2 + v0.8.2)
# Runs Phase 2.5 (patch validation) + Phase 3 (verification) + Phase 4 (summary) for an existing task.
#
# Usage:
#   .\run-loop.ps1 -TaskDir <path-to-task-dir>
#   .\run-loop.ps1 -TaskDir <path> -Action validate
#   .\run-loop.ps1 -TaskDir <path> -Action verify
#   .\run-loop.ps1 -TaskDir <path> -Action summarize
#   .\run-loop.ps1 -TaskDir <path> -Action all           (default)
#   .\run-loop.ps1 -TaskList <path1,path2,...> -MaxConcurrency 3   (v0.8.2)
#
# Prereqs:
#   - Task dir must contain prd.json
#   - Task dir may contain proposed-changes/*.patch (for validate/verify)
#   - .looprc.json must be in same dir as this script
#
# Exit codes:
#   0 = all phases pass
#   1 = validation or verification failed
#   2 = prereq missing
#   3 = partial success in concurrent mode (some tasks failed)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, ParameterSetName = "Single")]
    [string]$TaskDir,

    [Parameter(Mandatory = $false, ParameterSetName = "Multi")]
    [string]$TaskList,

    [Parameter(Mandatory = $false, ParameterSetName = "Multi")]
    [int]$MaxConcurrency = 4,

    [ValidateSet("validate", "verify", "summarize", "all")]
    [string]$Action = "all",

    [switch]$NoArchive
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# === Load config ===
$loopRcPath = Join-Path $ScriptDir ".looprc.json"
if (-not (Test-Path $loopRcPath)) {
    Write-Error ".looprc.json not found at $loopRcPath"
    exit 2
}
# v0.8.1: use .NET API for UTF-8 no-BOM read
# (PS 5.1 Get-Content uses system codepage, mangles UTF-8 Chinese)
$loopRcText = [System.IO.File]::ReadAllText($loopRcPath, [System.Text.UTF8Encoding]::new($false))
$loopRc = $loopRcText | ConvertFrom-Json
$vaultPath = $loopRc.defaults.vault_path
# v0.7: 读 execution_mode + journal config
$executionMode = if ($loopRc.execution) { $loopRc.execution.mode } else { "human-gate" }
$autoApply = if ($loopRc.execution -and $null -ne $loopRc.execution.auto_apply_on_pass) { $loopRc.execution.auto_apply_on_pass } else { $false }
$decisionByAutonomous = if ($loopRc.execution -and $loopRc.execution.decision_by_autonomous) { $loopRc.execution.decision_by_autonomous } else { "AI:autonomous" }
$journalEnabled = if ($loopRc.journal -and $null -ne $loopRc.journal.enabled) { $loopRc.journal.enabled } else { $false }
$journalDir = if ($loopRc.journal -and $loopRc.journal.dir) { $loopRc.journal.dir } else { "workspace/loop/journals/" }
Write-Host "[config] vault: $vaultPath  mode: $executionMode" -ForegroundColor DarkGray

# === v0.8.2: Concurrent routing ===
# If -TaskList is provided, route to concurrent runner
# TaskList is a single string with | separator (PS inter-process array passing is unreliable)
if ($TaskList) {
    $taskDirs = @($TaskList -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Write-Host "[v0.8.2] Concurrent mode — $($taskDirs.Count) tasks, max $MaxConcurrency parallel" -ForegroundColor Magenta
    # Validate all task dirs first
    foreach ($td in $taskDirs) {
        if (-not (Test-Path $td)) {
            Write-Error "TaskDir not found: $td"
            exit 2
        }
    }
    # v0.8.2: Use file-based result collection
    # Each child process writes <taskDir>/run-results.json (Phase 4 already does this)
    # Parent waits for each child's run-results.json to appear, then reads exitCode from it
    # This avoids PS 5.1 Start-Process ExitCode unreliability bug
    $procList = @()
    $i = 0
    foreach ($td in $taskDirs) {
        # Throttle: wait if at MaxConcurrency
        while ($procList.Count -ge $MaxConcurrency) {
            $done = @($procList | Where-Object { $_.HasExited })
            foreach ($d in $done) { $procList = @($procList | Where-Object { $_ -ne $d }) }
            if ($procList.Count -ge $MaxConcurrency) { Start-Sleep -Milliseconds 200 }
        }
        $i++
        $scriptPath = $MyInvocation.MyCommand.Path
        $argLine = "-NoLogo -NoProfile -File `"$scriptPath`" -TaskDir `"$td`" -Action $Action"
        Write-Host "  [spawn $i/$($taskDirs.Count)] $td" -ForegroundColor Cyan
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argLine `
                              -NoNewWindow -PassThru
        Add-Member -InputObject $proc -NotePropertyName "TaskDir" -NotePropertyValue $td -Force
        $procList += $proc
    }
    # Wait for all to finish + poll for run-results.json
    Write-Host "  [wait] all tasks spawned, waiting for results..." -ForegroundColor DarkGray
    $resultTimeout = 120  # seconds
    $waitStart = Get-Date
    foreach ($p in $procList) {
        $p.WaitForExit()
        # Poll for run-results.json (child Phase 4 writes runner-results.json)
        $resultsJson = Join-Path $p.TaskDir "runner-results.json"
        $maxWait = (Get-Date).AddSeconds($resultTimeout)
        while (-not (Test-Path $resultsJson) -and (Get-Date) -lt $maxWait) {
            Start-Sleep -Milliseconds 100
        }
    }
    # Collect results from runner-results.json files
    Write-Host ""
    Write-Host "=== Concurrent results ===" -ForegroundColor Cyan
    $okCount = 0
    $failCount = 0
    foreach ($p in $procList) {
        $taskName = Split-Path $p.TaskDir -Leaf
        $resultsJson = Join-Path $p.TaskDir "runner-results.json"
        if (Test-Path $resultsJson) {
            try {
                $text = [System.IO.File]::ReadAllText($resultsJson, [System.Text.UTF8Encoding]::new($false))
                $jr = $text | ConvertFrom-Json
                if ($jr.exitCode -eq 0) {
                    Write-Host "  PASS  $taskName" -ForegroundColor Green
                    $okCount++
                } else {
                    Write-Host "  FAIL  $taskName (exit $($jr.exitCode))" -ForegroundColor Red
                    $failCount++
                }
            } catch {
                Write-Host "  FAIL  $taskName (results parse error: $($_.Exception.Message))" -ForegroundColor Red
                $failCount++
            }
        } else {
            Write-Host "  FAIL  $taskName (no run-results.json after $($resultTimeout)s)" -ForegroundColor Red
            $failCount++
        }
    }
    Write-Host "  Total: $okCount pass, $failCount fail"
    if ($failCount -gt 0) { exit 3 } else { exit 0 }
}

# === Load task ===
if (-not $TaskDir) {
    Write-Error "Must provide -TaskDir (single) or -TaskList (concurrent)"
    exit 2
}
if (-not (Test-Path $TaskDir)) {
    Write-Error "TaskDir not found: $TaskDir"
    exit 2
}
$prdPath = Join-Path $TaskDir "prd.json"
if (-not (Test-Path $prdPath)) {
    Write-Error "prd.json not found in $TaskDir"
    exit 2
}
$prdRaw = [System.IO.File]::ReadAllText($prdPath, [System.Text.UTF8Encoding]::new($false))
$prd = $prdRaw | ConvertFrom-Json
$proposedDir = Join-Path $TaskDir "proposed-changes"

Write-Host "[task] $((Split-Path $TaskDir -Leaf))  items=$($prd.items.Count)  scope=$($prd.scope)" -ForegroundColor DarkGray
Write-Host ""

# === Results accumulator ===
$results = [ordered]@{
    task = Split-Path $TaskDir -Leaf
    ts = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
    action = $Action
    validation = [ordered]@{
        total = 0
        pass = 0
        fail = 0
        details = @()
    }
    verification = [ordered]@{
        total = 0
        pass = 0
        fail = 0
        details = @()
    }
}

# ============================================================
# Phase 2.5: PATCH VALIDATION
# ============================================================
function Invoke-PatchValidation {
    Write-Host "[Phase 2.5] Patch validation (git apply --check)" -ForegroundColor Cyan
    if (-not (Test-Path $proposedDir)) {
        Write-Host "  no proposed-changes/ dir, skipping" -ForegroundColor DarkGray
        $script:validationAdvisory = $true
        return $true
    }
    $patches = @(Get-ChildItem $proposedDir -Filter "*.patch")
    $results.validation.total = $patches.Count
    if ($patches.Count -eq 0) {
        Write-Host "  no .patch files, skipping" -ForegroundColor DarkGray
        $script:validationAdvisory = $true
        return $true
    }

    # v0.8.0: Phase 2.5 改 advisory
    # 不再因 patch validation 失败而阻塞 allPass
    # 把 fail 转 advisory warn，autonomous 决策时再考虑
    $advisoryPass = $true
    Push-Location $vaultPath
    try {
        foreach ($patch in $patches) {
            # v0.7 Bug A fix: 包 inner try/catch — PS 5.1 下 & git apply 抛 NativeCommandError
            $output = ""
            $exitCode = 0
            try {
                $output = & git apply --check $patch.FullName 2>&1
                $exitCode = $LASTEXITCODE
            } catch {
                $output = "FATAL: git apply --check threw: $($_.Exception.Message)"
                $exitCode = 1
            }
            if ($exitCode -eq 0) {
                $results.validation.pass++
                $results.validation.details += @{
                    file = $patch.Name
                    status = "PASS"
                    output = "CLEAN"
                }
                Write-Host "  PASS  $($patch.Name)" -ForegroundColor Green
            } else {
                # v0.8.0: 标记为 advisory warn，不设 $allPass = $false
                $results.validation.fail++
                $results.validation.details += @{
                    file = $patch.Name
                    status = "ADVISORY-WARN"
                    output = ($output -join "`n")
                }
                Write-Host "  ADVISORY-WARN  $($patch.Name)" -ForegroundColor Yellow
                Write-Host "        $($output -join "`n        ")" -ForegroundColor DarkYellow
                $advisoryPass = $false
            }
        }
    } finally {
        Pop-Location
    }
    # v0.8.0: 用 $script: 写回 advisory 状态，return 永远为 $true（Phase 2.5 不阻塞）
    $script:validationAdvisory = $advisoryPass
    return $true
}

# ============================================================
# Phase 3: VERIFICATION (R1-R6, shadow mode)
# 逻辑：把 patches apply 到 temp copy，验证 temp copy，丢弃 temp。
# 这样回答的是"假设 apply 了这些 patches，文件状态如何"。
# ============================================================
function Invoke-Verification {
    param([bool]$ValidationPassed)

    Write-Host ""
    Write-Host "[Phase 3] R1-R6 verification (shadow mode — applies patches to temp, verifies, discards)" -ForegroundColor Cyan
    $results.verification.total = $prd.items.Count
    $allPass = $true

    # Build temp shadow vault (copy of full vault) — too expensive for large vaults.
    # Better: copy only files referenced by prd.items, apply patches, verify, cleanup.
    $shadowRoot = Join-Path $env:TEMP "loop-shadow-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Force -Path $shadowRoot | Out-Null
    Write-Host "  shadow root: $shadowRoot" -ForegroundColor DarkGray

    try {
        # Copy each referenced file to shadow
        $copiedFiles = @()
        foreach ($item in $prd.items) {
            $srcPath = Join-Path $vaultPath $item.file
            if (-not (Test-Path $srcPath)) { continue }
            $destPath = Join-Path $shadowRoot $item.file
            $destDir = Split-Path $destPath -Parent
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item $srcPath $destPath -Force
            $copiedFiles += $item.file
        }

        # Apply all patches to shadow (if validation passed)
        if ($ValidationPassed) {
            $patches = @(Get-ChildItem $proposedDir -Filter "*.patch")
            # Copy patches into shadow (paths inside are relative to vault, and shadow preserves same subtree structure)
            foreach ($patch in $patches) {
                Copy-Item $patch.FullName (Join-Path $shadowRoot $patch.Name) -Force
            }
            # 在 shadow root 里 apply patches — pass full path to git apply 避免 cwd 问题
            foreach ($patch in $patches) {
                $shadowPatchPath = Join-Path $shadowRoot $patch.Name
                # patch 内的路径是 a/<file> b/<file>，相对于 git apply 调用的 cwd
                Push-Location $shadowRoot
                try {
                    # v0.7 Bug A fix: inner try/catch 包 & git apply — PS 5.1 NativeCommandError 不中断整个 Phase 3
                    try {
                        & git apply $patch.Name 2>&1 | Out-Null
                    } catch {
                        Write-Host "  WARN: patch apply in shadow failed: $($patch.Name) — $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } finally {
                    Pop-Location
                }
            }
        } else {
            Write-Host "  (validation failed — verifying unpatched current state)" -ForegroundColor Yellow
        }

        # Now verify each item against the (possibly patched) shadow
        foreach ($item in $prd.items) {
            $shadowFilePath = Join-Path $shadowRoot $item.file
            if (-not (Test-Path $shadowFilePath)) {
                $results.verification.fail++
                $results.verification.details += @{
                    id = $item.id
                    file = $item.file
                    status = "FAIL"
                    rules = @{ _fatal = "FILE NOT FOUND" }
                }
                Write-Host "  FAIL  $($item.id) — file not found: $($item.file)" -ForegroundColor Red
                $allPass = $false
                continue
            }

            $content = [System.IO.File]::ReadAllText($shadowFilePath, [System.Text.UTF8Encoding]::new($false))
        $rules = [ordered]@{}

        # R1: frontmatter 完整性
        # Use named group + explicit RegexOptions to avoid PS 5.1 inline (?ms) bug
        $fmPattern = New-Object System.Text.RegularExpressions.Regex('^---\r?\n(?<body>.*?)\r?\n---', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $fmMatch = $fmPattern.Match($content)
        if ($fmMatch.Success) {
            $fm = $fmMatch.Groups[1].Value
            $required = @('title','created','updated','type','status','narrative')
            $missing = @($required | Where-Object { $fm -notmatch "(?m)^$([regex]::Escape($_))\s*:" })
            $rules.R1 = if ($missing.Count -eq 0) { "PASS" } else { "FAIL (missing: $($missing -join ','))" }
        } else {
            $rules.R1 = "FAIL (no frontmatter block)"
        }

        # R2: abstract callout — same RegexOptions workaround
        $afterFmPattern = New-Object System.Text.RegularExpressions.Regex('^---\r?\n.*?\r?\n---\r?\n', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $afterFm = $afterFmPattern.Replace($content, '')
        $firstNonBlank = ($afterFm -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        $rules.R2 = if ($firstNonBlank -match '^\s*>\s*\[!abstract\]') { "PASS" } else { "FAIL" }

        # R3: cross-reference（轻量检 — 只看每条 wikilink 目标文件是否存在）
        $wlPattern = '\[\[([^\]]+)\]\]'
        $wikilinks = [regex]::Matches($content, $wlPattern) | ForEach-Object { $_.Groups[1].Value }
        $broken = @()
        foreach ($wl in $wikilinks) {
            $wlClean = $wl -replace '\|.*$',''
            $target = $wlClean -replace '\\','/'
            $candidates = @(
                (Join-Path $vaultPath "$target.md"),
                (Join-Path $vaultPath ($target -replace '^Wiki/',''))
            )
            $found = $false
            foreach ($c in $candidates) { if (Test-Path $c) { $found = $true; break } }
            if (-not $found) { $broken += $wl }
        }
        $rules.R3 = if ($broken.Count -eq 0) { "PASS" } else { "FAIL ($($broken.Count) broken: $($broken -join ', '))" }

        # R4: 死文档保护 (v0.2 简化：只检 item.file 不在 Sources/)
        $rules.R4 = if ($item.file -match '^Sources/') { "FAIL (Sources/ protected)" } else { "PASS" }

        # R5: 中文编码 BOM
        $bytes = [System.IO.File]::ReadAllBytes($shadowFilePath)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $rules.R5 = "FAIL (UTF-8 BOM present)"
        } else {
            $rules.R5 = "PASS"
        }

        # R6: Sources/ 未触碰
        $rules.R6 = if ($item.file -match '^Sources/') { "FAIL" } else { "PASS" }

        # Verdict per item
        $fails = @($rules.Values | Where-Object { $_ -match '^FAIL' })
        $verdict = if ($fails.Count -eq 0) { "PASS" } else { "FAIL" }
        if ($verdict -eq "FAIL") { $allPass = $false; $results.verification.fail++ } else { $results.verification.pass++ }

        $results.verification.details += @{
            id = $item.id
            file = $item.file
            status = $verdict
            rules = $rules
        }

        $color = if ($verdict -eq "PASS") { "Green" } else { "Red" }
        Write-Host "  $verdict  $($item.id) ($($item.file))" -ForegroundColor $color
        if ($verdict -eq "FAIL") {
            foreach ($k in @($rules.Keys)) {
                if ($rules[$k] -match '^FAIL') {
                    Write-Host "        $k : $($rules[$k])" -ForegroundColor Red
                }
            }
        }
    }
    } finally {
        # Cleanup shadow
        if (Test-Path $shadowRoot) {
            Remove-Item -Recurse -Force $shadowRoot
        }
    }
    return $allPass
}

# ============================================================
# Phase 4: SUMMARY
# ============================================================
function Invoke-Summarize {
    param([bool]$OverallPass)

    Write-Host ""
    Write-Host "[Phase 4] Summary" -ForegroundColor Cyan

    $summaryPath = Join-Path $TaskDir "loop-summary.md"
    $ts = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")

    $verdict = if ($OverallPass) { "SAFE TO APPLY" } else { "MANUAL REVIEW REQUIRED" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Loop Summary — $((Split-Path $TaskDir -Leaf))")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Generated: $ts")
    [void]$sb.AppendLine("> Action: **$Action**")
    [void]$sb.AppendLine("> Verdict: **$verdict**")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Overview")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- **Task**: $((Split-Path $TaskDir -Leaf))")
    [void]$sb.AppendLine("- **Vault**: $vaultPath")
    [void]$sb.AppendLine("- **Scope**: $($prd.scope)")
    [void]$sb.AppendLine("- **Items found**: $($prd.items.Count)")
    [void]$sb.AppendLine("- **Patches**: $($results.validation.pass)/$($results.validation.total) PASS")
    [void]$sb.AppendLine("- **Verification**: $($results.verification.pass)/$($results.verification.total) PASS")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Patch validation (Phase 2.5)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| File | Status |")
    [void]$sb.AppendLine("|------|--------|")
    foreach ($d in $results.validation.details) {
        [void]$sb.AppendLine("| $($d.file) | $($d.status) |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## R1-R6 verification (Phase 3)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Item | File | R1 | R2 | R3 | R4 | R5 | R6 | Verdict |")
    [void]$sb.AppendLine("|------|------|----|----|----|----|----|----|---------|")
    foreach ($d in $results.verification.details) {
        $r = $d.rules
        [void]$sb.AppendLine("| $($d.id) | $($d.file) | $($r.R1) | $($r.R2) | $($r.R3) | $($r.R4) | $($r.R5) | $($r.R6) | $($d.status) |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Verdict")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**$verdict**")
    [void]$sb.AppendLine("")

    [System.IO.File]::WriteAllText($summaryPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  wrote: $summaryPath" -ForegroundColor Green

    # Also write runner-results.json
    $resultsPath = Join-Path $TaskDir "runner-results.json"
    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultsPath -Encoding utf8
    Write-Host "  wrote: $resultsPath" -ForegroundColor Green
}

# ============================================================
# v0.7: WRITE JOURNAL (autonomous mode + human-gate review)
# 写 journal-{task}-{ts}.md 到 workspace/loop/journals/
# 不入 git（按 v0.5 4 决策隔离原则）
# ============================================================
function Invoke-WriteJournal {
    param([bool]$OverallPass, [string]$Decision, [string]$Mode)

    if (-not $journalEnabled) { return }

    $journalFullDir = Join-Path $ScriptDir $journalDir
    if (-not (Test-Path $journalFullDir)) {
        New-Item -ItemType Directory -Force -Path $journalFullDir | Out-Null
    }
    $tsCompact = Get-Date -Format "yyyyMMdd-HHmmss"
    $journalPath = Join-Path $journalFullDir "journal-$((Split-Path $TaskDir -Leaf))-$tsCompact.md"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Loop Journal — $((Split-Path $TaskDir -Leaf))")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Generated: $([DateTimeOffset]::Now.ToString('yyyy-MM-ddTHH:mm:sszzz'))")
    [void]$sb.AppendLine("> Mode: **$Mode**")
    [void]$sb.AppendLine("> Decision: **$Decision**")
    [void]$sb.AppendLine("> Verdict: **$(if ($OverallPass) { 'ALL PASS' } else { 'SOME FAIL' })**")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Task")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- Task: $((Split-Path $TaskDir -Leaf))")
    [void]$sb.AppendLine("- Vault: $vaultPath")
    [void]$sb.AppendLine("- Scope: $($prd.scope)")
    [void]$sb.AppendLine("- Items: $($prd.items.Count)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Patch Validation (Phase 2.5)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| File | Status | Output |")
    [void]$sb.AppendLine("|------|--------|--------|")
    foreach ($d in $results.validation.details) {
        $out = if ($d.output) { ($d.output -replace "`n", " " -replace "\|", "\|") } else { "" }
        [void]$sb.AppendLine("| $($d.file) | $($d.status) | $out |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Verification (Phase 3)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Item | File | Status |")
    [void]$sb.AppendLine("|------|------|--------|")
    foreach ($d in $results.verification.details) {
        [void]$sb.AppendLine("| $($d.id) | $($d.file) | $($d.status) |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Decision")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**$Decision**")
    [void]$sb.AppendLine("")
    if ($Decision -eq "AUTO-APPLIED") {
        [void]$sb.AppendLine("Patches have been auto-applied to vault (not committed).")
        [void]$sb.AppendLine("Run the following to commit:")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine('```powershell')
        [void]$sb.AppendLine("git -C `"$vaultPath`" add $($prd.scope)")
        [void]$sb.AppendLine("git -C `"$vaultPath`" commit -m `"lint: apply $((Split-Path $TaskDir -Leaf))`"")
        [void]$sb.AppendLine('```')
    } elseif ($Decision -eq "PARTIAL-APPLIED") {
        [void]$sb.AppendLine("Some patches auto-applied, some failed. Review vault diff before committing.")
    } elseif ($Decision -eq "NEEDS-REVIEW") {
        [void]$sb.AppendLine("Validation or verification failed. Patches have NOT been applied.")
        [void]$sb.AppendLine("Review the failure details above and re-run after fixes.")
    } else {
        [void]$sb.AppendLine("Manual review required. See details above.")
    }
    [void]$sb.AppendLine("")

    try {
        [System.IO.File]::WriteAllText($journalPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        Write-Host "  wrote: $journalPath" -ForegroundColor Green
    } catch {
        Write-Host "  WARN: journal write failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================
# v0.7: LOG DECISION
# append _log.jsonl entry with decision_by
# 用 .NET 显式无 BOM UTF-8（06-13 硬性规则）
# ============================================================
function Invoke-LogDecision {
    param([string]$Action, [string]$Status, [string]$DecisionBy, [string]$Note)

    $logPath = Join-Path $ScriptDir "_log.jsonl"
    if (-not (Test-Path $logPath)) {
        Write-Host "  WARN: _log.jsonl not found at $logPath" -ForegroundColor Yellow
        return
    }

    $entry = @{
        ts = [DateTimeOffset]::Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
        task = $prd.task_id
        run_id = (Split-Path $TaskDir -Leaf)
        action = $Action
        status = $Status
        items_total = $prd.items.Count
        items_verified = $results.verification.pass
        max_iter = 5
        max_tokens = 500000
        decision_by = $DecisionBy
        note = $Note
    } | ConvertTo-Json -Compress

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::AppendAllText($logPath, $entry + "`n", $utf8NoBom)
        Write-Host "  logged: _log.jsonl  decision_by=$DecisionBy" -ForegroundColor Green
    } catch {
        Write-Host "  WARN: _log.jsonl write failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================
# Run selected actions
# ============================================================
$allPass = $true
# v0.8.0: validationAdvisory 追踪 Phase 2.5 的 advisory 状态
# 默认 true（如果只跑 verify/summarize，未调过 Phase 2.5）
$validationAdvisory = $true

if ($Action -in @("validate", "all")) {
    # v0.8.0: Phase 2.5 永远返回 true（advisory 不阻塞）
    # $script:validationAdvisory 在函数内写入：true=pass, false=advisory warn
    $null = Invoke-PatchValidation
    # validationAdvisory 由函数内部通过 $script: 写入
}

if ($Action -in @("verify", "all")) {
    # v0.8.0: 仍然传 ValidationPassed 给 verifier（告诉它 vault 是否 patched）
    # 但这条信息不再阻塞主 $allPass
    $r = Invoke-Verification -ValidationPassed ($results.validation.fail -eq 0)
    if (-not $r) { $allPass = $false }
}

if ($Action -in @("summarize", "all")) {
    Invoke-Summarize -OverallPass $allPass
}

# ============================================================
# v0.8.0: AUTONOMOUS MODE — auto-apply + journal + log
# Phase 2.5 改 advisory 后决策矩阵:
#   - Phase 3 allPass + advisory pass  → AUTO-APPLIED
#   - Phase 3 allPass + advisory warn  → NEEDS-REVIEW（避免 vault 状态未知时 apply 造成污染）
#   - Phase 3 fail                      → NEEDS-REVIEW
# ============================================================
if ($executionMode -eq "autonomous" -and $allPass -and $autoApply) {
    if (-not $validationAdvisory) {
        # Phase 3 pass 但 Phase 2.5 有 advisory warn → 降级到 NEEDS-REVIEW
        Write-Host ""
        Write-Host "[v0.8.0] Phase 2.5 advisory warn — downgrading to NEEDS-REVIEW (avoid dirty vault)" -ForegroundColor Yellow
        if ($journalEnabled) {
            Invoke-WriteJournal -OverallPass $allPass -Decision "NEEDS-REVIEW" -Mode $executionMode
        }
        Invoke-LogDecision -Action "advisory-downgrade" -Status "warn" -DecisionBy $decisionByAutonomous -Note "v0.8.0: Phase 2.5 advisory warn, Phase 3 pass — kept NEEDS-REVIEW for human review"
    } else {
        Write-Host ""
        Write-Host "[v0.8.1] Autonomous mode — auto-applying patches with all-or-nothing rollback" -ForegroundColor Magenta
        Push-Location $vaultPath
        try {
            $applied = 0
            $rollbackTriggered = $false
            $rollbackFiles = @()
            $failedPatch = ""
            $patches = @(Get-ChildItem $proposedDir -Filter "*.patch")

            # v0.8.1: snapshot 阶段——从所有 patch 的 hunk 里提取要改的文件路径
            # git apply 失败时统一 git checkout 这些文件
            $affectedFiles = @()
            foreach ($patch in $patches) {
                # 从 patch header 读 "diff --git a/<file> b/<file>"
                $headerLine = Get-Content $patch.FullName -TotalCount 1 -ErrorAction SilentlyContinue
                if ($headerLine -match '^diff --git a/(.+?) b/(.+?)$') {
                    $affectedFiles += $Matches[2]
                }
            }
            $affectedFiles = @($affectedFiles | Select-Object -Unique)
            Write-Host "  [snapshot] affected files: $($affectedFiles.Count)" -ForegroundColor DarkGray

            foreach ($patch in $patches) {
                $exitCode = 0
                try {
                    & git apply $patch.FullName 2>&1 | Out-Null
                    $exitCode = $LASTEXITCODE
                } catch {
                    Write-Host "  FATAL-APPLY  $($patch.Name) — $($_.Exception.Message)" -ForegroundColor Red
                    $exitCode = 1
                }
                if ($exitCode -eq 0) {
                    $applied++
                    Write-Host "  APPLIED  $($patch.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  FAIL-APPLY  $($patch.Name)" -ForegroundColor Red
                    $rollbackTriggered = $true
                    $failedPatch = $patch.Name
                    break  # v0.8.1: any fail = break, rollback all
                }
            }

            # v0.8.1: rollback 阶段
            if ($rollbackTriggered -and $affectedFiles.Count -gt 0) {
                Write-Host "  [rollback] git checkout HEAD -- $($affectedFiles.Count) files (failed: $failedPatch)" -ForegroundColor Yellow
                $rollbackFiles = $affectedFiles
                foreach ($f in $affectedFiles) {
                    $rbCode = 0
                    try {
                        & git checkout HEAD -- $f 2>&1 | Out-Null
                        $rbCode = $LASTEXITCODE
                    } catch {
                        Write-Host "    ROLLBACK-FAIL  $f — $($_.Exception.Message)" -ForegroundColor Red
                        $rbCode = 1
                    }
                    if ($rbCode -eq 0) {
                        Write-Host "    ROLLED-BACK  $f" -ForegroundColor Green
                    }
                }
            }

            # v0.8.1: decision 矩阵
            if ($rollbackTriggered) {
                $decision = "ROLLBACK-APPLIED"
                $status = "rolled-back"
                $note = "v0.8.1: apply failed at $failedPatch, rolled back $($rollbackFiles.Count) files. Vault unchanged."
            } elseif ($applied -eq $patches.Count) {
                $decision = "AUTO-APPLIED"
                $status = "ok"
                $note = "v0.8.1 autonomous mode auto-applied $applied/$($patches.Count) patches to vault (not committed)"
            } else {
                $decision = "PARTIAL-APPLIED"
                $status = "partial"
                $note = "v0.8.1: applied=$applied total=$($patches.Count) (no failures but partial)"
            }

            if ($journalEnabled) {
                Invoke-WriteJournal -OverallPass $allPass -Decision $decision -Mode $executionMode
            }
            Invoke-LogDecision -Action "applied-autonomous" -Status $status -DecisionBy $decisionByAutonomous -Note $note
        } finally {
            Pop-Location
        }
    }
}
elseif ($executionMode -eq "human-gate" -or (-not $allPass)) {
    # human-gate or fail path: write journal for next-day review
    if ($journalEnabled) {
        if ($allPass) { $decision = "READY-TO-APPLY" } else { $decision = "NEEDS-REVIEW" }
        Invoke-WriteJournal -OverallPass $allPass -Decision $decision -Mode $executionMode
    }
}

# Final
Write-Host ""
Write-Host "=== Final ===" -ForegroundColor Cyan
Write-Host "Validation:   $($results.validation.pass)/$($results.validation.total) PASS"
Write-Host "Verification: $($results.verification.pass)/$($results.verification.total) PASS"
Write-Host "Overall:      $(if ($allPass) { 'PASS' } else { 'FAIL' })"
Write-Host ""

if ($allPass) {
    $results.exitCode = 0
} else {
    $results.exitCode = 1
}
# v0.8.2: rewrite runner-results.json with exitCode (for concurrent parent to read)
$resultsPath = Join-Path $TaskDir "runner-results.json"
$resultsJsonText = $results | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($resultsPath, $resultsJsonText, [System.Text.UTF8Encoding]::new($false))
exit $results.exitCode
