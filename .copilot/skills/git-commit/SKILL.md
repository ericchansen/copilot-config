---
name: git-commit
description: 'Execute git commit with conventional commit message analysis, intelligent staging, and message generation. Use when user asks to commit changes, create a git commit, or mentions "/commit". Supports: (1) Auto-detecting type and scope from changes, (2) Generating conventional commit messages from diff, (3) Interactive commit with optional type/scope/description overrides, (4) Intelligent file staging for logical grouping'
license: MIT
allowed-tools: Bash
---

# Git Commit with Conventional Commits

Create standardized, semantic git commits using the Conventional Commits specification combined with Chris Beams' seven rules. Analyze the actual diff to determine appropriate type, scope, and message.

## Conventional Commit Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Commit Types

| Type       | Purpose                        |
| ---------- | ------------------------------ |
| `feat`     | New feature                    |
| `fix`      | Bug fix                        |
| `docs`     | Documentation only             |
| `style`    | Formatting/style (no logic)    |
| `refactor` | Code refactor (no feature/fix) |
| `perf`     | Performance improvement        |
| `test`     | Add/update tests               |
| `build`    | Build system/dependencies      |
| `ci`       | CI/config changes              |
| `chore`    | Maintenance/misc               |
| `revert`   | Revert commit                  |

## The Seven Rules

### 1. Separate subject from body with a blank line

### 2. Limit the subject line to 50 characters
Aim for 50 characters (soft limit). Maximum 72 characters (hard limit).

### 3. Capitalize the subject line
`feat: Add feature` not `feat: add feature`

### 4. Do not end the subject line with a period

### 5. Use the imperative mood in the subject line
"Add feature" not "Added feature" or "Adds feature".

**Validation test:** "If applied, this commit will _[your subject line here]_"

### 6. Wrap the body at 72 characters

### 7. Use the body to explain what and why vs. how
The diff shows what changed. The body explains why.

## Workflow

### 1. Analyze Diff

```bash
# If files are staged, use staged diff
git diff --staged

# If nothing staged, use working tree diff
git diff

# Also check status
git status --porcelain
```

### 2. Stage Files (if needed)

```bash
# Stage specific files
git add path/to/file1 path/to/file2

# Stage by pattern
git add *.test.*
git add src/components/*

# Interactive staging
git add -p
```

**Never commit secrets** (.env, credentials.json, private keys).

### 3. Generate Commit Message

Analyze the diff to determine:

- **Type**: What kind of change is this?
- **Scope**: What area/module is affected?
- **Description**: One-line summary (present tense, imperative mood, <72 chars)

### 4. Execute Commit

```bash
# Single line
git commit -m "<type>[scope]: <description>"

# Multi-line with body/footer
git commit -m "$(cat <<'EOF'
<type>[scope]: <description>

<optional body>

<optional footer>
EOF
)"
```

## Breaking Changes

```
# Exclamation mark after type/scope
feat!: remove deprecated endpoint

# BREAKING CHANGE footer
feat: allow config to extend other configs

BREAKING CHANGE: `extends` key behavior changed
```

## Examples

### ✅ Good Examples

```
feat: Add caching to database queries

Application was making redundant database calls for user profile
data on every request, causing 200ms latency on profile pages.

Implement Redis-based caching layer with 5-minute TTL for user
profiles. Cache is invalidated on profile updates. Reduces
profile page load time from 250ms to 50ms in production.

Closes #42
```

```
fix: Resolve autofix preflight failures

Autofix preflight aborted in --yes/--dry-run because debug
logging returned non-zero when ACFS_DEBUG was off.

Fix debug logging to always succeed and initialize change-recording
state before writes.
```

```
docs: Fix typo in installation documentation
```

```
chore: Update Node.js to v20 LTS
```

### ❌ Bad Examples

- `fixed the bug` - No type prefix, past tense, too vague
- `Updated files` - No type prefix, past tense, lists files
- `Add feature.` - No type prefix, ends with period
- `feat add thing` - Missing colon after type

## Pre-Commit Checklist

- [ ] Starts with valid type prefix (`feat:`, `fix:`, etc.)
- [ ] Subject ≤50 characters (hard max 72)
- [ ] Capitalized first word after prefix
- [ ] No trailing period
- [ ] Uses imperative mood
- [ ] Body explains what and why (if present)

## Git Safety Protocol

- NEVER update git config
- NEVER run destructive commands (--force, hard reset) without explicit request
- NEVER skip hooks (--no-verify) unless user asks
- NEVER force push to main/master
- If commit fails due to hooks, fix and create NEW commit (don't amend)

## Reference

- Conventional Commits: https://www.conventionalcommits.org/
- Chris Beams' guide: https://cbea.ms/git-commit/
