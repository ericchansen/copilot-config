#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup script to install Copilot CLI skills from multiple sources.

.DESCRIPTION
    Clones external skill repositories and creates junctions/symlinks to ~/.copilot/skills.
    Handles conflicts interactively, letting users choose which source to use.

.EXAMPLE
    ./setup.ps1
#>

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================
$defaultReposDir = Join-Path $env:USERPROFILE "repos"
$skillsTargetDir = Join-Path $env:USERPROFILE ".copilot\skills"
$scriptDir = $PSScriptRoot

# External repositories to clone (local skills are added separately)
$externalRepos = @(
    @{ 
        Name = "anthropic"
        DisplayName = "anthropics/skills"
        Repo = "https://github.com/anthropics/skills.git"
        CloneDir = "anthropic-skills"
        SkillsSubdir = "skills"
    },
    @{ 
        Name = "github"
        DisplayName = "github/awesome-copilot"
        Repo = "https://github.com/github/awesome-copilot.git"
        CloneDir = "awesome-copilot"
        SkillsSubdir = "skills"
    }
)

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Color {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Success { param([string]$Text) Write-Color "  ✓ $Text" "Green" }
function Write-Info { param([string]$Text) Write-Color "  $Text" "Cyan" }
function Write-Warn { param([string]$Text) Write-Color "  ⚠ $Text" "Yellow" }
function Write-Err { param([string]$Text) Write-Color "  ✗ $Text" "Red" }

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Clone-Or-Pull-Repo {
    param(
        [string]$RepoUrl,
        [string]$TargetPath,
        [string]$DisplayName
    )
    
    if (Test-Path (Join-Path $TargetPath ".git")) {
        # Repo exists, pull latest
        Push-Location $TargetPath
        try {
            git pull --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Failed to pull updates (may be offline)"
            }
        } finally {
            Pop-Location
        }
    } else {
        # Clone fresh
        $parentDir = Split-Path $TargetPath -Parent
        Ensure-Directory $parentDir
        git clone --quiet $RepoUrl $TargetPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Err "Failed to clone $DisplayName"
            Write-Host ""
            Write-Color "  This usually happens because you don't have an SSH key associated" "Yellow"
            Write-Color "  with your GitHub account, or git isn't configured properly." "Yellow"
            Write-Host ""
            Write-Color "  You can manually clone these repositories using HTTPS:" "White"
            Write-Host ""
            Write-Color "    git clone https://github.com/anthropics/skills.git" "Cyan"
            Write-Color "    git clone https://github.com/github/awesome-copilot.git" "Cyan"
            Write-Host ""
            Write-Color "  Clone them into: $parentDir" "White"
            Write-Host ""
            throw "Failed to clone $RepoUrl - see instructions above"
        }
    }
}

function Get-Skills {
    param([string]$BasePath)
    
    $skills = @()
    
    if (Test-Path $BasePath) {
        Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
            $skillMdPath = Join-Path $_.FullName "SKILL.md"
            if (Test-Path $skillMdPath) {
                $skills += @{
                    Name = $_.Name
                    Path = $_.FullName
                }
            }
        }
    }
    
    return $skills
}

function Create-Junction {
    param(
        [string]$LinkPath,
        [string]$TargetPath
    )
    
    if (Test-Path $LinkPath) {
        $item = Get-Item $LinkPath -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Already a junction/symlink - check if it points to the right place
            $existingTarget = (Get-Item $LinkPath).Target
            if ($existingTarget -eq $TargetPath) {
                return "exists"
            }
            # Remove old junction to replace it
            Remove-Item $LinkPath -Force
        } else {
            # It's a real directory, skip
            return "skipped"
        }
    }
    
    # Create junction
    cmd /c mklink /J "$LinkPath" "$TargetPath" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return "created"
    } else {
        return "failed"
    }
}

# =============================================================================
# Main Script
# =============================================================================

Write-Host ""
Write-Color "📦 Copilot Skills Setup" "Cyan"
Write-Color "=======================" "Cyan"
Write-Host ""

# Step 1: Ask where to clone external repositories
Write-Color "External repositories will be cloned to your local machine." "White"
Write-Color "Default location: $defaultReposDir" "Gray"
Write-Host ""

