# copilot-marketplace

Personal multi-harness marketplace of independently installable skill plugins. The skills use
the open [Agent Skills](https://agentskills.io) `SKILL.md` format, so the same
plugins install across **GitHub Copilot CLI**, **Claude Code**, and **OpenAI
Codex**, and can be reused in **opencode**.

## Install

### GitHub Copilot CLI

Open Copilot CLI, then register this marketplace once:

```text
copilot
/plugin marketplace add ericchansen/copilot-marketplace
```

Install plugins individually:

```text
/plugin install doc-generator@copilot-marketplace
```

Replace `doc-generator` with any plugin name below.

### Claude Code

Claude Code reads `.claude-plugin/marketplace.json` (kept byte-identical to the
Copilot manifest):

```text
/plugin marketplace add ericchansen/copilot-marketplace
/plugin install doc-generator@copilot-marketplace
```

### OpenAI Codex

Codex reads the repo catalog at `.agents/plugins/marketplace.json`:

```text
codex plugin marketplace add ericchansen/copilot-marketplace
codex/plugins   # open the plugin browser, pick this marketplace, install a plugin
```

### opencode

opencode has no remote marketplace — it discovers skills from local directories.
To use a skill, copy (or symlink) its skill folder into a scanned path, e.g. into
your global config:

```bash
# copy one skill (repeat per skill you want)
cp -R plugins/doc-generator/skills/doc-generator ~/.config/opencode/skills/doc-generator
# or into a project you're working in:
cp -R plugins/doc-generator/skills/doc-generator .agents/skills/doc-generator
```

opencode reads `SKILL.md` from `.opencode/skills/`, `.claude/skills/`, and
`.agents/skills/` (project and `~/` global). It ignores the `allowed-tools`
field.

## Plugins

- `api-reverse-engineer` — Capture browser network requests through Chrome DevTools Protocol when a web UI is the only reliable API reference.
- `azure-doctor` — Diagnose and fix Azure deployments across repos, CI/CD pipelines, subscriptions, and service health.
- `clean` — Perform post-merge git cleanup by returning to main/master, pulling latest, deleting merged branches, pruning remotes, and verifying a clean state.
- `doc-generator` — Generate professional PDF and Word (DOCX) documents from markdown source files.
- `edge-browser` — Launch Microsoft Edge with a specific user profile and remote debugging enabled for CDP control.
- `foundry-image-gen` — Generate and edit images using GPT-Image-2 deployed in Azure AI Foundry.
- `git-code-review` — Run a structured closeout review over local, branch, commit, or PR diffs before shipping.
- `git-commit` — Create conventional commits with diff analysis, safe staging, and repository guideline awareness.
- `git-safety-scan` — Scan staged changes or commits for sensitive data before pushing to remote.
- `github-writer` — Write PRs, issues, and comments for GitHub with encoding-safe body files and sanitized, structured content.
- `meeting-transcription` — Locally transcribe recorded meetings, identify speakers, and produce evidence-based meeting notes.
- `pr-review-address` — Review, address, and resolve GitHub PR feedback across comments, review threads, and requested changes.

## Repository structure

```text
.github/plugin/marketplace.json   Copilot CLI marketplace (source of truth)
.claude-plugin/marketplace.json   Claude Code marketplace (byte-identical mirror)
.agents/plugins/marketplace.json  Codex repo marketplace catalog
plugins/<name>/
  plugin.json                     Copilot/Claude plugin manifest
  .codex-plugin/plugin.json       Codex plugin manifest
  skills/<name>/SKILL.md          Agent Skills (agentskills.io) definition
```

Skill helper files live beside their `SKILL.md` files. The marketplace
manifests are kept in sync by the `Validate` workflow. `copilot-home/` holds the
portable user-level config (settings, MCP/LSP servers, instructions) deployed to
`~/.copilot/` via `copilot-home/link.ps1` — see `copilot-home/README.md`.
