# Loopen — Obsidian vault quality audit + auto-fix toolchain
# https://github.com/XiangLuoyang/Loopen
#
# Licensed under the MIT License. See LICENSE in the project root.

# loopen Phase 1 auto (v0.3 → v0.9 改 scope)
# v0.2 → v0.3 变化：
# - v0.2: 手动挑 target + 写 prd.json
# - v0.3: 自动扫 vault + 检测 R1/R2/R3/R5 violation + 生成 per-file prd.json + patches
# v0.9 变化：
# - 默认 scope 改为 full（全 vault），不再写死 Wiki/concepts/
# - 加 -Scope 参数可指定子目录（兼容旧行为）
# - 加系统目录跳过（.obsidian / .git / .trash / attachments 等）
# - 修 .looprc.json UTF-8 读取（PS 5.1 系统 codepage bug）
#
# R4 (死文档保护) / R6 (Sources/ 路径) v0.3 仍需手动 (需 LLM 理解内容)
# R1 (frontmatter) / R2 (H1 位置) / R3 (broken wikilink) / R5 (BOM) v0.3 可正则检测
#
# Usage:
#   .\loop\phase1-auto.ps1                            (default: full vault)
#   .\loop\phase1-auto.ps1 -Scope "Wiki/concepts"     (legacy: 仅 Wiki/concepts)
#   .\loop\phase1-auto.ps1 -SkipApplied
#   .\loop\phase1-auto.ps1 -DryRun

