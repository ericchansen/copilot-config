# AGENTS.md

Repo-specific guidance for AI agents working in `copilot-config`.

## Purpose

This repo manages GitHub Copilot CLI configuration, custom skills, and MCP/LSP servers. Config files live in `.copilot/` and are symlinked into `~/.copilot/` via the setup scripts. Editing a tracked config file here immediately affects the live Copilot CLI environment.

## Git Workflow

- **Default branch:** `master`
- **Push directly to `master`** — no feature branches, no PRs. This is a personal config repo.
- **No tests or CI** — just commit and push.
- The global `copilot-instructions.md` defaults to feature branches (`git checkout -b <type>/<short-description>`) when no repo guidance exists — this repo **overrides** that. AGENTS.md takes precedence over user-level instructions.

## File Layout

| Path | Purpose | Symlinked? |
|------|---------|------------|
| `.copilot/copilot-instructions.md` | Global Copilot instructions (all repos) | → `~/.copilot/copilot-instructions.md` |
| `.copilot/mcp-config.json` | MCP server configuration | → `~/.copilot/mcp-config.json` |
| `.copilot/lsp-config.json` | LSP server configuration | → `~/.copilot/lsp-config.json` |
| `.copilot/config.portable.json` | Portable settings (model, theme, etc.) | **No** — patched into `config.json` |
| `.copilot/skills/` | Custom skills | Directory junctions |
| `external/` | Cloned external skill repos (repos without `LocalPath`) | — |
| `setup.ps1` / `setup.sh` | Install: symlink configs, patch settings, clone externals, link skills | — |
| `restore.ps1` / `restore.sh` | Uninstall: remove symlinks, optionally restore backups | — |
| `sync-skills.ps1` / `sync-skills.sh` | Adopt untracked skills from `~/.copilot/skills/` | — |

## Adding a New Tracked Config File

Update **4 places** across the two setup scripts:

1. `$configFileLinks` array in `setup.ps1`
2. `CONFIG_FILE_LINKS` array in `setup.sh`
3. Backup file list (`$configFiles`) in `setup.ps1`
4. Backup file list (`for f in ...`) in `setup.sh`

Then copy the file into `.copilot/`, replace the original in `~/.copilot/` with a symlink, and update `README.md`.

## Checking for Uncommitted Work

Don't just run `git status`. Also compare `~/.copilot/` against the repo for **new untracked files** that should be adopted (e.g., a new `lsp-config.json` that appeared but isn't tracked yet). Key files to check:

```
~/.copilot/config.json          # machine-specific, NOT tracked (only patched)
~/.copilot/copilot-instructions.md  # should be symlink → repo
~/.copilot/mcp-config.json      # should be symlink → repo
~/.copilot/lsp-config.json      # should be symlink → repo
~/.copilot/skills/*             # should be directory junctions → repo or external/
```

## Secrets

MCP config uses `${VAR_NAME}` environment variable syntax. **Never hardcode API keys** in any config file. See `README.md` for required environment variables and how to set them.

## Secrets

MCP config uses `${VAR_NAME}` environment variable syntax. **Never hardcode API keys** in any config file. See `README.md` for required environment variables and how to set them.
