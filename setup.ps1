#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup script for Copilot CLI configuration, skills, and MCP servers.

.DESCRIPTION
    Backs up existing ~/.copilot/ config, symlinks config files, patches config.json
    with portable settings, symlinks local custom skills, builds local MCP servers,
    validates env vars, and generates ~/.copilot/mcp-config.json.

    Community skills (awesome-copilot, anthropic, msx-mcp, SPT-IQ) are installed via
    Copilot CLI plugins, not managed by this script. See README.md for plugin install
    commands.

    Idempotent — safe to re-run at any time.

.PARAMETER Work
    Include work tools: installs work plugins (MSX-MCP, SPT-IQ) and enables
    the Power BI Remote MCP server.

.PARAMETER NonInteractive
    Run without prompts (safe for cron jobs). Defaults: skip replacing real dirs
    with junctions.

.EXAMPLE
    ./setup.ps1
    ./setup.ps1 -Work
    ./setup.ps1 -NonInteractive
#>
param(
    [switch]$Work,
    [switch]$CleanOrphans,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================
$repoRoot = $PSScriptRoot
$repoCopilotDir = Join-Path $repoRoot ".copilot"
$repoSkillsDir = Join-Path $repoCopilotDir "skills"
$externalDir = Join-Path $repoRoot "external"
$mcpServersJsonPath = Join-Path $repoRoot "mcp-servers.json"

$copilotHome = Join-Path $env:USERPROFILE ".copilot"
$copilotSkillsHome = Join-Path $copilotHome "skills"
$configJsonPath = Join-Path $copilotHome "config.json"
$portableJsonPath = Join-Path $repoCopilotDir "config.portable.json"

# Git auth state (populated by preflight check)
$script:ghAvailable = $false
$script:sshAvailable = $false
$script:preferSsh = $false

# Config files to symlink (file symlinks)
$configFileLinks = @(
    @{ Name = "copilot-instructions.md" },
    @{ Name = "lsp-config.json" }
)

# Keys allowed to be patched from config.portable.json into config.json
$portableAllowedKeys = @(
    "banner", "model", "render_markdown", "theme", "experimental", "reasoning_effort"
)

# External skill repositories
# All community and work skills (awesome-copilot, anthropic, msx-mcp, SPT-IQ) are now
# installed via Copilot CLI plugins — see README.md. No external repos are cloned.
$externalRepos = @()

# Plugins to install via `copilot plugin install`
# Work = $true means the plugin is only installed when -Work is specified.
$plugins = @(
    @{ Name = "msx-mcp";  Source = "mcaps-microsoft/MSX-MCP"; Work = $true },
    @{ Name = "spt-iq";   Source = "mcaps-microsoft/SPT-IQ";  Work = $true }
)

# Resolve whether to include work tools (plugins + Power BI MCP server)
$includeWork = $false
if ($Work) {
    $includeWork = $true
} elseif (-not $NonInteractive) {
    $answer = Read-Host "  Include work tools? (MSX-MCP, SPT-IQ plugins + Power BI MCP) [y/N]"
    if ($answer -eq "y" -or $answer -eq "Y") {
        $includeWork = $true
    }
}

# Resolve whether to clean orphan skills
$includeCleanOrphans = $false
if ($CleanOrphans) {
    $includeCleanOrphans = $true
} elseif (-not $NonInteractive) {
    $answer = Read-Host "  Remove skills not managed by this repo? [y/N]"
    if ($answer -eq "y" -or $answer -eq "Y") {
        $includeCleanOrphans = $true
    }
}

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
    McpServersBuilt   = @()
    McpServersFailed  = @()
    McpEnvMissing     = @()
    McpConfigGenerated = $false
    PluginJunctionsCleaned = 0
    PluginsInstalled  = @()
    PluginsSkipped    = @()
    PluginsFailed     = @()
    OptionalInstalled = @()
    OptionalSkipped   = @()
    OptionalFailed    = @()
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
            # Real file exists — ask user (skip in non-interactive mode)
            Write-Warn "$DisplayName already exists as a real file at $LinkPath"
            if ($NonInteractive) {
                return "skipped"
            }
            $answer = Read-Host "    Replace with symlink? [y/N]"
            if ($answer -ne "y" -and $answer -ne "Y") {
                return "skipped"
            }
            Remove-Item $LinkPath -Force
        }
    }

    cmd /c mklink "$LinkPath" "$TargetPath" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return "created" }

    # Fallback: try PowerShell New-Item (requires Developer Mode on Windows)
    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force | Out-Null
        return "created"
    } catch {
        # Symlinks require Developer Mode or admin on Windows
        # Fall back to copying the file (re-run setup after git pull to sync)
        try {
            Copy-Item -Path $TargetPath -Destination $LinkPath -Force
            return "copied"
        } catch {
            return "failed"
        }
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
        [string]$DisplayName,
        [string]$Category = "base"
    )

    # Resolve preferred URL (SSH when available, else original HTTPS)
    $cloneUrl = if ($script:preferSsh -and $RepoUrl -match "^https://github\.com/(.+)$") {
        "git@github.com:$($Matches[1])"
    } else { $RepoUrl }
    $authMethod = if ($cloneUrl -match "^git@") { "SSH" } else { "HTTPS" }

    if (Test-Path (Join-Path $TargetPath ".git")) {
        Push-Location $TargetPath
        try {
            # Validate repo identity before touching anything
            # Accept if origin OR upstream matches the expected repo (supports forks)
            $currentRemote = git remote get-url origin 2>$null
            if ($currentRemote) {
                $expectedSlug = if ($RepoUrl -match "github\.com[:/](.+?)(?:\.git)?$") { $Matches[1] } else { $null }
                $actualSlug   = if ($currentRemote -match "github\.com[:/](.+?)(?:\.git)?$") { $Matches[1] } else { $null }
                if ($expectedSlug -and $actualSlug -and $expectedSlug -ne $actualSlug) {
                    # Origin doesn't match — check upstream (fork workflow)
                    $upstreamRemote = git remote get-url upstream 2>$null
                    $upstreamSlug = if ($upstreamRemote -and $upstreamRemote -match "github\.com[:/](.+?)(?:\.git)?$") { $Matches[1] } else { $null }
                    if (-not $upstreamSlug -or $upstreamSlug -ne $expectedSlug) {
                        Write-Err "$DisplayName — path contains a different repo ($actualSlug, expected $expectedSlug)"
                        return "identity-check-failed"
                    }
                    Write-Info "$DisplayName — fork detected (origin=$actualSlug, upstream=$expectedSlug)"
                }
            }

            # Upgrade remote to SSH if preferred and currently HTTPS
            if ($currentRemote -and $currentRemote -ne $cloneUrl -and $script:preferSsh) {
                git remote set-url origin $cloneUrl 2>$null
                Write-Info "$DisplayName — remote updated to $authMethod"
            }

            # Pull the current branch (don't force checkout — respect user's branch choice)
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
            if ($currentBranch) {
                Write-Info "$DisplayName — on branch $currentBranch"
            }

            git pull --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "$DisplayName — failed to pull (may be offline)"

                # Interactive recovery for pull failures
                if (-not $NonInteractive) {
                    Write-Host ""
                    Write-Color "    [C] Continue       — use existing local copy (default)" "White"
                    Write-Color "    [R] Retry          — try pulling again" "White"
                    Write-Color "    [S] Skip           — skip this repo entirely" "White"
                    Write-Color "    [A] Abort          — stop processing remaining repos" "White"
                    Write-Host ""
                    :pullRecovery while ($true) {
                        $choice = Read-Host "    Choice [C/r/s/a]"
                        switch -Regex (($choice ?? "").Trim().ToLowerInvariant()) {
                            "^a$" { return "aborted" }
                            "^s$" { return "skipped" }
                            "^r$" {
                                git pull --quiet 2>&1 | Out-Null
                                if ($LASTEXITCODE -eq 0) {
                                    return "pulled"
                                }
                                Write-Warn "$DisplayName — pull failed again"
                                continue pullRecovery
                            }
                            default {
                                # Enter or 'c' — continue with existing local copy
                                return "pull-failed"
                            }
                        }
                    }
                }

                return "pull-failed"
            }
            return "pulled"
        } finally {
            Pop-Location
        }
    } else {
        $parentDir = Split-Path $TargetPath -Parent
        Ensure-Directory $parentDir

        :cloneLoop while ($true) {
            # Clean up partial clone directory from prior failed attempt
            if (Test-Path $TargetPath) {
                if (-not (Test-Path (Join-Path $TargetPath ".git"))) {
                    Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    # Already a valid repo (user cloned manually between retries?)
                    return "cloned"
                }
            }

            Write-Info "$DisplayName — cloning via $authMethod ($Category)"
            $attemptedMethods = @()

            # Try preferred URL first
            git clone --quiet $cloneUrl $TargetPath 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return "cloned"
            }
            $attemptedMethods += "git clone ($authMethod)"
            # Clean up failed partial clone
            if (Test-Path $TargetPath) { Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue }

            # Try gh CLI with auth token (no browser, no prompts)
            if ($script:ghAvailable -and $RepoUrl -match "github\.com/([^/]+/[^/]+?)(?:\.git)?$") {
                Write-Warn "$DisplayName — $authMethod clone failed, trying gh CLI..."
                $repoSlug = $Matches[1]
                $ghToken = gh auth token 2>$null
                if ($ghToken) {
                    $savedEnv = @{
                        GH_TOKEN           = $env:GH_TOKEN
                        GH_PROMPT_DISABLED = $env:GH_PROMPT_DISABLED
                        GCM_INTERACTIVE    = $env:GCM_INTERACTIVE
                    }
                    try {
                        $env:GH_TOKEN = $ghToken
                        $env:GH_PROMPT_DISABLED = "1"
                        $env:GCM_INTERACTIVE = "never"
                        $null = "" | gh repo clone $repoSlug $TargetPath 2>&1
                    } finally {
                        foreach ($k in $savedEnv.Keys) {
                            if ($null -eq $savedEnv[$k]) {
                                Remove-Item "Env:$k" -ErrorAction SilentlyContinue
                            } else {
                                Set-Item "Env:$k" $savedEnv[$k]
                            }
                        }
                    }
                    if ($LASTEXITCODE -eq 0) {
                        return "cloned"
                    }
                } else {
                    Write-Warn "$DisplayName — gh CLI not authenticated, skipping gh clone"
                }
                $attemptedMethods += "gh repo clone"
                if (Test-Path $TargetPath) { Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue }
            }

            # Final fallback: HTTPS with token auth, no browser/terminal prompts
            if ($cloneUrl -ne $RepoUrl) {
                Write-Warn "$DisplayName — falling back to HTTPS (token-only, no browser)..."
                $savedEnv = @{
                    GIT_TERMINAL_PROMPT = $env:GIT_TERMINAL_PROMPT
                    GCM_INTERACTIVE     = $env:GCM_INTERACTIVE
                    GH_TOKEN            = $env:GH_TOKEN
                }
                try {
                    $env:GIT_TERMINAL_PROMPT = "0"
                    $env:GCM_INTERACTIVE = "never"
                    # If gh is authenticated, inject token into HTTPS URL for git
                    $httpsUrl = $RepoUrl
                    $ghToken = if ($script:ghAvailable) { gh auth token 2>$null } else { $null }
                    if ($ghToken -and $RepoUrl -match "^https://github\.com/") {
                        $httpsUrl = $RepoUrl -replace "^https://", "https://x-access-token:$($ghToken)@"
                    }
                    git clone --quiet $httpsUrl $TargetPath 2>&1 | Out-Null
                } finally {
                    foreach ($k in $savedEnv.Keys) {
                        if ($null -eq $savedEnv[$k]) {
                            Remove-Item "Env:$k" -ErrorAction SilentlyContinue
                        } else {
                            Set-Item "Env:$k" $savedEnv[$k]
                        }
                    }
                }
                if ($LASTEXITCODE -eq 0) {
                    return "cloned"
                }
                $attemptedMethods += "git clone (HTTPS token-only)"
                if (Test-Path $TargetPath) { Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue }
            }

            # Interactive recovery
            if (-not $NonInteractive) {
                Write-Host ""
                Write-Warn "Failed to clone $DisplayName after: $($attemptedMethods -join ', ')"
                Write-Host ""
                Write-Color "    [R] Retry          — try again (fix auth in another terminal first)" "White"
                Write-Color "    [L] Login & retry  — run 'gh auth login' then retry" "White"
                Write-Color "    [M] Manual clone   — you clone it yourself, tell me the path" "White"
                Write-Color "    [S] Skip           — skip this repo, continue with others" "White"
                Write-Color "    [A] Abort          — stop cloning remaining repos" "White"
                Write-Host ""
                $choice = Read-Host "    Choice [R/l/m/s/a]"
                switch -Regex (($choice ?? "").Trim().ToLowerInvariant()) {
                    "^a$" { return "aborted" }
                    "^s$" { return "skipped" }
                    "^l$" {
                        Write-Info "Launching 'gh auth login'..."
                        gh auth login
                        continue cloneLoop
                    }
                    "^m$" {
                        Write-Host ""
                        Write-Color "    Clone it yourself using:" "Yellow"
                        Write-Color "      git clone $cloneUrl <path>" "Cyan"
                        Write-Host ""
                        $manualPath = Read-Host "    Enter the path where you cloned it [$TargetPath]"
                        if (-not $manualPath) { $manualPath = $TargetPath }
                        $manualPath = $manualPath -replace "^~", $env:USERPROFILE
                        $manualPath = [System.IO.Path]::GetFullPath($manualPath)
                        if (Test-Path (Join-Path $manualPath ".git")) {
                            Write-Success "$DisplayName — found at $manualPath"
                            # Update TargetPath for caller if different
                            if ($manualPath -ne $TargetPath) {
                                Set-Variable -Name TargetPath -Value $manualPath -Scope 1 -ErrorAction SilentlyContinue
                            }
                            return "cloned"
                        } else {
                            Write-Err "No git repo found at $manualPath"
                            continue cloneLoop
                        }
                    }
                    default { continue cloneLoop }
                }
            }

            # Non-interactive: just fail
            Write-Host ""
            Write-Err "Failed to clone $DisplayName"
            Write-Color "    You can manually clone:" "Yellow"
            Write-Color "      git clone $cloneUrl $TargetPath" "Cyan"
            Write-Host ""
            return "clone-failed"
        }
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
# Preflight: Git authentication
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Preflight: Git authentication"

