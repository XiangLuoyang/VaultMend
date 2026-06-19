# Loopen — Obsidian vault quality audit + auto-fix toolchain
# https://github.com/XiangLuoyang/Loopen
#
# Licensed under the MIT License. See LICENSE in the project root.

# loopen Phase 2 batch (v0.3)
# Process all auto-generated task dirs from phase1-auto.ps1
# For each task dir: read prd.json -> generate patches -> verify -> apply -> commit
#
# Rules supported (auto-generate patches):
# - R2: H1 before abstract -> move H1 after abstract
# - R3: broken wikilinks -> convert [[name]] to [TODO: 待补 name]
# - R1: frontmatter incomplete -> skip (manual, 2 files only)
# - R5: BOM -> skip (0 files)
#
# Usage:
#   powershell -File .\loop\phase2-batch.ps1                # process all
#   powershell -File .\loop\phase2-batch.ps1 -DryRun        # show plan, don't apply
#   powershell -File .\loop\phase2-batch.ps1 -Limit 5       # process only first 5

# === Helper functions ===

function Repair-R2Order {
    param([string]$content)
    
    $lines = $content -split "`n"
    
    $fmEnd = -1; $dashCount = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*$') {
            $dashCount++
            if ($dashCount -eq 2) { $fmEnd = $i; break }
        }
    }
    if ($fmEnd -lt 0) { return $content }
    
    $h1Line = -1
    for ($i = $fmEnd + 1; $i -lt [Math]::Min($fmEnd + 30, $lines.Count); $i++) {
        if ($lines[$i] -match '^#\s+\S') { $h1Line = $i; break }
    }
    if ($h1Line -lt 0) { return $content }
    
    $absLine = -1
    for ($i = $fmEnd + 1; $i -lt [Math]::Min($fmEnd + 30, $lines.Count); $i++) {
        if ($lines[$i] -match '^\s*>\s*\[!abstract\]') { $absLine = $i; break }
    }
    if ($absLine -lt 0) { return $content }
    
    if ($h1Line -ge $absLine) { return $content }
    
    $absEnd = $absLine
    for ($i = $absLine; $i -lt [Math]::Min($absLine + 10, $lines.Count); $i++) {
        if ($lines[$i] -match '^\s*>\s*\[!abstract\]') { $absEnd = $i; continue }
        if ($lines[$i] -match '^\s*>\s+') { $absEnd = $i; continue }
        if ($lines[$i] -match '^\s*>\s*$') { $absEnd = $i; continue }
        break
    }
    
    $h1Content = $lines[$h1Line]
    
    $newLines = @()
    for ($i = 0; $i -lt $h1Line; $i++) { $newLines += $lines[$i] }
    
    $insertIdx = $h1Line + 1
    while ($insertIdx -lt $lines.Count -and $lines[$insertIdx] -match '^\s*$') { $insertIdx++ }
    
    for ($i = $insertIdx; $i -le $absEnd; $i++) { $newLines += $lines[$i] }
    
    $newLines += ""
    $newLines += ""
    $newLines += $h1Content
    $newLines += ""
    
    for ($i = $absEnd + 1; $i -lt $lines.Count; $i++) { $newLines += $lines[$i] }
    
    return ($newLines -join "`n")
}

function Repair-R3BrokenWikilinks {
    param(
        [string]$content,
        [string]$vaultPath
    )
    
    $wikilinkPattern = '\[\[([^\]]+)\]\]'
    $matches = [regex]::Matches($content, $wikilinkPattern)
    
    $newContent = $content
    
    foreach ($m in $matches) {
        $wl = $m.Groups[1].Value
        $wlClean = $wl -replace '\|.*$',''
        $target = $wlClean -replace '\\','/'
        $candidates = @(
            (Join-Path $vaultPath "$target.md"),
            (Join-Path $vaultPath ($target -replace '^Wiki/',''))
        )
        $found = $false
        foreach ($c in $candidates) { if (Test-Path $c) { $found = $true; break } }
        if (-not $found) {
            $newContent = $newContent.Replace("[[$wl]]", "[TODO: 待补 $wl]")
        }
    }
    
    return $newContent
}

# === Main script ===

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Parse args (manual, no [CmdletBinding()])
$Limit = 0
$DryRun = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Limit" -and $i + 1 -lt $args.Count) { $Limit = [int]$args[$i+1]; $i++ }
    elseif ($args[$i] -eq "-DryRun") { $DryRun = $true }
}

# Load .looprc.json via .NET (avoid PowerShell UTF-8 -> GBK mojibake)
$loopRcPath = Join-Path $ScriptDir ".looprc.json"
$loopRcJson = [System.IO.File]::ReadAllText($loopRcPath, [System.Text.UTF8Encoding]::new($false))
if ($loopRcJson.Length -gt 0 -and $loopRcJson[0] -eq [char]0xFEFF) { $loopRcJson = $loopRcJson.Substring(1) }
$loopRc = $loopRcJson | ConvertFrom-Json
$vaultPath = $loopRc.defaults.vault_path