$reposDir = Read-Host "Clone repositories to [$defaultReposDir]"
if ([string]::IsNullOrWhiteSpace($reposDir)) {
    $reposDir = $defaultReposDir
}
# Expand ~ if used
if ($reposDir.StartsWith("~")) {
    $reposDir = Join-Path $env:USERPROFILE $reposDir.Substring(1).TrimStart("/\")
}
$reposDir = [System.IO.Path]::GetFullPath($reposDir)

Write-Host ""

# Build sources list dynamically based on chosen directory
$sources = @(
    @{ 
        Name = "local"
        DisplayName = "Local skills"
        Path = Join-Path $scriptDir "skills"
        Repo = $null
        CloneTo = $null
    }
)

foreach ($repo in $externalRepos) {
    $clonePath = Join-Path $reposDir $repo.CloneDir
    $skillsPath = Join-Path $clonePath $repo.SkillsSubdir
    $sources += @{
        Name = $repo.Name
        DisplayName = $repo.DisplayName
        Path = $skillsPath
        Repo = $repo.Repo
        CloneTo = $clonePath
    }
}

# Step 2: Fetch all repositories
Write-Color "Fetching repositories..." "White"

$allSkills = @{}  # skill name -> list of @{Source; Path}
$sourceStats = @{}

foreach ($source in $sources) {
    try {
        if ($source.Repo) {
            Clone-Or-Pull-Repo -RepoUrl $source.Repo -TargetPath $source.CloneTo -DisplayName $source.DisplayName
        }
        
        $skills = Get-Skills -BasePath $source.Path
        $sourceStats[$source.Name] = $skills.Count
        
        foreach ($skill in $skills) {
            if (-not $allSkills.ContainsKey($skill.Name)) {
                $allSkills[$skill.Name] = @()
            }
            $allSkills[$skill.Name] += @{
                Source = $source.Name
                DisplayName = $source.DisplayName
                Path = $skill.Path
            }
        }
        
        Write-Success "$($source.DisplayName) ($($skills.Count) skills)"
    } catch {
        Write-Err "$($source.DisplayName): $($_.Exception.Message)"
        $sourceStats[$source.Name] = 0
    }
}

Write-Host ""

# Step 2: Detect conflicts
$conflicts = @{}
$nonConflicts = @{}

foreach ($skillName in $allSkills.Keys) {
    if ($allSkills[$skillName].Count -gt 1) {
        $conflicts[$skillName] = $allSkills[$skillName]
    } else {
        $nonConflicts[$skillName] = $allSkills[$skillName][0]
    }
}

# Step 3: Resolve conflicts interactively
$selectedSkills = @{}  # skill name -> selected source info

# Add all non-conflicting skills
foreach ($skillName in $nonConflicts.Keys) {
    $selectedSkills[$skillName] = $nonConflicts[$skillName]
}

if ($conflicts.Count -gt 0) {
    Write-Color "⚠️  Conflicts detected ($($conflicts.Count)):" "Yellow"
    Write-Host ""
    
    foreach ($skillName in $conflicts.Keys | Sort-Object) {
        Write-Color "   $skillName" "White"
        $options = $conflicts[$skillName]
        for ($i = 0; $i -lt $options.Count; $i++) {
            Write-Color "     [$($i + 1)] $($options[$i].Path)" "Gray"
        }
        Write-Host ""
        
        do {
            $choice = Read-Host "   Select source for '$skillName' [1-$($options.Count)]"
            $choiceNum = 0
            $valid = [int]::TryParse($choice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $options.Count
            if (-not $valid) {
                Write-Warn "Please enter a number between 1 and $($options.Count)"
            }
        } while (-not $valid)
        
        $selectedSkills[$skillName] = $options[$choiceNum - 1]
        Write-Host ""
    }
}

# Step 4: Show summary and confirm
Write-Host ""
Write-Color "📋 Skills to install ($($selectedSkills.Count) total):" "Cyan"
Write-Host ""

$bySource = @{}
foreach ($skillName in $selectedSkills.Keys | Sort-Object) {
    $sourceName = $selectedSkills[$skillName].Source
    if (-not $bySource.ContainsKey($sourceName)) {
        $bySource[$sourceName] = @()
    }
    $bySource[$sourceName] += $skillName
}

foreach ($source in $sources) {
    if ($bySource.ContainsKey($source.Name)) {
        $skills = $bySource[$source.Name]
        Write-Color "  $($source.DisplayName) ($($skills.Count)):" "White"
        foreach ($skill in $skills | Sort-Object) {
            $conflictMarker = if ($conflicts.ContainsKey($skill)) { " ←" } else { "" }
            Write-Color "    [x] $skill$conflictMarker" "Gray"
        }
        Write-Host ""
    }
}

$proceed = Read-Host "Proceed with installation? [Y/n]"
if ($proceed -eq "n" -or $proceed -eq "N") {
    Write-Color "Installation cancelled." "Yellow"
    exit 0
}

# Step 5: Create target directory and junctions
Write-Host ""
Write-Color "Installing skills to $skillsTargetDir ..." "White"
Write-Host ""

Ensure-Directory $skillsTargetDir

$created = 0
$existed = 0
$skipped = 0
$failed = 0

foreach ($skillName in $selectedSkills.Keys | Sort-Object) {
    $skillInfo = $selectedSkills[$skillName]
    $linkPath = Join-Path $skillsTargetDir $skillName
    
    $result = Create-Junction -LinkPath $linkPath -TargetPath $skillInfo.Path
    
    switch ($result) {
        "created" { 
            Write-Success "$skillName"
            $created++
        }
        "exists" { 
            Write-Info "$skillName (already linked)"
            $existed++
        }
        "skipped" {
            Write-Warn "$skillName (skipped - real directory exists)"
            $skipped++
        }
        "failed" {
            Write-Err "$skillName (failed to create junction)"
            $failed++
        }
    }
}

# Step 6: Summary
Write-Host ""
Write-Color "✨ Done!" "Green"
Write-Host ""
Write-Color "Summary:" "White"
Write-Color "  Created: $created" "Green"
if ($existed -gt 0) { Write-Color "  Already linked: $existed" "Cyan" }
if ($skipped -gt 0) { Write-Color "  Skipped: $skipped" "Yellow" }
if ($failed -gt 0) { Write-Color "  Failed: $failed" "Red" }
Write-Host ""
