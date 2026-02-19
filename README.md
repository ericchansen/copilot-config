# Copilot Config

Personal [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) configuration, custom skills, and setup automation — synced across machines via Git.

## What's Included

| File | Purpose |
|------|---------|
| `.copilot/copilot-instructions.md` | Global custom instructions for all sessions |
| `.copilot/lsp-config.json` | Language server configuration (TypeScript, Python, Rust) |
| `.copilot/mcp-config.json` | MCP server configuration |
| `.copilot/config.portable.json` | Portable settings (model, theme, banner — no auth) |
| `.copilot/skills/` | Custom skills (see below) |

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone git@github.com:ericchansen/copilot-config.git ~/repos/copilot-config
   cd ~/repos/copilot-config
   ```

2. **Run the setup script:**

   **Windows (PowerShell):**
   ```powershell
   ./setup.ps1
   ```

   **macOS/Linux:**
   ```bash
   ./setup.sh
   ```

The setup script will:
- Back up your existing `~/.copilot/` config
- Symlink instructions, MCP config, and skills into `~/.copilot/`
- Patch your `config.json` with portable settings (without touching auth)
- Clone external skill repos ([Anthropic](https://github.com/anthropics/skills), [GitHub](https://github.com/github/awesome-copilot)) and link those skills too
- Link all discovered skills into `~/.copilot/skills/`

Run the setup script again at any time to pull updates and re-sync.

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

> **Note:** Never put actual API keys in `mcp-config.json` — always use `${VAR_NAME}` references. The Copilot CLI resolves these from your environment at startup.

## Updating

```bash
cd ~/repos/copilot-config
git pull
./setup.ps1   # or ./setup.sh
```

## Restoring

If something breaks, use the restore script to remove all symlinks and optionally restore from backup:

```powershell
./restore.ps1   # or ./restore.sh
```

## Custom Skills

### git-commit
Conventional commit messages with [Chris Beams' 7 rules](https://cbea.ms/git-commit/). Auto-detects type and scope from your diff, generates properly formatted commit messages, and supports intelligent file staging for logical grouping.

**Trigger:** Ask to commit, create a git commit, or say "/commit"

### summon-the-knights-of-the-round-table
Multi-model brainstorming using GPT-5.2-Codex and Gemini 3 Pro. Gathers context, frames a question, queries both models for divergent perspectives, then synthesizes a consensus with agreed conclusions, resolved disagreements, and recommended actions.

**Trigger:** "summon knights of the round table to review..."

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