# Check for GitHub CLI
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $script:ghAvailable = $true
    $ghStatus = gh auth status 2>&1 | Out-String
    $accounts = [regex]::Matches($ghStatus, "Logged in to github\.com account (\S+)")
    if ($accounts.Count -gt 0) {
        $accountNames = ($accounts | ForEach-Object { $_.Groups[1].Value }) -join ", "
        Write-Success "GitHub CLI — logged in ($accountNames)"
        if ($accounts.Count -gt 1) {
            $activeMatch = [regex]::Match($ghStatus, "account (\S+) \(keyring\)\s*\n\s*- Active account: true")
            if ($activeMatch.Success) {
                Write-Info "Active account: $($activeMatch.Groups[1].Value)"
            }
        }
    } else {
        Write-Warn "GitHub CLI found but not authenticated — run: gh auth login"
    }
} else {
    Write-Warn "GitHub CLI (gh) not installed — credential prompts may appear"
    Write-Info "Install: https://cli.github.com"
}

# Check SSH connectivity to github.com
$sshResult = ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | Out-String
if ($sshResult -match "Hi .+!") {
    $script:sshAvailable = $true
    $script:preferSsh = $true
    $sshUser = [regex]::Match($sshResult, "Hi (\S+)!").Groups[1].Value
    Write-Success "SSH to github.com — OK (as $sshUser, will prefer SSH URLs)"
} else {
    Write-Info "SSH to github.com not available — using HTTPS"
    if (-not $script:ghAvailable) {
        Write-Warn "No SSH and no gh CLI — git may prompt for credentials"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Backup ~/.copilot/
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 1: Backup existing ~/.copilot/"

if (Test-Path $copilotHome) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $env:USERPROFILE ".copilot-backup-$timestamp"
    Ensure-Directory $backupDir

    # Back up config files (not sessions/logs/caches)
    $configFiles = @("config.json", "copilot-instructions.md", "lsp-config.json", "mcp-config.json")
    foreach ($f in $configFiles) {
        $src = Join-Path $copilotHome $f
        if (Test-Path $src -ErrorAction SilentlyContinue) {
            Copy-Item $src (Join-Path $backupDir $f) -Force -ErrorAction SilentlyContinue
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
    $sourceFileName = if ($cfg.Target) { $cfg.Target } else { $cfg.Name }
    $targetPath = Join-Path $repoCopilotDir $sourceFileName
    $linkPath = Join-Path $copilotHome $cfg.Name

    if (-not (Test-Path $targetPath)) {
        Write-Warn "$($cfg.Name) — source not found in repo, skipping"
        continue
    }

    $displayName = if ($cfg.Target) { "$($cfg.Name) → $($cfg.Target)" } else { $cfg.Name }
    $result = Create-FileSymlink -LinkPath $linkPath -TargetPath $targetPath -DisplayName $displayName

    switch ($result) {
        "created" {
            Write-Success "$($cfg.Name) → linked"
            $script:summary.ConfigFilesLinked += $cfg.Name
        }
        "copied" {
            Write-Warn "$($cfg.Name) → copied (symlinks need Developer Mode; re-run setup after git pull)"
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
    Write-Info "Local: $($localSkills.Count) skills found in $repoSkillsDir"
    foreach ($skill in $localSkills) {
        $linkPath = Join-Path $copilotSkillsHome $skill.Name
        $result = Create-DirJunction -LinkPath $linkPath -TargetPath $skill.Path -DisplayName $skill.Name -AskBeforeReplace:(-not $NonInteractive)

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
# Step 7b: Clean up old anthropic/awesome-copilot skill junctions
# ─────────────────────────────────────────────────────────────────────────────
# These repos are now installed via Copilot CLI plugins, not manual cloning.
# Remove any leftover junctions pointing into their old clone directories.
Write-Step "Step 7b: Clean up legacy skill junctions (anthropic, awesome-copilot, msx-mcp, SPT-IQ)"

$legacyPatterns = @("anthropic-skills", "awesome-copilot", "msx-mcp", "MSX-MCP", "SPT-IQ")
$legacyCleaned = 0

Get-ChildItem -Path $copilotSkillsHome -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $target = (Get-Item $_.FullName -Force).Target
        if ($target -is [System.Collections.IEnumerable] -and $target -isnot [string]) { $target = $target[0] }
        if ($target) {
            foreach ($pattern in $legacyPatterns) {
                if ($target -match [regex]::Escape($pattern)) {
                    Write-Warn "Removing legacy junction: $($_.Name) → $target"
                    cmd /c rmdir "$($_.FullName)" 2>&1 | Out-Null
                    $legacyCleaned++
                    break
                }
            }
        }
    }
}

# Clean legacy entries from .external-paths.json
$externalPathsFile = Join-Path $repoRoot ".external-paths.json"
if (Test-Path $externalPathsFile) {
    $externalPaths = Get-Content $externalPathsFile -Raw | ConvertFrom-Json
    $legacyKeys = @("anthropic", "github", "msx-mcp", "spt-iq")
    $cleaned = $false
    foreach ($key in $legacyKeys) {
        if ($externalPaths.PSObject.Properties[$key]) {
            $externalPaths.PSObject.Properties.Remove($key)
            $cleaned = $true
        }
    }
    if ($cleaned) {
        $externalPaths | ConvertTo-Json -Depth 5 | Set-Content $externalPathsFile -Encoding UTF8
        Write-Info "Cleaned legacy entries from .external-paths.json"
    }
}

if ($legacyCleaned -gt 0) {
    Write-Success "Removed $legacyCleaned legacy skill junction(s)"
    Write-Info "Install community skills via plugins instead:"
    Write-Color "    copilot plugin install <name>@awesome-copilot" "Cyan"
    Write-Color "    copilot plugin marketplace add anthropics/skills" "Cyan"
    Write-Color "    copilot plugin install document-skills@anthropic-agent-skills" "Cyan"
    $script:summary.PluginJunctionsCleaned = $legacyCleaned
} else {
    Write-Info "No legacy junctions to clean up"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7c: Install Copilot CLI plugins
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 7c: Install plugins"

# Determine which plugins to install based on flags
$pluginsToInstall = $plugins | Where-Object { -not $_.Work -or $includeWork }

if ($pluginsToInstall.Count -eq 0) {
    Write-Info "No plugins to install (use -Work to include work plugins)"
} else {
    # Get currently installed plugins
    $installedRaw = ""
    try {
        $installedRaw = (& copilot plugin list 2>&1) | Out-String
    } catch {
        Write-Warn "Could not list installed plugins: $_"
    }

    foreach ($plugin in $pluginsToInstall) {
        if ($installedRaw -match [regex]::Escape($plugin.Name)) {
            Write-Info "$($plugin.Name) already installed"
            $script:summary.PluginsSkipped += $plugin.Name
        } else {
            Write-Info "Installing $($plugin.Name) from $($plugin.Source)..."
            try {
                $output = & copilot plugin install $plugin.Source 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "$($plugin.Name) installed"
                    $script:summary.PluginsInstalled += $plugin.Name
                } else {
                    Write-Warn "$($plugin.Name) install returned exit code $LASTEXITCODE"
                    Write-Warn "  $($output | Out-String)"
                    $script:summary.PluginsFailed += $plugin.Name
                }
            } catch {
                Write-Err "Failed to install $($plugin.Name): $_"
                $script:summary.PluginsFailed += $plugin.Name
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

# Load or create .external-paths.json (machine-local, gitignored)
$externalPathsFile = Join-Path $repoRoot ".external-paths.json"
if (Test-Path $externalPathsFile) {
    $externalPaths = Get-Content $externalPathsFile -Raw | ConvertFrom-Json
} else {
    $externalPaths = [PSCustomObject]@{}
}

$abortRemainingExternal = $false
foreach ($repo in $externalRepos) {
    $resolvedPath = $null

    # 1. Check stored path from .external-paths.json (subsequent runs)
    $storedPath = $externalPaths.PSObject.Properties[$repo.Name]
    if ($storedPath -and (Test-Path $storedPath.Value)) {
        $resolvedPath = $storedPath.Value
        Write-Info "$($repo.DisplayName) — using stored path: $resolvedPath"
    }

    if (-not $resolvedPath) {
        # Auto-detect: check external/<CloneDir>
        $detectedPath = $null
        $extPath = Join-Path $externalDir $repo.CloneDir
        if (Test-Path $extPath) {
            $detectedPath = [System.IO.Path]::GetFullPath($extPath)
        }

        # 2. Interactive: prompt user for parent directory (append CloneDir)
        if (-not $NonInteractive) {
            $parentSuggestion = if ($detectedPath) { Split-Path $detectedPath -Parent } else { $externalDir }
            $userDir = Read-Host "    Clone directory for $($repo.DisplayName) [$parentSuggestion]"
            if ($userDir) {
                $userDir = $userDir -replace "^~", $env:USERPROFILE
                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $userDir $repo.CloneDir))
            } else {
                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $parentSuggestion $repo.CloneDir))
            }
        }
        # 3. Non-interactive: use detected path or fall back to external/<CloneDir>
        else {
            if ($detectedPath) {
                $resolvedPath = $detectedPath
                Write-Info "$($repo.DisplayName) — auto-detected at $resolvedPath"
            } else {
                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $externalDir $repo.CloneDir))
            }
        }
    }

    $skillsPath = Join-Path $resolvedPath $repo.SkillsSubdir

    $cloneResult = Clone-Or-Pull-Repo -RepoUrl $repo.Repo -TargetPath $resolvedPath -DisplayName $repo.DisplayName -Category ($repo.Category ?? "base")

    $skipRepo = $false
    switch ($cloneResult) {
        "cloned" {
            Write-Success "$($repo.DisplayName) — cloned"
            $script:summary.ExternalCloned += $repo.DisplayName
            break
        }
        "pulled" {
            Write-Success "$($repo.DisplayName) — updated"
            $script:summary.ExternalPulled += $repo.DisplayName
            break
        }
        "skipped" {
            Write-Warn "$($repo.DisplayName) — skipped by user"
            $skipRepo = $true
            break
        }
        "aborted" {
            Write-Warn "$($repo.DisplayName) — aborting remaining external repo clones by user choice"
            $abortRemainingExternal = $true
            break
        }
        "pull-failed" {
            Write-Warn "$($repo.DisplayName) — using existing local copy (pull failed)"
            $script:summary.ExternalFailed += $repo.DisplayName
            break
        }
        { $_ -match "failed" } {
            Write-Err "$($repo.DisplayName) — $cloneResult"
            $script:summary.ExternalFailed += $repo.DisplayName
            $skipRepo = $true
        }
    }
    if ($abortRemainingExternal) { break }
    if ($skipRepo) { continue }

    # Store resolved path for subsequent runs
    if ($externalPaths.PSObject.Properties[$repo.Name]) {
        $externalPaths.PSObject.Properties[$repo.Name].Value = $resolvedPath
    } else {
        $externalPaths | Add-Member -NotePropertyName $repo.Name -NotePropertyValue $resolvedPath
    }

    $extSkills = Get-SkillFolders -BasePath $skillsPath
    $excludeList = @($repo.Exclude)
    $excludedCount = 0
    Write-Info "$($repo.DisplayName): $($extSkills.Count) skills found in $skillsPath"

    foreach ($skill in $extSkills) {
        # Skip excluded skills
        if ($excludeList -contains $skill.Name) {
            $excludedCount++
            continue
        }

        if (-not $allSkills.ContainsKey($skill.Name)) {
            $allSkills[$skill.Name] = @()
        }
        $allSkills[$skill.Name] += @{
            Source      = $repo.Name
            DisplayName = $repo.DisplayName
            Path        = $skill.Path
        }
    }
    if ($excludedCount -gt 0) {
        Write-Info "$($repo.DisplayName): $excludedCount skill(s) excluded"
    }
}

# Save .external-paths.json
$externalPaths | ConvertTo-Json -Depth 5 | Set-Content $externalPathsFile -Encoding UTF8

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

    $result = Create-DirJunction -LinkPath $linkPath -TargetPath $skillInfo.Path -DisplayName "$skillName ($($skillInfo.DisplayName))" -AskBeforeReplace:(-not $NonInteractive)

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
# Step 9: Resolve & build local MCP servers
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 9: Resolve & build local MCP servers"

$mcpServers = (Get-Content $mcpServersJsonPath -Raw | ConvertFrom-Json).servers

# Determine enabled categories
$enabledCategories = @("base")
if ($includeWork)    { $enabledCategories += "powerbi" }

$enabledServers = $mcpServers | Where-Object { $enabledCategories -contains $_.category }

# Load or create .mcp-paths.json (machine-local, gitignored)
$mcpPathsFile = Join-Path $repoRoot ".mcp-paths.json"
if (Test-Path $mcpPathsFile) {
    $mcpPaths = Get-Content $mcpPathsFile -Raw | ConvertFrom-Json
} else {
    $mcpPaths = [PSCustomObject]@{}
}

$abortRemainingMcpClones = $false
foreach ($server in $enabledServers) {
    if ($server.type -ne "local") { continue }

    $resolvedPath = $null

    # 1. Check stored path from .mcp-paths.json (subsequent runs)
    $storedPath = $mcpPaths.PSObject.Properties[$server.name]
    if ($storedPath -and (Test-Path $storedPath.Value)) {
        $resolvedPath = $storedPath.Value
        Write-Info "$($server.name) — using stored path: $resolvedPath"
    }

    if (-not $resolvedPath) {
        # Auto-detect from defaultPaths and external/ for use as suggestion
        $detectedPath = $null
        if ($server.defaultPaths) {
            foreach ($dp in $server.defaultPaths) {
                $expanded = $dp -replace "^~", $env:USERPROFILE
                if (Test-Path $expanded) {
                    $detectedPath = [System.IO.Path]::GetFullPath($expanded)
                    break
                }
            }
        }
        if (-not $detectedPath) {
            $extPath = Join-Path $externalDir $server.cloneDir
            if (Test-Path $extPath) {
                $detectedPath = [System.IO.Path]::GetFullPath($extPath)
            }
        }

        # 2. First run, interactive: always prompt (use detected path as default)
        if (-not $NonInteractive) {
            $suggestion = if ($detectedPath) { $detectedPath } else { Join-Path $externalDir $server.cloneDir }
            $userPath = Read-Host "    Path to $($server.name) repo [$suggestion]"
            if ($userPath) {
                $userPath = $userPath -replace "^~", $env:USERPROFILE
                $resolvedPath = [System.IO.Path]::GetFullPath($userPath)
            } else {
                $resolvedPath = [System.IO.Path]::GetFullPath($suggestion)
            }
        }
        # 3. Non-interactive: use detected path or fall back to external/
        else {
            if ($detectedPath) {
                $resolvedPath = $detectedPath
                Write-Info "$($server.name) — auto-detected at $resolvedPath"
            } else {
                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $externalDir $server.cloneDir))
            }
        }
    }

    # Clone if needed
    if (-not (Test-Path $resolvedPath)) {
        Write-Info "$($server.name) — cloning to $resolvedPath..."
        $cloneResult = Clone-Or-Pull-Repo -RepoUrl $server.repo -TargetPath $resolvedPath -DisplayName $server.name -Category $server.category
        if ($cloneResult -eq "aborted") {
            Write-Warn "$($server.name) — aborting remaining MCP clones by user choice"
            $abortRemainingMcpClones = $true
            break
        }
        if ($cloneResult -eq "skipped") {
            Write-Warn "$($server.name) — skipped by user"
            $script:summary.McpServersFailed += $server.name
            continue
        }
        if ($cloneResult -match "failed") {
            Write-Err "$($server.name) — clone failed: $cloneResult"
            $script:summary.McpServersFailed += $server.name
            continue
        }
    }

    # Store resolved path
    if ($mcpPaths.PSObject.Properties[$server.name]) {
        $mcpPaths.PSObject.Properties[$server.name].Value = $resolvedPath
    } else {
        $mcpPaths | Add-Member -NotePropertyName $server.name -NotePropertyValue $resolvedPath
    }

    # Build
    if ($server.build) {
        Write-Info "$($server.name) — building..."
        $buildFailed = $false
        foreach ($cmd in $server.build) {
            try {
                Push-Location $resolvedPath
                $output = Invoke-Expression $cmd 2>&1
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                    Write-Err "$($server.name) — '$cmd' failed (exit code $LASTEXITCODE)"
                    $buildFailed = $true
                    break
                }
            } catch {
                Write-Err "$($server.name) — '$cmd' threw: $_"
                $buildFailed = $true
                break
            } finally {
                Pop-Location
            }
        }

        if ($buildFailed) {
            $script:summary.McpServersFailed += $server.name
        } else {
            Write-Success "$($server.name) — built successfully"
            $script:summary.McpServersBuilt += $server.name
        }
    }
}

