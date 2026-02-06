#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup script for Copilot CLI configuration, skills, and external repos.

.DESCRIPTION
    Backs up existing ~/.copilot/ config, symlinks config files, patches config.json
    with portable settings, symlinks local custom skills, clones/pulls external skill
    repos, and links their skills into ~/.copilot/skills/.

    Idempotent — safe to re-run at any time.

.EXAMPLE
    ./setup.ps1
#>

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================
$repoRoot = $PSScriptRoot
$repoCopilotDir = Join-Path $repoRoot ".copilot"
$repoSkillsDir = Join-Path $repoCopilotDir "skills"
$externalDir = Join-Path $repoRoot "external"

$copilotHome = Join-Path $env:USERPROFILE ".copilot"
$copilotSkillsHome = Join-Path $copilotHome "skills"
$configJsonPath = Join-Path $copilotHome "config.json"
$portableJsonPath = Join-Path $repoCopilotDir "config.portable.json"

# Config files to symlink (file symlinks)
$configFileLinks = @(
    @{ Name = "copilot-instructions.md" },
    @{ Name = "mcp.json" }
)

# Keys allowed to be patched from config.portable.json into config.json
$portableAllowedKeys = @(
    "banner", "model", "render_markdown", "theme", "experimental", "reasoning_effort"
)

# External skill repositories
$externalRepos = @(
    @{
        Name        = "anthropic"
        DisplayName = "anthropics/skills"
        Repo        = "https://github.com/anthropics/skills.git"
        CloneDir    = "anthropic-skills"
        SkillsSubdir = "skills"
    },
    @{
        Name        = "github"
        DisplayName = "github/awesome-copilot"
        Repo        = "https://github.com/github/awesome-copilot.git"
        CloneDir    = "awesome-copilot"
        SkillsSubdir = "skills"
    }
)

# =============================================================================
# Counters for summary
# =============================================================================
$script:summary = [ordered]@{
    BackedUp          = $false
    ConfigFilesLinked = @()
    ConfigFilesSkipped = @()
    ConfigPatched     = $false
    TrustedFolderAdded = $false
    BeadsRemoved      = $false
    SkillsCreated     = @()
    SkillsExisted     = @()
    SkillsSkipped     = @()
    SkillsFailed      = @()
    ExternalCloned    = @()
    ExternalPulled    = @()
    ExternalFailed    = @()
    ConflictsResolved = @()
}

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Write-Success { param([string]$Text) Write-Color "  ✓ $Text" "Green" }
function Write-Info    { param([string]$Text) Write-Color "  ℹ $Text" "Cyan" }
function Write-Warn    { param([string]$Text) Write-Color "  ⚠ $Text" "Yellow" }
function Write-Err     { param([string]$Text) Write-Color "  ✗ $Text" "Red" }
function Write-Step    { param([string]$Text) Write-Host ""; Write-Color "▸ $Text" "Cyan" }

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

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

function Create-FileSymlink {
    <#
    .SYNOPSIS
        Create a file symlink. Returns: created | exists | skipped | ask
    #>
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [string]$DisplayName
    )

    if (Test-Path $LinkPath) {
        if (Test-IsReparsePoint $LinkPath) {
            $existing = Get-LinkTarget $LinkPath
            $resolvedTarget = [System.IO.Path]::GetFullPath($TargetPath)
            $resolvedExisting = if ($existing) { [System.IO.Path]::GetFullPath($existing) } else { "" }
            if ($resolvedExisting -eq $resolvedTarget) {
                return "exists"
            }
            # Wrong target — remove and re-create
            Remove-Item $LinkPath -Force
        } else {
            # Real file exists — ask user
            Write-Warn "$DisplayName already exists as a real file at $LinkPath"
            $answer = Read-Host "    Replace with symlink? [y/N]"
            if ($answer -ne "y" -and $answer -ne "Y") {
                return "skipped"
            }
            Remove-Item $LinkPath -Force
        }
    }

    cmd /c mklink "$LinkPath" "$TargetPath" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return "created" }

    # Fallback: try PowerShell New-Item
    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force | Out-Null
        return "created"
    } catch {
        return "failed"
    }
}

