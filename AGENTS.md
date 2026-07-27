# AGENTS.md — copilot-marketplace (personal)

## Repository Purpose

A **multi-harness marketplace** of personal plugins. Each skill is its own
independently installable plugin, and the skills use the open
[Agent Skills](https://agentskills.io) `SKILL.md` format so they work across
**GitHub Copilot CLI**, **Claude Code**, and **OpenAI Codex** (and are reusable
in **opencode**).

```bash
# Copilot CLI (shell)
copilot plugin marketplace add ericchansen/copilot-marketplace
copilot plugin install doc-generator@copilot-marketplace
# Codex (shell)
codex plugin marketplace add ericchansen/copilot-marketplace
```

Claude Code installs the same marketplace from its in-session slash commands
(`/plugin marketplace add ericchansen/copilot-marketplace`, then
`/plugin install <name>@copilot-marketplace`) — see README for per-harness details.

MCP and LSP servers are **not** bundled here — they are defined once in synced
user config (`~/.copilot/mcp-config.json`, `~/.copilot/lsp-config.json`).

## Repository Structure

```
.github/plugin/marketplace.json   — Copilot CLI marketplace (SOURCE OF TRUTH)
.claude-plugin/marketplace.json   — Claude Code marketplace (BYTE-IDENTICAL mirror of the above)
.agents/plugins/marketplace.json  — Codex repo marketplace catalog (distinct schema; same plugin set)
plugins/<name>/
  plugin.json                     — Copilot/Claude plugin manifest (name, version, "skills": "skills/")
  .codex-plugin/plugin.json       — Codex plugin manifest (name, version, "skills": "./skills/")
  skills/<name>/SKILL.md          — Skill definition with YAML frontmatter (+ any helper files)
copilot-home/                     — Portable user-level config deployed to ~/.copilot via link.ps1
  settings.json                     home profile: prefs + marketplace + enabledPlugins
  mcp-config.json                   general dev MCP servers
  lsp-config.json                   LSP servers (typescript, python, rust)
  link.ps1                          deploys the config (symlink + merge-aware settings)
  copilot-instructions.md           global custom instructions
AGENTS.md, README.md, LICENSE
```

Claude Code auto-discovers each plugin's `skills/` directory on install, so no
per-plugin `.claude-plugin/plugin.json` is needed. opencode has no remote install;
users copy skill folders into a scanned skills dir (see README).

## Adding a Plugin

1. Create `plugins/{name}/plugin.json` (`name`, `version`, `"skills": "skills/"`).
2. Create `plugins/{name}/.codex-plugin/plugin.json` (`name`, `version`,
   `"skills": "./skills/"`) — keep `name`/`version` identical to `plugin.json`.
3. Create `plugins/{name}/skills/{name}/SKILL.md` with YAML frontmatter
   (`name`, `description`, `license`, `allowed-tools`); add any helper files alongside it.
4. Add an entry to `.github/plugin/marketplace.json` (`name`, `source: plugins/{name}`, `description`, `version`).
5. Mirror the change into `.claude-plugin/marketplace.json` — it must stay
   **byte-identical** (`cp .github/plugin/marketplace.json .claude-plugin/marketplace.json`).
6. Add a matching entry to `.agents/plugins/marketplace.json` (Codex schema:
   `source: { source: "local", path: "./plugins/{name}" }`, `interface.displayName`,
   `policy`, `category`).

The `Validate` workflow enforces that all marketplace manifests list the
same plugins and that the Codex manifests match each `plugin.json`.

## Skill YAML Frontmatter

Every `SKILL.md` must have:

```yaml
---
name: my-skill
description: 'Brief description with trigger words'
license: MIT
allowed-tools: Bash, PowerShell
---
```

## Releases

`version` is per plugin in each `plugins/<name>/plugin.json`. The repo-level tag
(`vX.Y.Z`) must match `metadata.version` in `marketplace.json` (enforced by the
Release workflow). Bump, tag, and push to publish.

Any change under `plugins/<name>/` that affects shipped plugin behavior or content
must bump that plugin's SemVer in the same PR. Use a patch bump by default; use
minor or major only when feature or breaking-change semantics require it.
Synchronize every version-bearing plugin manifest and catalog entry, run the
existing validation, and verify no version surface was missed.

## Formatting

File formatting is enforced by [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker)
against `.editorconfig` (the `Lint` workflow). Run it locally with `npx editorconfig-checker`.
Indentation enforcement is disabled in `.editorconfig-checker.json`; line endings are
normalized to LF via `.gitattributes`.