# Save .mcp-paths.json
$mcpPaths | ConvertTo-Json -Depth 5 | Set-Content $mcpPathsFile -Encoding UTF8

if ($script:summary.McpServersBuilt.Count -eq 0 -and $script:summary.McpServersFailed.Count -eq 0) {
    $localCount = @($enabledServers | Where-Object { $_.type -eq "local" }).Count
    if ($localCount -eq 0) {
        Write-Info "No local MCP servers to build"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 10: Validate MCP server environment variables
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 10: Validate MCP environment variables"

foreach ($server in $enabledServers) {
    if (-not $server.envVars) { continue }

    foreach ($varName in $server.envVars) {
        $val = [System.Environment]::GetEnvironmentVariable($varName)
        if ($val) {
            Write-Info "$varName — set ✓"
        } elseif (-not $NonInteractive) {
            Write-Warn "$varName (required by $($server.name)) is not set"
            $input = Read-Host "    Enter value for $varName (or press Enter to skip)"
            if ($input) {
                [System.Environment]::SetEnvironmentVariable($varName, $input, "Process")
                Write-Success "$varName — set for this session"
                Write-Warn "  To persist, add to your shell profile: `$env:$varName = `"$input`""
            } else {
                Write-Warn "$varName — skipped (MCP server $($server.name) may not work)"
                $script:summary.McpEnvMissing += "$varName ($($server.name))"
            }
        } else {
            Write-Warn "$varName (required by $($server.name)) is not set — server may not work at runtime"
            $script:summary.McpEnvMissing += "$varName ($($server.name))"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 11: Generate ~/.copilot/mcp-config.json
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 11: Generate mcp-config.json"

$mcpConfig = [ordered]@{ mcpServers = [ordered]@{} }

foreach ($server in $enabledServers) {
    $entry = [ordered]@{}

    switch ($server.type) {
        "npx" {
            $entry["type"] = "local"
            $entry["command"] = "npx"
            $entry["tools"] = @($server.tools)
            $npxArgs = @("-y", $server.package)
            if ($server.args) { $npxArgs += @($server.args) }
            $entry["args"] = $npxArgs
        }
        "http" {
            $entry["type"] = "http"
            $entry["url"] = $server.url
            $entry["tools"] = @($server.tools)
            if ($server.headers) {
                $headers = [ordered]@{}
                $server.headers.PSObject.Properties | ForEach-Object { $headers[$_.Name] = $_.Value }
                $entry["headers"] = $headers
            }
        }
        "local" {
            $serverPath = $mcpPaths.PSObject.Properties[$server.name]
            if ($serverPath) {
                $entryPointPath = Join-Path $serverPath.Value $server.entryPoint
            } else {
                $entryPointPath = Join-Path (Join-Path $externalDir $server.cloneDir) $server.entryPoint
            }
            $entry["type"] = "local"
            $entry["command"] = $server.command
            $entry["tools"] = @($server.tools)
            $entry["args"] = @([System.IO.Path]::GetFullPath($entryPointPath))
        }
    }

    $mcpConfig.mcpServers[$server.name] = $entry
}

$mcpConfigPath = Join-Path $copilotHome "mcp-config.json"
# Remove stale symlink so Set-Content can create a regular file
if (Test-Path $mcpConfigPath) {
    $item = Get-Item $mcpConfigPath -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Remove-Item $mcpConfigPath -Force
    }
}
$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content $mcpConfigPath -Encoding UTF8
Write-Success "Generated $mcpConfigPath ($($enabledServers.Count) servers)"
$script:summary.McpConfigGenerated = $true

# ─────────────────────────────────────────────────────────────────────────────
# Step 12: Clean up stale skill junctions
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Step 12: Clean up stale skill junctions"

# Build set of all skill names we intentionally linked (local + external)
$linkedSkillNames = @{}
foreach ($skill in $localSkills) { $linkedSkillNames[$skill.Name] = $true }
foreach ($skillName in $externalToLink.Keys) { $linkedSkillNames[$skillName] = $true }

$staleCount = 0
$orphanCount = 0

if ($includeCleanOrphans) {
    # Remove ALL items in skills dir that aren't in the linked set
    Get-ChildItem -Path $copilotSkillsHome -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $linkedSkillNames.ContainsKey($_.Name)) {
            if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Write-Warn "Removing orphan junction: $($_.Name)"
                cmd /c rmdir "$($_.FullName)" 2>&1 | Out-Null
            } else {
                Write-Warn "Removing orphan skill: $($_.Name)"
                Remove-Item -Path $_.FullName -Recurse -Force
            }
            $orphanCount++
        }
    }
} else {
    # Default: only remove stale junctions pointing into managed directories
    $managedRoots = @(
        [System.IO.Path]::GetFullPath($repoRoot),
        [System.IO.Path]::GetFullPath($externalDir)
    )

    Get-ChildItem -Path $copilotSkillsHome -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $target = (Get-Item $_.FullName -Force).Target
            if ($target -is [System.Collections.IEnumerable] -and $target -isnot [string]) { $target = $target[0] }
            if ($target) {
                $resolved = [System.IO.Path]::GetFullPath($target)
                $isManagedTarget = $false
                foreach ($root in $managedRoots) {
                    if ($resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $isManagedTarget = $true
                        break
                    }
                }
                if ($isManagedTarget -and -not $linkedSkillNames.ContainsKey($_.Name)) {
                    Write-Warn "Removing stale junction: $($_.Name) → $target"
                    cmd /c rmdir "$($_.FullName)" 2>&1 | Out-Null
                    $staleCount++
                }
            }
        }
    }
}

$totalCleaned = $staleCount + $orphanCount
if ($totalCleaned -eq 0) {
    Write-Info "No stale junctions to clean up"
} else {
    $parts = @()
    if ($staleCount -gt 0) { $parts += "$staleCount stale" }
    if ($orphanCount -gt 0) { $parts += "$orphanCount orphan" }
    Write-Success "Cleaned up $($parts -join ', ') skill(s)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 12b: Optional Dependencies
# ─────────────────────────────────────────────────────────────────────────────
if (-not $NonInteractive) {
    Write-Host ""
    Write-Color "═══════════════════════════════════" "Cyan"
    Write-Color "  Optional Dependencies" "Cyan"
    Write-Color "═══════════════════════════════════" "Cyan"
    Write-Host ""
    Write-Host "These tools enhance specific skills. You can install them now"
    Write-Host "or later. The agent works without them but some skills will"
    Write-Host "be limited."
    Write-Host ""

    # --- MarkItDown (pip) ---
    if (Get-Command markitdown -ErrorAction SilentlyContinue) {
        Write-Success "MarkItDown already installed"
        $script:summary.OptionalSkipped += "markitdown"
    } else {
        $answer = Read-Host "Install MarkItDown? (converts PDF/Word/Excel to markdown) [Y/n]"
        if ($answer -eq "" -or $answer -eq "y" -or $answer -eq "Y") {
            try {
                Write-Info "Installing markitdown[all] via pip..."
                pip install 'markitdown[all]'
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "MarkItDown installed"
                    $script:summary.OptionalInstalled += "markitdown"
                } else {
                    Write-Err "MarkItDown install failed"
                    $script:summary.OptionalFailed += "markitdown"
                }
            } catch {
                Write-Err "MarkItDown install failed: $_"
                $script:summary.OptionalFailed += "markitdown"
            }
        } else {
            Write-Info "Skipped MarkItDown"
            $script:summary.OptionalSkipped += "markitdown"
        }
    }

    # --- QMD (npm, requires Node.js 22+) ---
    if (Get-Command qmd -ErrorAction SilentlyContinue) {
        Write-Success "QMD already installed"
        $script:summary.OptionalSkipped += "qmd"
    } else {
        $nodeOk = $false
        if (Get-Command node -ErrorAction SilentlyContinue) {
            $nodeVer = (node --version 2>&1) -replace '^v', ''
            $nodeMajor = [int]($nodeVer -split '\.')[0]
            if ($nodeMajor -ge 22) {
                $nodeOk = $true
            }
        }
        if (-not $nodeOk) {
            Write-Warn "QMD requires Node.js 22+ (current: $(if (Get-Command node -ErrorAction SilentlyContinue) { node --version } else { 'not found' }))"
            Write-Info "Skipped QMD"
            $script:summary.OptionalSkipped += "qmd"
        } else {
            $answer = Read-Host "Install QMD? (local hybrid search for memory, requires Node.js 22+) [Y/n]"
            if ($answer -eq "" -or $answer -eq "y" -or $answer -eq "Y") {
                try {
                    Write-Info "Installing @tobilu/qmd via npm..."
                    npm install -g "@tobilu/qmd"
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "QMD installed"
                        $script:summary.OptionalInstalled += "qmd"
                    } else {
                        Write-Err "QMD install failed"
                        $script:summary.OptionalFailed += "qmd"
                    }
                } catch {
                    Write-Err "QMD install failed: $_"
                    $script:summary.OptionalFailed += "qmd"
                }
            } else {
                Write-Info "Skipped QMD"
                $script:summary.OptionalSkipped += "qmd"
            }
        }
    }

    # --- Playwright Edge driver ---
    $edgeInstalled = $false
    $msPlaywrightDir = Join-Path $env:LOCALAPPDATA "ms-playwright"
    if (Test-Path $msPlaywrightDir) {
        $edgeDirs = Get-ChildItem -Path $msPlaywrightDir -Directory -Filter "msedge-*" -ErrorAction SilentlyContinue
        if ($edgeDirs.Count -gt 0) { $edgeInstalled = $true }
    }
    if ($edgeInstalled) {
        Write-Success "Playwright Edge driver already installed"
        $script:summary.OptionalSkipped += "playwright-edge"
    } else {
        $answer = Read-Host "Install Playwright Edge driver? (needed for browser automation) [Y/n]"
        if ($answer -eq "" -or $answer -eq "y" -or $answer -eq "Y") {
            try {
                Write-Info "Installing Playwright Edge driver..."
                npx playwright install msedge
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Playwright Edge driver installed"
                    $script:summary.OptionalInstalled += "playwright-edge"
                } else {
                    Write-Err "Playwright Edge install failed"
                    $script:summary.OptionalFailed += "playwright-edge"
                }
            } catch {
                Write-Err "Playwright Edge install failed: $_"
                $script:summary.OptionalFailed += "playwright-edge"
            }
        } else {
            Write-Info "Skipped Playwright Edge driver"
            $script:summary.OptionalSkipped += "playwright-edge"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 13: Summary
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
Write-Color "  Skills (no allowlist — all linked):" "Cyan"
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

if ($script:summary.McpConfigGenerated) {
    Write-Host ""
    Write-Color "  MCP servers:" "Cyan"
    Write-Color "    Configured:     $($enabledServers.Count)" "Green"
    if ($script:summary.McpServersBuilt.Count -gt 0) {
        Write-Color "    Built:          $($script:summary.McpServersBuilt -join ', ')" "Green"
    }
    if ($script:summary.McpServersFailed.Count -gt 0) {
        Write-Color "    Build failed:   $($script:summary.McpServersFailed -join ', ')" "Red"
    }
    if ($script:summary.McpEnvMissing.Count -gt 0) {
        Write-Color "    Env missing:    $($script:summary.McpEnvMissing -join ', ')" "Yellow"
    }
}

if ($script:summary.PluginJunctionsCleaned -gt 0) {
    Write-Host ""
    Write-Color "  Legacy cleanup:" "Cyan"
    Write-Color "    Junctions removed: $($script:summary.PluginJunctionsCleaned) (now use plugins)" "Yellow"
}

$pInstalled = $script:summary.PluginsInstalled.Count
$pSkipped   = $script:summary.PluginsSkipped.Count
$pFailed    = $script:summary.PluginsFailed.Count
if ($pInstalled -gt 0 -or $pSkipped -gt 0 -or $pFailed -gt 0) {
    Write-Host ""
    Write-Color "  Plugins:" "Cyan"
    if ($pInstalled -gt 0) { Write-Color "    Installed:      $($script:summary.PluginsInstalled -join ', ')" "Green" }
    if ($pSkipped   -gt 0) { Write-Color "    Already there:  $($script:summary.PluginsSkipped -join ', ')" "Cyan" }
    if ($pFailed    -gt 0) { Write-Color "    Failed:         $($script:summary.PluginsFailed -join ', ')" "Red" }
}

$oInstalled = $script:summary.OptionalInstalled.Count
$oSkipped   = $script:summary.OptionalSkipped.Count
$oFailed    = $script:summary.OptionalFailed.Count
if ($oInstalled -gt 0 -or $oSkipped -gt 0 -or $oFailed -gt 0) {
    Write-Host ""
    Write-Color "  Optional tools:" "Cyan"
    if ($oInstalled -gt 0) { Write-Color "    Installed:      $($script:summary.OptionalInstalled -join ', ')" "Green" }
    if ($oSkipped   -gt 0) { Write-Color "    Skipped:        $($script:summary.OptionalSkipped -join ', ')" "Cyan" }
    if ($oFailed    -gt 0) { Write-Color "    Failed:         $($script:summary.OptionalFailed -join ', ')" "Red" }
}

Write-Host ""