function Create-DirJunction {
    <#
    .SYNOPSIS
        Create a directory junction. Returns: created | exists | skipped | failed
    #>
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [string]$DisplayName,
        [switch]$AskBeforeReplace
    )

    if (Test-Path $LinkPath) {
        if (Test-IsReparsePoint $LinkPath) {
            $existing = Get-LinkTarget $LinkPath
            $resolvedTarget = [System.IO.Path]::GetFullPath($TargetPath)
            $resolvedExisting = if ($existing) { [System.IO.Path]::GetFullPath($existing) } else { "" }
            if ($resolvedExisting -eq $resolvedTarget) {
                return "exists"
            }
            # Wrong target — remove and re-create
            cmd /c rmdir "$LinkPath" 2>&1 | Out-Null
        } else {
            if ($AskBeforeReplace) {
                Write-Warn "$DisplayName already exists as a real directory at $LinkPath"
                $answer = Read-Host "    Replace with junction? [y/N]"
                if ($answer -ne "y" -and $answer -ne "Y") {
                    return "skipped"
                }
            }
            Remove-Item $LinkPath -Recurse -Force
        }
    }

    cmd /c mklink /J "$LinkPath" "$TargetPath" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return "created"
    } else {
        return "failed"
    }
}

function Clone-Or-Pull-Repo {
    param(
        [string]$RepoUrl,
        [string]$TargetPath,
        [string]$DisplayName
    )

    if (Test-Path (Join-Path $TargetPath ".git")) {
        Push-Location $TargetPath
        try {
            git pull --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "$DisplayName — failed to pull (may be offline)"
                return "pull-failed"
            }
            return "pulled"
        } finally {
            Pop-Location
        }
    } else {
        $parentDir = Split-Path $TargetPath -Parent
        Ensure-Directory $parentDir
        git clone --quiet $RepoUrl $TargetPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Err "Failed to clone $DisplayName"
            Write-Color "    You can manually clone:" "Yellow"
            Write-Color "      git clone $RepoUrl $TargetPath" "Cyan"
            Write-Host ""
            return "clone-failed"
        }
        return "cloned"
    }
}

function Get-SkillFolders {
    <#
    .SYNOPSIS
        Return skill folder objects from a directory (folders containing SKILL.md).
    #>
    param([string]$BasePath)

    $skills = @()
    if (Test-Path $BasePath) {
        Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName "SKILL.md")) {
                $skills += @{ Name = $_.Name; Path = $_.FullName }
            }
        }
    }
    return $skills
}

# =============================================================================
# Main Script
# =============================================================================

Write-Host ""
Write-Color "📦 Copilot Config & Skills Setup" "Cyan"
Write-Color "=================================" "Cyan"
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Backup ~/.copilot/
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 1: Backup existing ~/.copilot/"