[CmdletBinding()]
param(
    [string]$Scope = "full",
    [switch]$SkipApplied,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# v0.9: use .NET API for UTF-8 no-BOM read (avoid PS 5.1 system codepage)
$loopRcPath = Join-Path $ScriptDir ".looprc.json"
$loopRcText = [System.IO.File]::ReadAllText($loopRcPath, [System.Text.UTF8Encoding]::new($false))
$loopRc = $loopRcText | ConvertFrom-Json
$vaultPath = $loopRc.defaults.vault_path

# Build list of already-applied files (from _log.jsonl action=applied)
$logPath = Join-Path $ScriptDir "_log.jsonl"
$appliedFiles = @()
if (Test-Path $logPath) {
    Get-Content $logPath | ForEach-Object {
        try {
            $entry = $_ | ConvertFrom-Json
            if ($entry.action -eq "applied" -and $entry.scope) {
                $appliedFiles += $entry.scope
            }
        } catch {}
    }
}
Write-Host "[phase1-auto] Applied files (will skip with -SkipApplied): $($appliedFiles.Count)"

# v0.9: Scope-aware scan with system dir skip
# Supported scopes: "full" (default), or any vault-relative path like "Wiki/concepts"
$skipDirs = @('.obsidian', '.git', '.trash', '.claude', '.opencode', '.smtcmp_json_db', 'attachments', '.claudian', 'copilot')
if ($Scope -eq "full") {
    $scanRoot = $vaultPath
    $scopeDesc = "full vault (skipping system dirs: $($skipDirs -join ', '))"
} else {
    $scanRoot = Join-Path $vaultPath $Scope
    $scopeDesc = "scope: $Scope"
}
if (-not (Test-Path $scanRoot)) {
    Write-Error "Scan root not found: $scanRoot"
    exit 2
}
$targets = @(Get-ChildItem $scanRoot -Recurse -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object {
    $rel = $_.FullName.Substring($vaultPath.Length + 1) -replace '\\', '/'
    # Filter out files inside skipDirs
    $skip = $false
    foreach ($d in $skipDirs) {
        if ($rel -match "^$([regex]::Escape($d))(/|$)") { $skip = $true; break }
    }
    -not $skip
})
Write-Host "[phase1-auto] Scanning $($targets.Count) .md files in $scopeDesc" -ForegroundColor Cyan

$results = @()
$skippedApplied = 0
$patchPaths = @{}  # v0.9: track R1 patch paths per file

# ============================================================
# v0.9: R1 frontmatter auto-fix
# For files WITH existing frontmatter block but missing fields:
# adds missing fields with sensible defaults.
# Returns @{patch; patchedContent; addedFields} or $null if skip.
# ============================================================
function Repair-R1Frontmatter {
    param([string]$filePath, [string]$fileContent, [string[]]$missing)

    # Only fix in structured dirs; skip Daily/日记/Sources/attachments
    $relForCheck = $filePath.Substring($vaultPath.Length + 1) -replace '\\', '/'
    $skipDirs = @('Daily', '日记', 'Sources', 'skills', 'attachments')
    foreach ($d in $skipDirs) {
        if ($relForCheck -match "^$([regex]::Escape($d))(/|$)") { return $null }
    }

    # Parse frontmatter block
    $regexFm = New-Object System.Text.RegularExpressions.Regex(
        '(?m)^---\r?\n(?<body>.*?)\r?\n---',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $fmMatch = $regexFm.Match($fileContent)
    if (-not $fmMatch.Success) { return $null }

    $fmBody = $fmMatch.Groups['body'].Value
    $fmStart = $fmMatch.Index
    $fmEnd = $fmMatch.Index + $fmMatch.Length

    # Extract title from H1
    $titleVal = "Untitled"
    $titleMatch = [regex]::Match($fileContent, '(?m)^#\s+(.+)$')
    if ($titleMatch.Success) { $titleVal = $titleMatch.Groups[1].Value.Trim() }

    # Build added fields
    $added = @()
    foreach ($field in $missing) {
        switch ($field) {
            'title'    { $added += "title: $titleVal" }
            'created'  { $added += "created: $([DateTime]::Now.ToString('yyyy-MM-dd'))" }
            'updated'  { $added += "updated: $([DateTime]::Now.ToString('yyyy-MM-dd'))" }
            'type'     { $added += "type: document" }
            'status'   { $added += "status: active" }
            'narrative'{ $added += "narrative: analytical" }
            'tags'     { $added += "tags: []" }
            default    { $added += "$($field): `"`"" }
        }
    }

    # Build new content
    $newFmBody = $fmBody.TrimEnd() + "`n" + ($added -join "`n") + "`n"
    $newContent = $fileContent.Substring(0, $fmStart) + "---`n" + $newFmBody + "---`n" + $fileContent.Substring($fmEnd)

    # APPROACH: the "patch" IS the corrected file written to proposed-changes/.
    # phase2-batch.ps1 already handles this pattern for R2 repairs.
    # Here we return @{patchedContent = corrected content} so the caller writes it.
    return @{ patchedContent = $newContent; addedFields = $added; hasPatch = $true }
}










foreach ($f in $targets) {
    $relPath = $f.FullName.Substring($vaultPath.Length + 1) -replace '\\', '/'
    
    if ($SkipApplied -and $appliedFiles -contains $relPath) {
        $skippedApplied++
        continue
    }
    
    # Use a Regex object (not string) — PowerShell 5.1 string-passing has subtle quirks
    $fileContent = [System.IO.File]::ReadAllText($f.FullName, [System.Text.UTF8Encoding]::new($false))
    $fileLines = $fileContent -split "`n"
    
    $items = @()
    
    # === R1: frontmatter completeness ===
    $regexFm = New-Object System.Text.RegularExpressions.Regex('^---\r?\n(?<body>.*?)\r?\n---', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $fmMatch = $regexFm.Match($fileContent)
    if ($fmMatch.Success -and $fmMatch.Groups['body'].Success) {
        $fm = $fmMatch.Groups['body'].Value
        $required = @('title','created','updated','type','status','narrative')
        $missing = @($required | Where-Object { $fm -notmatch "(?m)^$([regex]::Escape($_))\s*:" })
        if ($missing.Count -gt 0) {
            $items += @{
                id = "item-r1"
                type = "R1-frontmatter-incomplete"
                severity = "warn"
                file = $relPath
                line = 1
                rule = "R1"
                fix_action = "add-missing-frontmatter-fields"
                description = "R1 frontmatter missing fields: $($missing -join ', ')"
            }
            # v0.9: generate patch for R1-frontmatter-incomplete
            $r1Result = Repair-R1Frontmatter -filePath $f.FullName -fileContent $fileContent -missing $missing
            if ($r1Result) {
                $patchPaths[$relPath] = $r1Result
                Write-Host "  [R1] auto-patch ready: $($r1Result.addedFields -join ', ')" -ForegroundColor Green
            }
        }
    } else {
        $items += @{
            id = "item-r1"
            type = "R1-no-frontmatter"
            severity = "error"
            file = $relPath
            line = 1
            rule = "R1"
            fix_action = "create-frontmatter-block"
            description = "R1 no frontmatter block found"
        }
    }
    
    # === R2: H1 before abstract callout ===
    # Find end of frontmatter via "---" line scan
    $fmEndLine = -1; $dashCount = 0
    for ($i = 0; $i -lt $fileLines.Count; $i++) {
        if ($fileLines[$i] -match '^---\s*$') {
            $dashCount++
            if ($dashCount -eq 2) { $fmEndLine = $i; break }
        }
    }
    
    if ($fmEndLine -ge 0) {
        $h1Idx = -1; $abstractIdx = -1
        for ($i = $fmEndLine + 1; $i -lt [Math]::Min($fmEndLine + 30, $fileLines.Count); $i++) {
            if ($fileLines[$i] -match '^#\s+\S' -and $h1Idx -lt 0) { $h1Idx = $i }
            if ($fileLines[$i] -match '^\s*>\s*\[!abstract\]' -and $abstractIdx -lt 0) { $abstractIdx = $i }
            if ($h1Idx -ge 0 -and $abstractIdx -ge 0) { break }
        }
        if ($h1Idx -ge 0 -and $abstractIdx -ge 0 -and $h1Idx -lt $abstractIdx) {
            $items += @{
                id = "item-r2"
                type = "R2-abstract-callout-position"
                severity = "warn"
                file = $relPath
                line = $h1Idx + 1
                rule = "R2"
                fix_action = "reorder-move-h1-after-abstract"
                description = "R2 H1 at L$($h1Idx+1) before abstract callout at L$($abstractIdx+1)"
            }
        }
    }
    
    # === R3: broken wikilinks ===
    $regexWl = New-Object System.Text.RegularExpressions.Regex('\[\[([^\]]+)\]\]')
    $wlMatches = $regexWl.Matches($fileContent)
    $brokenList = @()
    foreach ($m in $wlMatches) {
        $wl = $m.Groups[1].Value
        $wlClean = $wl -replace '\|.*$',''
        $target = $wlClean -replace '\\','/'
        $candidates = @(
            (Join-Path $vaultPath "$target.md"),
            (Join-Path $vaultPath ($target -replace '^Wiki/',''))
        )
        $found = $false
        foreach ($c in $candidates) { if (Test-Path $c) { $found = $true; break } }
        if (-not $found) { $brokenList += $wl }
    }
    if ($brokenList.Count -gt 0) {
        $items += @{
            id = "item-r3"
            type = "R3-broken-wikilinks"
            severity = "warn"
            file = $relPath
            line = 0
            rule = "R3"
            fix_action = "convert-broken-wikilinks-to-todo"
            description = "R3 $($brokenList.Count) broken wikilinks: $($brokenList -join ', ')"
        }
    }
    
    # === R5: BOM ===
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $items += @{
            id = "item-r5"
            type = "R5-utf8-bom"
            severity = "warn"
            file = $relPath
            line = 0
            rule = "R5"
            fix_action = "remove-bom"
            description = "R5 UTF-8 BOM present (should be no BOM)"
        }
    }
    
    if ($items.Count -gt 0) {
        $results += @{
            file = $relPath
            fullPath = $f.FullName
            items = $items
            lineCount = $fileLines.Count
        }
    }
}

Write-Host "[phase1-auto] Affected files: $($results.Count)" -ForegroundColor Cyan
Write-Host "[phase1-auto] Skipped (already applied): $skippedApplied"

# Summary by rule
$byRule = @{ R1 = 0; R2 = 0; R3 = 0; R5 = 0 }
foreach ($r in $results) {
    foreach ($item in $r.items) {
        $rule = $item.rule
        if ($byRule.ContainsKey($rule)) { $byRule[$rule]++ }
    }
}
Write-Host ""
Write-Host "=== Rule breakdown ===" -ForegroundColor Cyan
foreach ($k in @('R1','R2','R3','R5')) {
    Write-Host "  $k : $($byRule[$k])"
}

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY-RUN] No task dirs created" -ForegroundColor Yellow
    exit 0
}

# Generate per-file task dirs
$ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
$tsIso = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")

Write-Host ""
Write-Host "[phase1-auto] Generating task dirs..." -ForegroundColor Cyan
$genCount = 0
foreach ($r in $results) {
    $fileName = Split-Path $r.file -Leaf
    $taskName = "lint-auto-$($fileName -replace '\.md$','')"
    $taskDir = Join-Path $ScriptDir "$taskName\$ts"
    $proposedDir = Join-Path $taskDir "proposed-changes"
    New-Item -ItemType Directory -Force -Path $proposedDir | Out-Null
    
    # v0.9: write R1 repaired content directly to proposed-changes/ as the corrected file.
    # phase2-batch.ps1 already handles copying from proposed-changes/ to vault.
    if ($patchPaths.ContainsKey($r.file)) {
        $patchData = $patchPaths[$r.file]
        # Write the frontmatter-corrected content using the original filename in proposed-changes/
        $origFileName = Split-Path $r.file -Leaf
        $repairedFile = Join-Path $proposedDir $origFileName
        [System.IO.File]::WriteAllText($repairedFile, $patchData.patchedContent, [System.Text.UTF8Encoding]::new($false))
        # Add repaired_content_path to each R1 item
        $repairedRelPath = $repairedFile.Substring($ScriptDir.Length + 1) -replace '\\', '/'
        $r.items = @($r.items | ForEach-Object {
            if ($_.rule -eq "R1") {
                $_.repaired_content_path = $repairedRelPath
            }
            $_
        })
    }
    
    $itemsJson = ($r.items | ConvertTo-Json -Depth 5 -Compress)
    $prdObj = @{
        task_id = "$taskName-$ts"
        ts = $tsIso
        vault_path = $vaultPath -replace '\\','/'
        rules_source = "CLAUDE.md"
        scope = $r.file
        items = $r.items
        metadata = @{
            max_iter = 5
            max_tokens = 500000
            timeout_seconds = 1800
            verifier_required = $true
            sources_protected = $true
        }
    }
    $prdJson = $prdObj | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::WriteAllText("$taskDir\prd.json", $prdJson, [System.Text.UTF8Encoding]::new($false))
    
    # Build summary via concatenation (avoid here-string issues)
    $itemLines = ($r.items | ForEach-Object { "- $($_.id): $($_.description)" }) -join "`n"
    $summary = "# Loop Summary -- $taskName (auto-generated)`n`n" +
               "> Generated: $tsIso`n" +
               "> Action: **AUTO_PHASE1**`n" +
               "> Source: phase1-auto.ps1`n" +
               "> Scope: $($r.file)`n" +
               "> Items: $($r.items.Count)`n`n" +
               "## Items`n`n" +
               "$itemLines`n`n" +
               "## Next step`n`n" +
               "Run: run-loop.ps1 -TaskDir `"$taskDir`" -Action all`n"
    [System.IO.File]::WriteAllText("$taskDir\loop-summary.md", $summary, [System.Text.UTF8Encoding]::new($false))
    
    $genCount++
}

Write-Host "[phase1-auto] Generated $genCount task dirs" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: process each task dir via run-loop.ps1, then apply/discard"
