---
name: git-commit
description: 'Execute git commits with conventional commit message analysis, intelligent staging, and message generation. Use when the user asks to commit changes, create a git commit, push code after committing, combine committing with opening a PR, or mentions "/commit". Do not use for creating or editing a PR alone; PR body formatting belongs to github-writer. Supports: (1) Auto-detecting type and scope from changes, (2) Generating conventional commit messages from diff, (3) Interactive commit with optional type/scope/description overrides, (4) Intelligent file staging for logical grouping, (5) Respecting repository contribution guidelines'
license: MIT
allowed-tools: Bash, PowerShell
---

# Git Commit with Conventional Commits

Create standardized git commits using Conventional Commits + Chris Beams' seven rules.

## Pre-Flight

1. Check for repo contribution guidelines (`CONTRIBUTING.md`, `AGENTS.md`). Repo rules override defaults below.
2. Ensure you're on a feature branch — never commit to `main`/`master`.
3. Run the repository's required safety or secret scan before committing or pushing. If the `git-safety-scan` skill is installed, use it.

## Format

```
<type>[optional scope]: <description>

[optional body — explain what and why, not how]

[optional footer(s)]
```

## Types

| Type | Purpose | Type | Purpose |
|------|---------|------|---------|
| `feat` | New feature | `test` | Add/update tests |
| `fix` | Bug fix | `build` | Build/dependencies |
| `docs` | Documentation | `ci` | CI/config changes |
| `refactor` | Refactor (no feature/fix) | `chore` | Maintenance |
| `perf` | Performance | `revert` | Revert commit |

## Rules

- Subject: target ≤50 chars, hard max 72; capitalized, imperative mood, no trailing period
- Validation: "If applied, this commit will _[subject]_"
- Body wraps at 72 chars, explains what and why
- Breaking changes: `feat!: ...` or `BREAKING CHANGE:` footer

## Workflow

1. **Analyze**: `git diff --staged` (or `git diff` if nothing staged)
2. **Stage**: `git add` relevant files. Never commit secrets.
3. **Generate message**: Determine type, scope, description from the diff.
4. **Commit**: `git commit -m "<type>[scope]: <description>"`

## Safety

- Never update git config or run destructive commands without explicit request
- Never skip hooks (`--no-verify`) unless user asks
- Never force push to main/master

# New Commit or Amend

If you're working in a feature branch or PR, does this commit refactor, rewrite or fix code that was introduced in the same feature branch or PR? If so, consider using `git commit --amend` to update the existing commit instead of creating a new one. This helps keep the commit history clean and focused on logical changes.
