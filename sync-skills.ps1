#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Detect untracked skills in ~/.copilot/skills/ and adopt them into the repo.

.DESCRIPTION
    Scans ~/.copilot/skills/ for real directories (not junctions/symlinks) that
    don't exist in the repo's .copilot/skills/. Offers to move each one into the
    repo and replace it with a junction.

.EXAMPLE
    ./sync-skills.ps1
#>

$ErrorActionPreference = "Stop"

$skillsTarget = Join-Path $env:USERPROFILE ".copilot\skills"
$scriptDir = $PSScriptRoot
$repoSkills = Join-Path $scriptDir ".copilot\skills"

function Write-Success { param([string]$Text) Write-Host "  ✓ $Text" -ForegroundColor Green }
function Write-Info    { param([string]$Text) Write-Host "  $Text" -ForegroundColor Cyan }
function Write-Warn    { param([string]$Text) Write-Host "  ⚠ $Text" -ForegroundColor Yellow }

Write-Host ""
Write-Host "🔍 Scanning for untracked skills..." -ForegroundColor Cyan
Write-Host ""

$untracked = @()

Get-ChildItem -Path $skillsTarget -Directory | ForEach-Object {
    $isLink = $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint
    if (-not $isLink) {
        # Real directory — check if it has a SKILL.md
        $hasSkill = Test-Path (Join-Path $_.FullName "SKILL.md")
        if ($hasSkill) {
            $inRepo = Test-Path (Join-Path $repoSkills $_.Name)
            if (-not $inRepo) {
                $untracked += $_
            }
        }
    }
}

if ($untracked.Count -eq 0) {
    Write-Info "No untracked skills found. Everything is in sync!"
    Write-Host ""
    exit 0
}

Write-Host "  Found $($untracked.Count) untracked skill(s):" -ForegroundColor White
Write-Host ""

$adopted = 0
$skipped = 0

foreach ($skill in $untracked) {
    # Show skill name and description from frontmatter
    $skillMd = Join-Path $skill.FullName "SKILL.md"
    $desc = ""
    $content = Get-Content $skillMd -Raw -ErrorAction SilentlyContinue
    if ($content -match 'description:\s*[''"]?(.+?)[''"]?\s*(\r?\n|$)') {
        $desc = $Matches[1].Substring(0, [Math]::Min(80, $Matches[1].Length))
        if ($Matches[1].Length -gt 80) { $desc += "..." }
    }

    Write-Host "  📦 $($skill.Name)" -ForegroundColor White
    if ($desc) { Write-Host "     $desc" -ForegroundColor Gray }

    $answer = Read-Host "     Adopt into repo? [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $skipped++
        Write-Host ""
        continue
    }

    $destDir = Join-Path $repoSkills $skill.Name

    # Move the real directory into the repo
    Move-Item -Path $skill.FullName -Destination $destDir -Force

    # Create junction back to ~/.copilot/skills/
    cmd /c mklink /J "$($skill.FullName)" "$destDir" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "$($skill.Name) → adopted and linked"
        $adopted++
    } else {
        Write-Warn "$($skill.Name) — moved but junction failed (run setup.ps1 to fix)"
        $adopted++
    }
    Write-Host ""
}

Write-Host "═══════════════════════════════" -ForegroundColor Cyan
Write-Host "  Adopted: $adopted" -ForegroundColor Green
if ($skipped -gt 0) { Write-Host "  Skipped: $skipped" -ForegroundColor Yellow }
Write-Host ""

if ($adopted -gt 0) {
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "    cd $(Split-Path $scriptDir -Leaf)" -ForegroundColor Gray
    Write-Host "    git add -A && git commit -m 'feat: Adopt new skills'" -ForegroundColor Gray
    Write-Host "    git push" -ForegroundColor Gray
    Write-Host ""
}