if (Test-Path $copilotHome) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $env:USERPROFILE ".copilot-backup-$timestamp"
    Ensure-Directory $backupDir

    # Back up config files (not sessions/logs/caches)
    $configFiles = @("config.json", "copilot-instructions.md", "mcp.json")
    foreach ($f in $configFiles) {
        $src = Join-Path $copilotHome $f
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $backupDir $f) -Force
        }
    }

    # Back up skills directory
    $skillsSrc = $copilotSkillsHome
    if (Test-Path $skillsSrc) {
        $skillsBackup = Join-Path $backupDir "skills"
        Ensure-Directory $skillsBackup
        # Copy junction metadata (dir listing), not recursing into targets
        Get-ChildItem -Path $skillsSrc -Directory | ForEach-Object {
            if (Test-IsReparsePoint $_.FullName) {
                $target = Get-LinkTarget $_.FullName
                # Record the junction target in a manifest
                "$($_.Name) -> $target" | Out-File -Append (Join-Path $skillsBackup "_junctions.txt")
            } else {
                Copy-Item $_.FullName (Join-Path $skillsBackup $_.Name) -Recurse -Force
            }
        }
    }

    Write-Success "Backed up to $backupDir"
    $script:summary.BackedUp = $true
} else {
    Write-Info "No existing ~/.copilot/ to back up"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Ensure directories exist
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 2: Ensure directories"

Ensure-Directory $copilotHome
Ensure-Directory $copilotSkillsHome
Write-Success "~/.copilot/ and ~/.copilot/skills/ exist"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Symlink config files
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 3: Symlink config files"

foreach ($cfg in $configFileLinks) {
    $targetPath = Join-Path $repoCopilotDir $cfg.Name
    $linkPath = Join-Path $copilotHome $cfg.Name

    if (-not (Test-Path $targetPath)) {
        Write-Warn "$($cfg.Name) — source not found in repo, skipping"
        continue
    }

    $result = Create-FileSymlink -LinkPath $linkPath -TargetPath $targetPath -DisplayName $cfg.Name

    switch ($result) {
        "created" {
            Write-Success "$($cfg.Name) → linked"
            $script:summary.ConfigFilesLinked += $cfg.Name
        }
        "exists" {
            Write-Info "$($cfg.Name) — already linked correctly"
        }
        "skipped" {
            Write-Warn "$($cfg.Name) — skipped (user declined)"
            $script:summary.ConfigFilesSkipped += $cfg.Name
        }
        "failed" {
            Write-Err "$($cfg.Name) — failed to create symlink"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Patch config.json with portable settings
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 4: Patch config.json"

# Load or create config.json
if (Test-Path $configJsonPath) {
    $configJson = Get-Content $configJsonPath -Raw | ConvertFrom-Json
} else {
    $configJson = [PSCustomObject]@{}
}

# Load portable settings
if (Test-Path $portableJsonPath) {
    $portable = Get-Content $portableJsonPath -Raw | ConvertFrom-Json

    foreach ($key in $portableAllowedKeys) {
        $val = $portable.PSObject.Properties[$key]
        if ($val) {
            if ($configJson.PSObject.Properties[$key]) {
                $configJson.$key = $val.Value
            } else {
                $configJson | Add-Member -NotePropertyName $key -NotePropertyValue $val.Value
            }
        }
    }

    $configJson | ConvertTo-Json -Depth 10 | Set-Content $configJsonPath -Encoding UTF8
    Write-Success "Patched config.json with portable settings"
    $script:summary.ConfigPatched = $true
} else {
    Write-Warn "config.portable.json not found in repo — skipping patch"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Add repo path to trusted_folders
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 5: Trusted folders"

$configJson = Get-Content $configJsonPath -Raw | ConvertFrom-Json
$resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRoot)

if (-not $configJson.PSObject.Properties["trusted_folders"]) {
    $configJson | Add-Member -NotePropertyName "trusted_folders" -NotePropertyValue @()
}

# Ensure it's an array
$trustedFolders = @($configJson.trusted_folders)

$alreadyTrusted = $false
foreach ($f in $trustedFolders) {
    if ([System.IO.Path]::GetFullPath($f) -eq $resolvedRepoRoot) {
        $alreadyTrusted = $true
        break
    }
}

if (-not $alreadyTrusted) {
    $trustedFolders += $resolvedRepoRoot
    $configJson.trusted_folders = $trustedFolders
    $configJson | ConvertTo-Json -Depth 10 | Set-Content $configJsonPath -Encoding UTF8
    Write-Success "Added $resolvedRepoRoot to trusted_folders"
    $script:summary.TrustedFolderAdded = $true
} else {
    Write-Info "Repo already in trusted_folders"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Remove beads marketplace
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 6: Remove beads marketplace"

$configJson = Get-Content $configJsonPath -Raw | ConvertFrom-Json

if ($configJson.PSObject.Properties["marketplaces"]) {
    $mp = $configJson.marketplaces

    # Handle object with named keys
    if ($mp -is [PSCustomObject] -and $mp.PSObject.Properties["beads-marketplace"]) {
        $mp.PSObject.Properties.Remove("beads-marketplace")
        $configJson.marketplaces = $mp
        $configJson | ConvertTo-Json -Depth 10 | Set-Content $configJsonPath -Encoding UTF8
        Write-Success "Removed beads-marketplace entry"
        $script:summary.BeadsRemoved = $true
    }
    # Handle array of objects with a key/name field
    elseif ($mp -is [System.Collections.IEnumerable]) {
        $filtered = @($mp | Where-Object {
            $name = if ($_.PSObject.Properties["key"]) { $_.key }
                    elseif ($_.PSObject.Properties["name"]) { $_.name }
                    elseif ($_.PSObject.Properties["id"]) { $_.id }
                    else { $null }
            $name -ne "beads-marketplace"
        })
        if ($filtered.Count -ne @($mp).Count) {
            $configJson.marketplaces = $filtered
            $configJson | ConvertTo-Json -Depth 10 | Set-Content $configJsonPath -Encoding UTF8
            Write-Success "Removed beads-marketplace entry"
            $script:summary.BeadsRemoved = $true
        } else {
            Write-Info "beads-marketplace not found in marketplaces array"
        }
    }
    else {
        Write-Info "No beads-marketplace found"
    }
} else {
    Write-Info "No marketplaces key in config.json"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Symlink local custom skills
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 7: Symlink local custom skills"

$localSkills = Get-SkillFolders -BasePath $repoSkillsDir

if ($localSkills.Count -eq 0) {
    Write-Info "No local skills found in $repoSkillsDir"
} else {
    foreach ($skill in $localSkills) {
        $linkPath = Join-Path $copilotSkillsHome $skill.Name
        $result = Create-DirJunction -LinkPath $linkPath -TargetPath $skill.Path -DisplayName $skill.Name -AskBeforeReplace

        switch ($result) {
            "created" {
                Write-Success "$($skill.Name)"
                $script:summary.SkillsCreated += $skill.Name
            }
            "exists" {
                Write-Info "$($skill.Name) — already linked"
                $script:summary.SkillsExisted += $skill.Name
            }
            "skipped" {
                Write-Warn "$($skill.Name) — skipped (real dir, user declined)"
                $script:summary.SkillsSkipped += $skill.Name
            }
            "failed" {
                Write-Err "$($skill.Name) — junction failed"
                $script:summary.SkillsFailed += $skill.Name
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Clone/pull external skill repos and symlink
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 8: External skill repositories"

# Track all skills for conflict detection: name -> list of @{Source; Path}
$allSkills = @{}

# Register local skills first (local wins by default)
foreach ($skill in $localSkills) {
    $allSkills[$skill.Name] = @(
        @{ Source = "local"; DisplayName = "Local skills"; Path = $skill.Path }
    )
}

foreach ($repo in $externalRepos) {
    $clonePath = Join-Path $externalDir $repo.CloneDir
    $skillsPath = Join-Path $clonePath $repo.SkillsSubdir

    $cloneResult = Clone-Or-Pull-Repo -RepoUrl $repo.Repo -TargetPath $clonePath -DisplayName $repo.DisplayName

    switch ($cloneResult) {
        "cloned" {
            Write-Success "$($repo.DisplayName) — cloned"
            $script:summary.ExternalCloned += $repo.DisplayName
        }
        "pulled" {
            Write-Success "$($repo.DisplayName) — updated"
            $script:summary.ExternalPulled += $repo.DisplayName
        }
        { $_ -match "failed" } {
            Write-Err "$($repo.DisplayName) — $cloneResult"
            $script:summary.ExternalFailed += $repo.DisplayName
            continue
        }
    }

    $extSkills = Get-SkillFolders -BasePath $skillsPath
    Write-Info "$($repo.DisplayName): $($extSkills.Count) skills found"

    foreach ($skill in $extSkills) {
        if (-not $allSkills.ContainsKey($skill.Name)) {
            $allSkills[$skill.Name] = @()
        }
        $allSkills[$skill.Name] += @{
            Source      = $repo.Name
            DisplayName = $repo.DisplayName
            Path        = $skill.Path
        }
    }
}

# Detect conflicts and resolve — local wins by default
Write-Host ""
$externalToLink = @{}  # name -> skill info to link

foreach ($skillName in ($allSkills.Keys | Sort-Object)) {
    $sources = $allSkills[$skillName]

    # Already linked as local skill? Skip external.
    $localSource = $sources | Where-Object { $_.Source -eq "local" }
    $externalSources = @($sources | Where-Object { $_.Source -ne "local" })

    if ($localSource -and $externalSources.Count -gt 0) {
        # Conflict: local wins
        $extNames = ($externalSources | ForEach-Object { $_.DisplayName }) -join ", "
        Write-Warn "$skillName — conflict with $extNames (local wins)"
        $script:summary.ConflictsResolved += "$skillName (local wins over $extNames)"
        continue
    }

    if ($externalSources.Count -gt 1) {
        # Conflict between external sources — pick first
        Write-Warn "$skillName — conflict between externals, using $($externalSources[0].DisplayName)"
        $externalToLink[$skillName] = $externalSources[0]
        $otherNames = ($externalSources[1..($externalSources.Count-1)] | ForEach-Object { $_.DisplayName }) -join ", "
        $script:summary.ConflictsResolved += "$skillName ($($externalSources[0].DisplayName) wins over $otherNames)"
        continue
    }

    if ($externalSources.Count -eq 1 -and -not $localSource) {
        $externalToLink[$skillName] = $externalSources[0]
    }
}

# Link external skills
foreach ($skillName in ($externalToLink.Keys | Sort-Object)) {
    $skillInfo = $externalToLink[$skillName]
    $linkPath = Join-Path $copilotSkillsHome $skillName

    $result = Create-DirJunction -LinkPath $linkPath -TargetPath $skillInfo.Path -DisplayName "$skillName ($($skillInfo.DisplayName))" -AskBeforeReplace

    switch ($result) {
        "created" {
            Write-Success "$skillName ($($skillInfo.DisplayName))"
            $script:summary.SkillsCreated += $skillName
        }
        "exists" {
            Write-Info "$skillName — already linked"
            $script:summary.SkillsExisted += $skillName
        }
        "skipped" {
            Write-Warn "$skillName — skipped"
            $script:summary.SkillsSkipped += $skillName
        }
        "failed" {
            Write-Err "$skillName — junction failed"
            $script:summary.SkillsFailed += $skillName
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Summary
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Color "═══════════════════════════════════" "Cyan"
Write-Color "  ✨ Setup Complete" "Green"
Write-Color "═══════════════════════════════════" "Cyan"
Write-Host ""

if ($script:summary.BackedUp) {
    Write-Color "  Backup:           ~/.copilot-backup-$timestamp/" "White"
}

$linkedCount = $script:summary.ConfigFilesLinked.Count
$skippedCfg  = $script:summary.ConfigFilesSkipped.Count
if ($linkedCount -gt 0 -or $skippedCfg -gt 0) {
    Write-Color "  Config symlinks:  $linkedCount linked, $skippedCfg skipped" "White"
}

if ($script:summary.ConfigPatched) {
    Write-Color "  Config patched:   $($portableAllowedKeys -join ', ')" "White"
}

if ($script:summary.TrustedFolderAdded) {
    Write-Color "  Trusted folder:   $resolvedRepoRoot (added)" "White"
}

if ($script:summary.BeadsRemoved) {
    Write-Color "  Marketplace:      beads-marketplace removed" "White"
}

$createdCount = $script:summary.SkillsCreated.Count
$existedCount = $script:summary.SkillsExisted.Count
$skippedCount = $script:summary.SkillsSkipped.Count
$failedCount  = $script:summary.SkillsFailed.Count

Write-Host ""
Write-Color "  Skills:" "Cyan"
if ($createdCount -gt 0) { Write-Color "    Created:        $createdCount" "Green" }
if ($existedCount -gt 0) { Write-Color "    Already linked: $existedCount" "Cyan" }
if ($skippedCount -gt 0) { Write-Color "    Skipped:        $skippedCount" "Yellow" }
if ($failedCount  -gt 0) { Write-Color "    Failed:         $failedCount" "Red" }
if ($createdCount -eq 0 -and $existedCount -eq 0 -and $skippedCount -eq 0 -and $failedCount -eq 0) {
    Write-Color "    (none)" "Gray"
}

$extCloned = $script:summary.ExternalCloned.Count
$extPulled = $script:summary.ExternalPulled.Count
$extFailed = $script:summary.ExternalFailed.Count
if ($extCloned -gt 0 -or $extPulled -gt 0 -or $extFailed -gt 0) {
    Write-Host ""
    Write-Color "  External repos:" "Cyan"
    if ($extCloned -gt 0) { Write-Color "    Cloned:         $extCloned" "Green" }
    if ($extPulled -gt 0) { Write-Color "    Updated:        $extPulled" "Cyan" }
    if ($extFailed -gt 0) { Write-Color "    Failed:         $extFailed" "Red" }
}

if ($script:summary.ConflictsResolved.Count -gt 0) {
    Write-Host ""
    Write-Color "  Conflicts resolved:" "Yellow"
    foreach ($c in $script:summary.ConflictsResolved) {
        Write-Color "    • $c" "Yellow"
    }
}

Write-Host ""
