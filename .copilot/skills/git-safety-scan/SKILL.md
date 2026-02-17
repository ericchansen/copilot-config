# Git Safety Scan

Scan staged changes or commits for sensitive data before pushing to remote.

## When to Use

**MANDATORY before ANY git push.** Invoke this skill automatically whenever:
- User asks to push code
- User asks to create a PR
- User says "commit and push" or similar

## Scanning Process

### Step 1: Check for User Blocklist

Look for a blocklist file at `~/.copilot/sensitive-terms.txt`. If it exists, read it and flag any matches in the diff.

```bash
# Check if blocklist exists
if (Test-Path "$env:USERPROFILE\.copilot\sensitive-terms.txt") {
    Get-Content "$env:USERPROFILE\.copilot\sensitive-terms.txt"
}
```

The blocklist is one term per line (case-insensitive). Example:
```
Contoso Corp
John Smith
project-apollo
```

### Step 2: Smart Pattern Detection

Scan `git diff` output for these patterns (even without a blocklist):

#### High-Risk Patterns (BLOCK immediately)
| Pattern | Example | Why |
|---------|---------|-----|
| **API keys/tokens** | `sk-`, `ghp_`, `ctx7sk-`, `Bearer ` | Credentials |
| **Connection strings** | `Server=`, `connectionString`, `mongodb://` | Database access |
| **Private keys** | `-----BEGIN`, `.pem`, `.pfx` | Cryptographic material |
| **Passwords** | `password=`, `pwd=`, `secret=` | Auth credentials |
| **AWS/Azure keys** | `AKIA`, `AccountKey=` | Cloud credentials |

#### Medium-Risk Patterns (WARN and confirm)
| Pattern | Example | Why |
|---------|---------|-----|
| **Real dollar amounts** | `$1,234,567`, `$50M` | Deal values |
| **MSX opportunity IDs** | `7-[A-Z0-9]{9}` (e.g., `7-3FER7U7HPD`) | Internal identifiers |
| **Phone numbers** | `(555) 123-4567`, `+1-555-` | PII |
| **Email addresses** | `user@company.com` (non-example domains) | PII |
| **Internal URLs** | `*.dynamics.com`, `*.sharepoint.com` | Internal systems |
| **GUIDs with context** | `id=abc123-...` in URLs | Resource identifiers |

#### Heuristic Detection (WARN)
| Pattern | Example | Why |
|---------|---------|-----|
| **Company-like names** | Capitalized multi-word names not in fictional list | Possible customer names |
| **Person names** | "worked with John Smith on..." | PII |
| **Specific dates + names** | "Meeting with X on Jan 15" | Activity details |

### Step 3: Known-Safe Terms

Do NOT flag these Microsoft fictional company names:
- Contoso, Fabrikam, Northwind, Adatum, Adventure Works
- Consolidated Messenger, Tailspin Toys, WingTip Toys
- Fourth Coffee, Litware, Proseware, Trey Research

Do NOT flag:
- Example domains: `example.com`, `contoso.com`, `fabrikam.com`
- Placeholder emails: `user@example.com`, `test@test.com`
- Microsoft product names: Azure, GitHub, Dynamics, etc.
- Generic competitor names in context: "AWS", "GCP", "Google Cloud"

### Step 4: Report and Block

If ANY high-risk patterns found:
```
🛑 BLOCKED: Found sensitive data in staged changes

HIGH RISK (must fix before push):
  - src/config.js:15 — API key pattern: "sk-abc123..."
  - .env:3 — Connection string found

Action: Remove secrets, add to .gitignore, use environment variables
```

If medium-risk or heuristic patterns found:
```
⚠️ WARNING: Possible sensitive data detected

REVIEW REQUIRED:
  - docs/notes.md:42 — Dollar amount: "$2.5M deal"
  - reports/summary.md:8 — Possible company name: "Acme Corp"

Action: User must confirm these are safe to push
```

## Commands

```bash
# Scan staged changes
git diff --staged

# Scan commits not yet pushed  
git diff origin/main..HEAD

# Check specific files
git diff --staged -- "*.md" "*.docx"
```

## User Blocklist Setup

Users can create `~/.copilot/sensitive-terms.txt` with terms to always block:

```
# Customer names
Acme Corp
Globex Industries

# Project codenames
project-phoenix
operation-sunrise

# Internal team names
tiger-team-alpha
```

Lines starting with `#` are comments. One term per line, case-insensitive matching.

## Critical Rules

1. **NEVER push if high-risk patterns are found** — no exceptions
2. **ALWAYS show the user what will be pushed** — they must review
3. **ALWAYS ask for explicit confirmation** — "Do you want to push these changes?"
4. **If in doubt, STOP and ask** — false positives are better than leaks
5. **This skill cannot be skipped** — it's mandatory for all pushes
