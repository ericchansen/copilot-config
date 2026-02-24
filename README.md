# Copilot Config

Personal [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) configuration, custom skills, and setup automation — synced across machines via Git.

## What's Included

| File | Purpose |
|------|---------|
| `.copilot/copilot-instructions.md` | Global custom instructions for all sessions |
| `.copilot/lsp-config.json` | Language server configuration (TypeScript, Python, Rust) |
| `.copilot/config.portable.json` | Portable settings (model, theme, banner — no auth) |
| `.copilot/skills/` | Custom skills (see below) |
| `mcp-servers.json` | MCP server definitions (generates `~/.copilot/mcp-config.json`) |

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone git@github.com:ericchansen/copilot-config.git ~/repos/copilot-config
   cd ~/repos/copilot-config
   ```

2. **Run the setup script:**

   ```powershell
   ./setup.ps1                                           # Interactive — prompts for options
   ./setup.ps1 -WorkSkills -PowerBI                      # Include work skills + Power BI
   ./setup.ps1 -NonInteractive                           # No prompts, base only (safe for cron)
   ./setup.ps1 -NonInteractive -WorkSkills -PowerBI      # No prompts, everything enabled
   ```

The setup script will:
- **Check git authentication** — detects SSH keys and GitHub CLI accounts, uses `gh auth token` for clone fallbacks (no browser popups)
- Back up your existing `~/.copilot/` config
- Symlink instructions and skills into `~/.copilot/`
- Patch your `config.json` with portable settings (without touching auth)
- Clone external skill repos ([Anthropic](https://github.com/anthropics/skills), [GitHub](https://github.com/github/awesome-copilot)) and link curated skills
- Optionally clone work-specific repos (msx-mcp, SPT-IQ) when requested
- Build local MCP servers (clone, install deps, compile)
- Validate required environment variables (prompt if missing)
- Generate `~/.copilot/mcp-config.json` with correct OS paths
- Clean up stale junctions for excluded or removed skills

Run the setup script again at any time to pull updates and re-sync.

## Git Authentication

The setup script clones and pulls multiple GitHub repos. To avoid credential popups, the script runs a **preflight auth check** before any git operations:

1. **SSH (preferred)** — checks `ssh -T git@github.com`. If SSH keys are configured, all clone/pull operations use `git@github.com:owner/repo.git` URLs. Existing HTTPS remotes are automatically upgraded to SSH.
2. **GitHub CLI** — detects `gh auth status` and reports which accounts are available. If SSH isn't available, `gh repo clone` is used as a fallback (uses cached auth tokens).
3. **Git Credential Manager** — if neither SSH nor `gh` is available, standard `git clone` runs and may trigger interactive credential prompts.

### Recommended Setup

```bash
# 1. Install GitHub CLI (if not already)
# https://cli.github.com

# 2. Authenticate
gh auth login

# 3. Configure SSH as the git protocol (eliminates credential popups)
gh auth setup-git
```

For multi-account setups (personal + work), configure SSH keys per account in `~/.ssh/config`:

```
# Personal
Host github.com
  HostName github.com
  IdentityFile ~/.ssh/id_ed25519_personal

# Work (if needed via separate host alias)
Host github-work
  HostName github.com
  IdentityFile ~/.ssh/id_ed25519_work
```

## Environment Variables

Some MCP servers require API keys or secrets. These are referenced in `mcp-config.json` using `${VAR_NAME}` syntax so that secrets are never committed to git.

### Required Variables

| Variable | Purpose | How to Get |
|----------|---------|-----------|
| `CONTEXT7_API_KEY` | Context7 documentation lookup | [context7.com](https://context7.com) — free tier available |

### Setting Variables (Windows)

```powershell
# Set permanently for your user account (persists across reboots)
[System.Environment]::SetEnvironmentVariable("CONTEXT7_API_KEY", "your-key-here", "User")

# Restart your terminal for the change to take effect
```

### Setting Variables (macOS/Linux)

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export CONTEXT7_API_KEY="your-key-here"

# Reload your shell
source ~/.bashrc  # or ~/.zshrc
```

> **Note:** Never put actual API keys in `mcp-servers.json` — always use `${VAR_NAME}` references. The Copilot CLI resolves these from your environment at startup.

## MCP Servers

MCP server configuration is defined in `mcp-servers.json` and generated into `~/.copilot/mcp-config.json` at setup time. This ensures correct OS paths and only enabled servers are included.

### Base Servers (always enabled)

| Server | Type | Purpose |
|--------|------|---------|
| azure-mcp | npx | Azure resource management |
| context7 | http | Documentation search (needs `CONTEXT7_API_KEY`) |
| microsoft-learn | http | Microsoft Learn docs |
| playwright | npx | Browser automation (Edge) |
| chrome-devtools | npx | Chrome DevTools debugging |

### Optional Servers

| Server | Flag | Type | Purpose |
|--------|------|------|---------|
| msx-mcp | `-WorkSkills` | local (node) | MSX deal/account tools |
| powerbi-remote | `-PowerBI` | http | Power BI Fabric API |

## Updating

```bash
cd ~/repos/copilot-config
git pull
./setup.ps1   # or ./setup.sh
```

## Restoring

If something breaks, use the restore script to remove all symlinks and optionally restore from backup:

```powershell
./restore.ps1
```

## Custom Skills

### git-commit
Conventional commit messages with [Chris Beams' 7 rules](https://cbea.ms/git-commit/). Auto-detects type and scope from your diff, scans for secrets, checks repo contribution guidelines, and generates properly formatted commit messages.

**Trigger:** Ask to commit, create a git commit, push code, create a PR, or say "/commit"

### git-safety-scan
Mandatory pre-push scan for secrets, PII, customer names, and sensitive data. Supports a user blocklist at `~/.copilot/sensitive-terms.txt`.

**Trigger:** Automatically invoked before any `git push` or PR creation

### summon-the-knights-of-the-round-table
Multi-model brainstorming using Claude Opus 4.6, GPT-5.3-Codex, and Gemini 3 Pro with randomized Devil's Advocate / Explorer / Steelman roles for structured debate.

**Trigger:** "summon knights of the round table to review..."

## External Skills

Setup links curated skills from:
- **[anthropics/skills](https://github.com/anthropics/skills)** — docx, pdf, pptx, xlsx, frontend-design, web-artifacts-builder, webapp-testing, theme-factory
- **[github/awesome-copilot](https://github.com/github/awesome-copilot)** — 27 skills covering Azure, GitHub CLI, Chrome DevTools, web forms, diagrams, and more

### Optional Work Skills (`-WorkSkills`)
- **[ericchansen/msx-mcp](https://github.com/ericchansen/msx-mcp)** — account-explorer, monthly-opportunity-report, msx-acr-reconciler, territory-scanner, weekly-impact-report
- **[ericchansen/SPT-IQ](https://github.com/ericchansen/SPT-IQ)** — spt-iq-consumption, spt-iq-preflight

## Migrating from `ericchansen/skills`

If you previously cloned this repo as `skills`, update your remote:

```bash
cd ~/repos/skills
git remote set-url origin git@github.com:ericchansen/copilot-config.git
# Optionally rename the local directory
cd .. && mv skills copilot-config
```

## About Agent Skills

Agent Skills are an [open standard](https://github.com/agentskills/agentskills) maintained by Anthropic for giving agents new capabilities. Skills are folders containing a `SKILL.md` with YAML frontmatter and optional bundled resources (scripts, references, assets).

## License

MIT
