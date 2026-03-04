---
name: gh-pr-create
description: 'Create or edit GitHub PRs and issues with properly formatted markdown bodies. Use when user asks to create a PR, open a pull request, edit a PR body, create an issue, or when you need to use gh pr create, gh pr edit, or gh issue create. This skill MUST be used instead of running gh commands directly — it prevents PowerShell backtick escaping bugs that corrupt markdown formatting.'
license: MIT
allowed-tools: Bash
---

# GitHub PR & Issue Creator (PowerShell-Safe)

Create PRs, edit PR bodies, and create issues using the `gh` CLI without markdown corruption.

## Why This Skill Exists

PowerShell uses the backtick (`` ` ``) as its escape character. When you pass markdown containing backticks via `--body "..."`, PowerShell interprets them as escape sequences:

- `` `n `` → newline
- `` `t `` → tab
- `` `a `` → BEL character (U+0007)
- `` `5 `` → literal `5` (backtick stripped)

This causes commit SHAs like `` `58a3f49` `` to render as `\58a3f49\` on GitHub, and code spans to break silently. The body looks correct in the terminal but renders incorrectly on GitHub.com.

**The fix is simple: always write the body to a temp file and use `--body-file`.**

## Workflow

### 1. Verify GitHub Account

Before creating a PR, verify the active account matches the repo:

```powershell
gh auth status
```

- **EMU account** (`_microsoft` suffix) → for org repos (e.g., `mcaps-microsoft/*`)
- **Personal account** → for personal repos
- Switch if needed: `gh auth switch --user <account>`

### 2. Compose the PR/Issue Body

Write the body as a PowerShell here-string. This preserves all markdown formatting including backticks, tables, code blocks, and special characters:

```powershell
$body = @'
## Summary

Brief description of what this PR does and why.

## Changes

- First change with `inline code` preserved
- Second change referencing commit `abc1234`

## Testing

```bash
npm test
```
'@
```

**Body format guidelines:**
- Short summary sentence (what and why)
- Grouped bullet list of changes (use `###` subsections if 3+ categories)
- Footer: testing status, breaking changes, or migration notes if applicable
- Use markdown formatting freely — backticks, bold, tables, code blocks all work with `--body-file`

### 3. Write to Temp File

```powershell
$bodyFile = "$env:TEMP\gh-body-$(Get-Random).md"
$body | Out-File -FilePath $bodyFile -Encoding utf8NoBOM
```

Use `utf8NoBOM` encoding to prevent BOM characters from appearing in the GitHub rendering.

### 4. Execute the gh Command

**Create a new PR:**
```powershell
gh pr create --title "<type>: <description>" --body-file $bodyFile --base main
```

**Edit an existing PR body:**
```powershell
gh pr edit <number> --body-file $bodyFile
```

**Create an issue:**
```powershell
gh issue create --title "<title>" --body-file $bodyFile
```

**Edit an existing issue:**
```powershell
gh issue edit <number> --body-file $bodyFile
```

### 5. Clean Up

```powershell
Remove-Item $bodyFile -ErrorAction SilentlyContinue
```

## Complete Example — Creating a PR

```powershell
# 1. Compose body with a single-quoted here-string (no escaping needed)
$body = @'
## Summary

Add Redis caching layer to reduce database query latency.

## Changes

| File | Change |
|------|--------|
| `src/cache.ts` | New Redis cache wrapper with TTL support |
| `src/routes/users.ts` | Cache user profile queries (5min TTL) |
| `src/config.ts` | Add `REDIS_URL` environment variable |

## Testing

- All 47 existing tests pass
- Added 12 new cache tests (`src/__tests__/cache.test.ts`)
- Manual verification: profile page load time 250ms → 50ms

## Breaking Changes

None — caching is additive and falls back to direct DB on cache miss.
'@

# 2. Write to temp file
$bodyFile = "$env:TEMP\gh-body-$(Get-Random).md"
$body | Out-File -FilePath $bodyFile -Encoding utf8NoBOM

# 3. Create the PR
gh pr create --title "feat(cache): Add Redis caching for user profiles" --body-file $bodyFile --base main

# 4. Clean up
Remove-Item $bodyFile -ErrorAction SilentlyContinue
```

## Anti-Patterns — NEVER Do These

```powershell
# ❌ NEVER — inline --body with backticks
gh pr create --title "fix: Bug" --body "Fixed the bug in `auth.js` by updating `refreshToken()`"
# Result on GitHub: "Fixed the bug in \auth.js\ by updating \refreshToken()\\"

# ❌ NEVER — double-quoted here-string (allows variable expansion + backtick escaping)
$body = @"
Fixed `$commitSha` issue
"@
# Result: backticks may still be interpreted, variables expanded unexpectedly

# ❌ NEVER — escaping backticks with more backticks
gh pr create --body "Fixed ``auth.js`` issue"
# Result: fragile, inconsistent across PowerShell versions

# ❌ NEVER — gh pr edit with inline --body
gh pr edit 42 --body "Updated `config.ts`"
# Same corruption as gh pr create
```

## Choosing Here-String Type

| Syntax | Backticks | Variables | Use When |
|--------|-----------|-----------|----------|
| `@'...'@` (single-quoted) | ✅ Literal | ❌ Not expanded | Body has no PowerShell variables |
| `@"..."@` (double-quoted) | ⚠️ Escaped | ✅ Expanded | Body needs `$variable` interpolation |

**Prefer single-quoted `@'...'@`** — it treats everything as literal text, which is what you want for markdown. Only use `@"..."@` when you need to embed PowerShell variables (and in that case, escape backticks as ` `` `).

## Checklist

- [ ] Active GitHub account matches the target repo (`gh auth status`)
- [ ] Body written to temp file with `Out-File -Encoding utf8NoBOM`
- [ ] Used `--body-file`, NOT `--body`
- [ ] Temp file cleaned up after command completes
- [ ] PR title follows conventional commit format: `<type>[scope]: <description>`
