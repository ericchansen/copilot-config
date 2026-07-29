---
name: github-writer
description: "Use for any GitHub CLI command that writes PR, issue, or comment content. Prevents shell encoding corruption by writing markdown to a body file first and enforces content quality: no machine-specific paths, generic repro steps, and structured sections. Triggers: github-writer, gh-writer, create PR, open pull request, edit PR, create issue, edit issue, comment on issue, push and create PR, gh pr, gh issue, file a bug, open a bug."
license: MIT
allowed-tools: Bash, PowerShell
---

# GitHub Content Writer

Write PRs, issues, and comments using `gh` CLI with encoding safety AND content quality enforcement.

## When to Use

**MANDATORY** whenever writing content to GitHub:
- `gh pr create` / `gh pr edit`
- `gh issue create` / `gh issue edit`
- `gh issue comment`
- Any `gh` command with `--body` or that produces markdown content

## Workflow

### 1. Verify GitHub Account

Check the active account matches the target repo:
```powershell
gh auth status
```
Switch if needed (see Multi-Account Git Authentication in copilot-instructions.md).

### 2. Compose the Content

Write the body content to a temporary markdown file first, then pass that file to `gh` with `--body-file`. This avoids shell quoting and encoding issues with inline markdown.

Choose a temp file path and use it consistently in steps 2-5:
```powershell
$bodyFile = "$env:TEMP\gh-body-$(Get-Random).md"
```

Use the available file-writing tool or editor to write content to that exact path. Avoid inline shell strings for markdown bodies; they are easy to corrupt with escaping, newlines, and non-ASCII characters.

### 3. Content Quality Rules

Before writing the file, review your content against these rules:

#### Encoding Safety
- **Never** use `--body "..."` inline -- shells corrupt backticks, quotes, and special chars
- **Never** use double-quoted here-strings (`@"..."@`) in PowerShell -- they allow backtick escaping
- **Always** write markdown to a temp file first, then use `--body-file`
- **Avoid non-ASCII** when possible: use `--` instead of em-dash, `->` instead of arrows

#### Markdown Source Layout
- **Never** hard-wrap PR, issue, or comment prose at 72, 80, or any other fixed column
- Keep each logical paragraph on one physical source line and retain blank lines between paragraphs and sections
- Keep each Markdown bullet on one physical source line
- Let GitHub soft-wrap prose and bullets visually to fit the available width

#### No Machine-Specific Content
- **Never** include real usernames, machine names, or user-specific paths
  - Bad: `C:\Users\<username>\.copilot\config.json`
  - Good: `~/.copilot/config.json`
- **Never** reference specific plugin/repo names from the user's system as if they're universal
  - Bad: "Tested with `copilot-config` plugin"
  - Good: "Tested with a local plugin (`marketplace: \"local\"`)"
- **Never** include real TPIDs, opportunity IDs, email addresses, or customer names
- Use generic placeholders: `owner/repo`, `my-plugin`, `<name>`, `example.com`

#### Structured Sections (for bug reports/issues)

Bug reports MUST include:
```markdown
### Environment
- **CLI/tool version:** (get this programmatically, don't guess)
- **OS:** (e.g., Windows 11, macOS 14)
- **Shell:** (e.g., PowerShell 7, zsh)

### Steps to Reproduce
1. (Generic, reproducible steps anyone can follow)
2. (Use placeholder names, not real ones)

### Expected Behavior
(What should happen)

### Observed Behavior
(What actually happens -- include evidence like tables, error messages)
```

Optional sections (include when helpful):
- `### Impact` -- who/what is affected
- `### Suggested Fix` -- if you have a concrete suggestion
- `### Related` -- links to related issues/PRs

#### Version Info
- Always include the tool/CLI version in the Environment section
- Get it programmatically (`copilot --version`, `node --version`, etc.)
- Don't guess or hardcode versions

### 4. Execute the gh Command

```powershell
# Create issue
gh issue create --repo owner/repo --title "Bug: short description" --body-file $bodyFile

# Edit issue
gh issue edit <number> --repo owner/repo --body-file $bodyFile

# Comment on issue
gh issue comment <number> --repo owner/repo --body-file $bodyFile

# Create PR
gh pr create --title "<type>: <description>" --body-file $bodyFile --base main

# Edit PR
gh pr edit <number> --body-file $bodyFile
```

### 5. Clean Up

```powershell
Remove-Item $bodyFile -ErrorAction SilentlyContinue
```

## PR Body Format

```markdown
## Summary

Explain what this PR changes and why the change is needed in one logical paragraph on one physical source line, even when the sentence is long enough for GitHub to wrap visually.

### Changes

- Keep each grouped bullet on one physical source line and use `inline code` for file or function names where that makes the change easier to identify.
- Preserve blank lines between sections, but do not insert source line breaks solely to fit a fixed text width.

### Testing

- Describe how the change was tested and include the relevant result on one physical source line.
```

## Issue Title Conventions

- Bug reports: `Bug: <concise description of what's wrong>`
- Feature requests: `Feature: <concise description of desired behavior>`
- Include version when relevant: `Bug: X does not work on v1.2.3`

## Critical Rules

1. **ALWAYS** use `--body-file` with a temp markdown file -- no exceptions
2. **NEVER** hard-wrap prose or bullets to a fixed column -- let GitHub soft-wrap them
3. **NEVER** include machine-specific info -- sanitize before writing
4. **ALWAYS** include version info in bug reports -- get it programmatically
5. **ALWAYS** use generic placeholders in reproduction steps
6. **REVIEW** content for PII/internal data before posting -- treat this as a public-facing communication
