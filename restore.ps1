#!/usr/bin/env pwsh
# Undo what setup.ps1 did: remove symlinks/junctions in ~/.copilot/ that point
# into this repo. Optionally restore from the most recent backup.
# Safe: only removes symlinks/junctions, never deletes real files/directories.

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$externalDir = Join-Path $repoRoot "external"
$copilotHome = Join-Path $env:USERPROFILE ".copilot"

$ownedRoots = @(
    [System.IO.Path]::GetFullPath($repoRoot),
    [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE "repos\skills")),
    [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE "repos\copilot-config")),
    [System.IO.Path]::GetFullPath($externalDir)
) | Select-Object -Unique

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}
function Write-Success { param([string]$Text) Write-Color "  ✓ $Text" "Green" }
function Write-Info    { param([string]$Text) Write-Color "  ℹ $Text" "Cyan" }
function Write-Warn    { param([string]$Text) Write-Color "  ⚠ $Text" "Yellow" }
function Write-Err     { param([string]$Text) Write-Color "  ✗ $Text" "Red" }
function Write-Step    { param([string]$Text) Write-Host ""; Write-Color "▸ $Text" "Cyan" }

function Test-IsReparsePoint {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item $Path -Force
    return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Get-LinkTarget {
    param([string]$Path)
    try {
        $item = Get-Item $Path -Force
        $target = $item.Target
        if ($target -is [System.Collections.IEnumerable] -and $target -isnot [string]) {
            $target = $target[0]
        }
        return $target
    } catch {
        return $null
    }
}

function Test-PointsIntoOwnedRoot {
    param([string]$Target)
    if (-not $Target) { return $false }
    $resolved = [System.IO.Path]::GetFullPath($Target)
    foreach ($root in $ownedRoots) {
        if ($resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Remove-OwnedLinks {
    param([string]$ScanDir)
    $result = @()
    Get-ChildItem -Path $ScanDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-IsReparsePoint $_.FullName) {
            $target = Get-LinkTarget $_.FullName
            if (Test-PointsIntoOwnedRoot $target) {
                $relName = $_.FullName.Replace($copilotHome, "~/.copilot")
                Write-Warn "Removing: $relName → $target"
                if ($_.PSIsContainer) { cmd /c rmdir "$($_.FullName)" 2>&1 | Out-Null }
                else { Remove-Item $_.FullName -Force }
                $result += $relName
            }
        }
    }
    return $result
}

Write-Host ""
Write-Color "🔄 Copilot Config & Skills Restore" "Cyan"
Write-Color "====================================" "Cyan"

$removed = @()

# Step 1: Find and remove symlinks/junctions in ~/.copilot/
Write-Step "Step 1: Scan ~/.copilot/ for symlinks pointing into this repo"

if (-not (Test-Path $copilotHome)) {
    Write-Info "~/.copilot/ does not exist — nothing to do"
} else {
    $removed += @(Remove-OwnedLinks $copilotHome)

    $skillsDir = Join-Path $copilotHome "skills"
    if (Test-Path $skillsDir) {
        $removed += @(Remove-OwnedLinks $skillsDir)
        # Remove skills dir if now empty
        if (@(Get-ChildItem -Path $skillsDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $skillsDir -Force
            Write-Info "Removed empty ~/.copilot/skills/"
        }
    }
}

# Step 2: Offer to restore from backup
Write-Step "Step 2: Check for backups"

$backups = @(Get-ChildItem -Path $env:USERPROFILE -Directory -Filter ".copilot-backup-*" -Force -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending)

if ($backups.Count -gt 0) {
    $latest = $backups[0]
    Write-Info "Found $($backups.Count) backup(s). Most recent: $($latest.Name)"
    $answer = Read-Host "  Restore from $($latest.Name)? [y/N]"

    if ($answer -eq "y" -or $answer -eq "Y") {
        Get-ChildItem -Path $latest.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $copilotHome $_.Name
            if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest -Force; Write-Success "Restored $($_.Name)" }
            else { Write-Info "$($_.Name) already exists, skipping" }
        }
        $backupSkills = Join-Path $latest.FullName "skills"
        if (Test-Path $backupSkills) {
            $skillsDir = Join-Path $copilotHome "skills"
            if (-not (Test-Path $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }
            Get-ChildItem -Path $backupSkills -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $dest = Join-Path $skillsDir $_.Name
                if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest -Recurse -Force; Write-Success "Restored skill: $($_.Name)" }
            }
        }
        Write-Success "Restore complete"
    } else {
        Write-Info "Skipping restore"
    }
} else {
    Write-Info "No ~/.copilot-backup-* directories found"
}

# Summary
Write-Host ""
Write-Color "═══════════════════════════════════" "Cyan"
Write-Color "  ✨ Restore Complete" "Green"
Write-Color "═══════════════════════════════════" "Cyan"
Write-Host ""
if ($removed.Count -eq 0) {
    Write-Color "  No symlinks/junctions were found pointing into this repo." "White"
} else {
    Write-Color "  Removed $($removed.Count) symlink(s)/junction(s):" "White"
    foreach ($r in $removed) { Write-Color "    • $r" "Yellow" }
}
Write-Host ""
