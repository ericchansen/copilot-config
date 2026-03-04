# AGENTS.md

Repo-specific guidance for AI agents working in `copilot-config`.

## Purpose

This repo manages GitHub Copilot CLI configuration, custom skills, and MCP/LSP servers. Config files live in `.copilot/` and are symlinked into `~/.copilot/` via the setup scripts. Editing a tracked config file here immediately affects the live Copilot CLI environment.

## Git Workflow

- **Default branch:** `master`
- Follow the global branching rules — use feature branches and PRs.
- **No tests or CI** — just commit and push.

## File Layout

| Path | Purpose | Symlinked? |
|------|---------|------------|
| `.copilot/copilot-instructions.md` | Global Copilot instructions (all repos) | → `~/.copilot/copilot-instructions.md` |
| `.copilot/mcp-config.json` | MCP server configuration | → `~/.copilot/mcp-config.json` |
| `.copilot/lsp-config.json` | LSP server configuration | → `~/.copilot/lsp-config.json` |
| `.copilot/config.portable.json` | Portable settings (model, theme, etc.) | **No** — patched into `config.json` |
| `.copilot/skills/` | Custom skills (local to this repo) | Directory junctions |
| `external/` | Clone location for work repos (SPT-IQ) | — |
| `setup.ps1` / `setup.sh` | Install: symlink configs, patch settings, link skills, clean legacy junctions | — |
| `restore.ps1` / `restore.sh` | Uninstall: remove symlinks, optionally restore backups | — |
| `sync-skills.ps1` / `sync-skills.sh` | Adopt untracked skills from `~/.copilot/skills/` | — |

## Adding a New Tracked Config File

Update **2 places** in `setup.ps1` (or `setup.sh` for the Bash version):

1. `$configFileLinks` array
2. Backup file list (`$configFiles`)

Then copy the file into `.copilot/`, replace the original in `~/.copilot/` with a symlink, and update `README.md`.

## Checking for Uncommitted Work

Don't just run `git status`. Also compare `~/.copilot/` against the repo for **new untracked files** that should be adopted (e.g., a new `lsp-config.json` that appeared but isn't tracked yet). Key files to check:

```
~/.copilot/config.json          # machine-specific, NOT tracked (only patched)
~/.copilot/copilot-instructions.md  # should be symlink → repo
~/.copilot/mcp-config.json      # should be symlink → repo
~/.copilot/lsp-config.json      # should be symlink → repo
~/.copilot/skills/*             # should be directory junctions → repo; community skills via plugins
```

## Skills Architecture

- **Local skills** (`.copilot/skills/`) — managed by this repo, symlinked by setup scripts
- **Community skills** (awesome-copilot, anthropic) — installed via `copilot plugin install`, NOT managed by setup scripts
- **Work skills** (SPT-IQ) — cloned into `external/` by setup scripts with `-WorkSkills` flag
- **Plugin skills** (msx-mcp) — installed via `copilot plugin install mcaps-microsoft/MSX-MCP`

See `README.md` for plugin install commands.

## Secrets

MCP config uses `${VAR_NAME}` environment variable syntax. **Never hardcode API keys** in any config file. See `README.md` for required environment variables and how to set them.