# Find all auto task dirs
$autoDirs = Get-ChildItem $ScriptDir -Directory | Where-Object { $_.Name -like "lint-auto-*" } | Sort-Object Name
if ($Limit -gt 0) {
    $autoDirs = $autoDirs | Select-Object -First $Limit
}

Write-Host "[phase2-batch] Found $($autoDirs.Count) auto task dirs (limit=$Limit)" -ForegroundColor Cyan

$processed = 0
$skipped = 0
$failed = 0

foreach ($taskDir in $autoDirs) {
    $taskName = $taskDir.Name
    $subdirs = Get-ChildItem $taskDir.FullName -Directory
    if ($subdirs.Count -eq 0) { 
        $skipped++
        continue 
    }
    $subdir = $subdirs[0]
    $prdPath = Join-Path $subdir.FullName "prd.json"
    
    if (-not (Test-Path $prdPath)) {
        Write-Host "  [SKIP] $taskName (no prd.json)" -ForegroundColor Yellow
        $skipped++
        continue
    }
    
    # Read prd.json via .NET
    $prdJson = [System.IO.File]::ReadAllText($prdPath, [System.Text.UTF8Encoding]::new($false))
    if ($prdJson.Length -gt 0 -and $prdJson[0] -eq [char]0xFEFF) { $prdJson = $prdJson.Substring(1) }
    $prd = $prdJson | ConvertFrom-Json
    $scopeFile = $prd.scope
    $vaultFilePath = Join-Path $vaultPath $scopeFile
    
    if (-not (Test-Path $vaultFilePath)) {
        Write-Host "  [SKIP] $taskName (file not found: $scopeFile)" -ForegroundColor Yellow
        $skipped++
        continue
    }
    
    Write-Host ""
    Write-Host "=== Processing: $taskName ===" -ForegroundColor Cyan
    Write-Host "  scope: $scopeFile"
    Write-Host "  items: $($prd.items.Count)"
    
    $originalContent = [System.IO.File]::ReadAllText($vaultFilePath, [System.Text.UTF8Encoding]::new($false))
    $newContent = $originalContent
    $patched = $false
    
    foreach ($item in $prd.items) {
        $rule = $item.rule
        $line = $item.line
        
        if ($rule -eq "R2") {
            $r2result = Repair-R2Order -content $newContent
            if ($r2result -ne $newContent) { 
                $newContent = $r2result
                $patched = $true
            }
        }
        elseif ($rule -eq "R3") {
            $r3result = Repair-R3BrokenWikilinks -content $newContent -vaultPath $vaultPath
            if ($r3result -ne $newContent) {
                $newContent = $r3result
                $patched = $true
            }
        }
        elseif ($rule -eq "R1") {
            # v0.9 A phase: R1 repaired content is already in proposed-changes/<orig-filename>
            if ($item.repaired_content_path) {
                $repairedFile = Join-Path $ScriptDir $item.repaired_content_path
                if (Test-Path $repairedFile) {
                    $repairedContent = [System.IO.File]::ReadAllText($repairedFile, [System.Text.UTF8Encoding]::new($false))
                    if ($repairedContent -ne $newContent) {
                        $newContent = $repairedContent
                        $patched = $true
                    }
                } else {
                    Write-Host "  [WARN R1] repaired content file missing: $repairedFile"
                }
            } else {
                Write-Host "  [SKIP R1] no repaired_content_path in prd"
            }
        }
        elseif ($rule -eq "R5") {
            Write-Host "  [SKIP R5] BOM present (manual fix needed)"
        }
    }
    
    if (-not $patched) {
        Write-Host "  [SKIP] No patches generated"
        $skipped++
        continue
    }
    
    if ($DryRun) {
        $oldBytes = [System.Text.Encoding]::UTF8.GetByteCount($originalContent)
        $newBytes = [System.Text.Encoding]::UTF8.GetByteCount($newContent)
        Write-Host "  [DRY-RUN] Would write: old=$oldBytes -> new=$newBytes bytes"
        continue
    }
    
    [System.IO.File]::WriteAllText($vaultFilePath, $newContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [APPLIED] $scopeFile"
    $processed++
    
    # Use git -C to avoid PowerShell Set-Location + Chinese path issue
    $oldEAP2 = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
    git -C $vaultPath add $scopeFile 2>$null | Out-Null
    $ErrorActionPreference = $oldEAP2
    
    $commitMsg = "lint: apply $taskName" + "`n`n" +
                 "Auto-applied R2 reorder + R3 broken-wikilink fixes from phase1-auto batch." + "`n" +
                 "Items: $($prd.items.Count)" + "`n" +
                 "Task: $taskName"
    [System.IO.File]::WriteAllText("C:\loop-tmp\commit-msg.txt", $commitMsg, [System.Text.UTF8Encoding]::new($false))
    $oldEAP3 = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
    git -C $vaultPath commit -F "C:\loop-tmp\commit-msg.txt" 2>$null | Out-String | Write-Host
    $ErrorActionPreference = $oldEAP3
}

Write-Host ""
Write-Host "=== Phase 2 batch complete ===" -ForegroundColor Green
Write-Host "  Processed: $processed"
Write-Host "  Skipped:   $skipped"
Write-Host "  Failed:    $failed"
