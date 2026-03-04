# Global Copilot Instructions

## Quick Reference

| Rule | Details |
|------|---------|
| **Never commit broken code** | Linter + full test suite must pass first |
| **⚠️ RUN E2E TESTS LOCALLY** | **MANDATORY before ANY push** — no exceptions |
| **🛑 NEVER PUSH WITHOUT REVIEW** | **User must review `git diff` before ANY push** — invoke `git-safety-scan` skill |
| **🚫 NEVER push to main/master** | **HARD BLOCK: No git push to main/master on ANY remote, for ANY reason, even "trivial" changes, even deprecated repos. No exceptions. Always use a feature branch + PR.** |
| **Commit locally by default** | Only push when explicitly asked |
| **Cite everything** | Every stat/claim needs a clickable URL |
| **Challenge assumptions** | Question approaches, push back with evidence |
| **Research first** | Use Context7 / Microsoft Learn MCP before implementing |
| **✅ Verify before claiming** | **EXHAUSTIVELY test/check yourself** (load page, hit endpoints, check data, take screenshots) before saying it works — a health check or HTTP 200 is NOT verification. Triple-check. |
| **🔬 Exhaust testing abilities** | **NEVER say "done" until double/triple checked** — run builds, run tests, load URLs, query DBs. Leave no stone unturned. |
| **🔐 Multiple GitHub accounts** | **`gh auth status` when git/gh ops fail** — wrong account is the most common cause |
| **🔍 Check before asking** | **NEVER ask the user a question you could answer by reading a file, running a command, or checking yourself** — investigate first, ask only when you genuinely can't determine the answer |
| **🚫 Never remove features silently** | **NEVER remove features, capabilities, or functionality based on internal reasoning without asking the user first** — even if it seems like a good idea |


## Git Workflow

**Prefixes:** `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`, `perf`

### Branching
- **🔐 When git/gh operations fail, check for multiple GitHub accounts** — run `gh auth status`. There may be multiple accounts configured (e.g., work EMU + personal). The wrong active account causes "Repository not found", 403s, SAML errors, and API failures that look like permission issues. If the active account doesn't match the repo, switch: `gh auth switch --user <account>`.
- **🚫 NEVER push to `main` or `master` on ANY remote** — this is an absolute rule with ZERO exceptions
  - Not even for "small" changes, README updates, redirects, or deprecated repos
  - Not even if the user's request implies it — create a branch and PR instead
  - If you catch yourself about to run `git push <remote> ...:main` or `git push <remote> ...:master` — **STOP**
- **🔀 ALWAYS create a feature branch BEFORE making any changes** — this is your FIRST step, not an afterthought
  - Check `git branch --show-current` at the start of every task
  - If on `main`/`master`, create a branch immediately: `git checkout -b <type>/<short-description>`
  - Do NOT make edits, stage files, or commit while on `main`/`master`
- Follow repo-specific instructions (AGENTS.md, CONTRIBUTING.md, etc.)
- If no repo guidance exists, use feature branches: `git checkout -b <type>/<short-description>`
- **Git worktrees** — use `git worktree add` when working on multiple branches simultaneously or when the user needs to preserve their current working tree (e.g., they have uncommitted changes on another branch)

### During Development
- Run tests after each logical change—catch failures early
- Commit frequently with clear messages

### Before Any Commit
1. Run linter (`ruff check .`, `npm run lint`, etc.)
2. Start test infra if needed (`docker-compose up -d`)
3. Run FULL unit test suite—all tests, not just affected
4. **⚠️ RUN E2E TESTS LOCALLY — THIS IS MANDATORY**
   - Command: `npx playwright test --project="msedge"`
   - Do NOT skip this step. Do NOT push without running E2E first.
   - E2E tests catch integration bugs that unit tests miss.
   - If E2E tests fail locally, they WILL fail in CI. Fix them first.
5. **🔑 Scan staged diff for secrets AND PII — MANDATORY**
   - Check `git diff --staged` for: API keys, tokens, passwords, connection strings, private keys, `.pem`/`.pfx` files
   - **Also scan for PII**: real usernames, GitHub account names, email addresses, SSH host aliases, org names, colleague names
   - Common patterns: `sk-`, `ctx7sk-`, `ghp_`, `Bearer `, `password=`, `connectionString`, `-----BEGIN`
   - **Always check `~/.copilot/sensitive-terms.txt`** — contains user-specific blocklist terms
   - If ANY secrets or PII are found: **STOP — do not commit**
   - Alert the user with the exact file and line
   - Use generic placeholders (`<account>`, `<org>`, `<host>`) instead of real identifiers
   - Move secrets to environment variables or `.env` files (must be in `.gitignore`)
6. UI apps: validate with Playwright MCP browser tools (uses **Edge**, not Chrome)
7. Azure apps: deploy and validate with Playwright MCP browser tools
8. **If tests fail**: fix first, never commit broken code
9. **If tests won't run**: research (Context7, MS Learn), then ask user

### Commit
```bash
git commit -m "<type>: <description>"  # Use git-commit skill
```

### Push & PR
- **Do NOT push or create PRs unless the user explicitly asks**
- Default is local-only: commit, but don't push
- **🔐 If push or PR creation fails, check `gh auth status`** — multiple accounts may be configured; wrong active account = "not found" or 403.
- **🛑 NEVER push directly to `main` or `master` on ANY remote** — always push a feature branch and open a PR. This applies to ALL remotes (origin, upstream, forks, deprecated repos — no exceptions).
- **🛑 BEFORE ANY PUSH — MANDATORY REVIEW:**
  1. **Invoke the `git-safety-scan` skill** — this scans for sensitive data
  2. **Show `git diff origin/main..HEAD --stat` to the user** — they MUST review what's being pushed
  3. **Ask user to confirm** — never push without explicit "yes, push it" confirmation
  4. If scan finds issues or user doesn't confirm: **STOP — do not push**
- When asked to push (after review):
  ```bash
  git push -u origin <branch-name>
  ```
- **Always offer to create a PR** after pushing a branch — submit work via PRs, not direct pushes
- If the upstream repo is not owned by the user (e.g., a Microsoft org repo), fork first, then open a PR from the fork

### Creating PRs and Issues
- **⚠️ NEVER use inline `--body` with ANY `gh` command** (`gh pr create`, `gh pr edit`, `gh issue create`, etc.) — backticks and special characters get mangled by PowerShell escaping (backtick is PS's escape char, so `\`` becomes literal `\`). **Always use `--body-file`:**
  ```powershell
  $body = @"
  ## Summary
  Fixed the bug in `auth.js`...
  "@
  $body | Out-File -FilePath "$env:TEMP\gh-body.md" -Encoding utf8NoBOM
  gh pr create --title "fix: Auth bug" --body-file "$env:TEMP\gh-body.md" --base main
  Remove-Item "$env:TEMP\gh-body.md" -ErrorAction SilentlyContinue
  ```
- **This applies to `gh pr edit --body` too** — use `--body-file` for edits
- **PR body format:** concise and scannable
  - Short summary sentence (what and why)
  - Grouped bullet list of changes (use `###` subsections if 3+ categories)
  - Footer: testing status, breaking changes, or migration notes if applicable
  - Use markdown formatting (backticks, bold, links) — the `--body-file` approach preserves it all

### ⚠️ Multi-Account Git Authentication

> **Multiple GitHub accounts may be configured on this machine (e.g., enterprise EMU + personal). When any git/gh operation fails unexpectedly, the wrong active account is the most likely cause. CHECK FIRST.**

**Account types and their limitations:**
- **Enterprise Managed User (EMU)** — for org repos. **CANNOT** create/access personal repos, transfer repos to itself, or interact with non-enterprise orgs.
- **Personal** — for personal repos, OSS, forks. **CANNOT** access enterprise org repos or SAML-protected resources.
- They are **not interchangeable** — using the wrong one silently fails.

**When something fails, check immediately:**
```bash
gh auth status  # Which account is active? Are there multiple?
```
If the active account doesn't match the repo you're working with → `gh auth switch --user <account>` and retry.

**SSH host aliases**: `~/.ssh/config` maps different SSH hosts to different keys. The default `github.com` host uses the personal key; a `-work` alias uses the work key.

**SAML-protected orgs**: Microsoft org repos require SAML SSO. If SSH keys aren't SAML-authorized, fall back to HTTPS:
```bash
gh auth switch --user <work-account>
git -c credential.helper="!gh auth git-credential" pull
```

**Common failure patterns — ALL caused by wrong active account:**
| Symptom | Cause | Fix |
|---------|-------|-----|
| "Repository not found" | Wrong account active | `gh auth switch --user <account>` |
| 403 Forbidden | Wrong account for org | Switch to account with org access |
| SAML SSO required | SSH key not SAML-authorized | Fall back to HTTPS (see above) |
| `gh pr create` fails | EMU can't access personal repo (or vice versa) | Switch to the account that owns the repo |
| `gh auth refresh` authenticates wrong account | Device flow defaults to browser's logged-in account | Open incognito, log into correct account first |
| "Resource not accessible by integration" | API token from wrong account | `gh auth switch`, then retry |

**After finishing work on a repo owned by one account, switch back if needed.** Don't leave the wrong account active — it will bite the next operation.

### Clean Commit History (No Merge Commits)
- **Prefer linear history** — avoid merge commits when possible
- Use `git rebase` before merging or pushing
- Use `git merge --ff-only` for local merges
- If a PR, prefer **"Rebase and merge"** — never "Create a merge commit"
- Every commit should be a clean, readable unit

## Environment & Azure

- **Playwright E2E Testing**: 
  - **ALWAYS run E2E tests locally before pushing**: `npx playwright test --project="Desktop Edge"`
  - Use **Microsoft Edge only** — Chrome is NOT available
  - MCP browser tools: Already configured for Edge
  - CLI tests: Always use `--project="msedge"`, never "Desktop Chrome"
  - CI should also run only Edge to keep pipeline times reasonable
- **Docker Containers**:
  - **NEVER stop, remove, or modify containers from other projects**
  - Only interact with containers explicitly associated with the current project
  - If port conflicts occur, modify the current project's docker-compose.yml (use different ports), do NOT kill other containers
  - Always check container names before any docker stop/rm commands
- **Databases**: Never pollute production—use temp/test DBs
- **Azure naming**: `<type>-<app>-<env>` (e.g., `rg-itemwise-prod`, `acr-myapp-dev`)
  - Never use generic names like `prod` or `dev`—subscriptions have many apps

## How I (Eric) Should Prompt Better

_Based on analysis of 153 sessions from Jan–Feb 2026._

### 1. State constraints upfront, not as corrections
**Problem**: ~14% of sessions had mid-stream "Actually..." corrections (21/153 sessions). Examples:
- "Actually, I changed my mind. This is just a demo." → Wasted work on over-engineered solution
- "Actually, can we pause work on this issue? I'd rather address the naming first." → Context switch
- "Actually, the colors for all of them would need updating" → Scope expanded after work started

**Fix**: Front-load constraints in the initial prompt:
```
❌ "Deploy this to Azure" ... (later) "Actually, this is just a demo. I don't want to spend unnecessarily."
✅ "Deploy this to Azure. Keep it minimal/cheap — this is just a demo, not production."
```

### 2. Avoid vague follow-ups when context matters
**Problem**: 60% of sessions had very short messages (<30 chars) like "Go ahead", "Continue", "What's the status?", "Get to work on some stuff". These are fine for simple confirmations, but cause problems when:
- The agent has multiple pending tasks and doesn't know which to prioritize
- Context was lost from a PC restart or session boundary

**Fix**: Add a noun — say _what_ to continue on:
```
❌ "Get to work on some stuff"
✅ "Get to work on the CI/CD pipeline fixes"

❌ "What's the status?"
✅ "What's the status of the Playwright test failures?"
```

### 3. One task per prompt for complex work
**Problem**: Bundling unrelated tasks leads to partial completion and confusion:
- "2 things: 1. PR staging deployments 2. Microsoft OAuth login" → Two massive features in one ask
- "Get rid of beads integrations. Create onboarding docs. Summon the knights of the round table." → Three unrelated tasks

**Fix**: Use separate prompts or plan mode (`[[PLAN]]`) to sequence them:
```
❌ "Do X, Y, and Z" (where each is a multi-hour task)
✅ "[[PLAN]] I need X, Y, and Z done. Let's plan the order and tackle them one at a time."
```

### 4. Use exact skill/tool names
**Problem**: Multiple sessions wasted turns trying to invoke skills by approximate names:
- "Summon the Knights of the Round Table" → Agent couldn't find it (was named `consensus-review`)
- "You have a skill called that. Do it." → Agent listed all skills, still didn't find it

**Fix**: Use the exact skill name from `/skills`, or describe what you want done:
```
❌ "You have a skill called that. Do it. Use the skill."
✅ "Invoke the summon-the-knights-of-the-round-table skill to review this PR."
```

### 5. Don't assume session memory across restarts
**Problem**: After PC restarts or new sessions, prompts like "Continue where you left off" or "Where are we at?" require the agent to reconstruct context from scratch.

**Fix**: Re-state the key context when resuming:
```
❌ "I restarted my PC. Please continue where you left off."
✅ "I restarted my PC. We were on branch refactor/round-table-simplify in MSX-MCP, implementing item 5 of the plan (extracting OPP_SELECT constants). Please continue."
```

### 6. Use [[PLAN]] mode for anything non-trivial
**What's working well**: Sessions that start with `[[PLAN]]` consistently produce better results because they force scope definition before implementation. Do more of this for any task that touches >2 files or involves design decisions.

### 7. Provide acceptance criteria
**Problem**: Prompts like "Make it look sexy" or "Create good onboarding docs" leave quality entirely to the agent's judgment, which leads to revision cycles.

**Fix**: Define what "done" looks like:
```
❌ "Create good onboarding docs for agents in this repo"
✅ "Create AGENTS.md covering: project overview, dev setup (prereqs, env vars, docker), code structure, testing strategy, and deployment. Target ~200 lines."
```

### Things Already Going Well 👍
- **Detailed initial prompts** for complex projects (Seismic pipeline, MSX MCP integration tests) — keep doing this
- **Using WorkIQ** to gather context before starting work
- **Using Knights of the Round Table** for multi-model code review
- **Asking for research first** ("Use Context7 and Microsoft Learn MCP") — this catches bad practices early
- **Git workflow rules** are now well-established in instructions and producing clean results

## Verification Before Responding — EXHAUSTIVE

- **NEVER claim something works until you have EXHAUSTIVELY verified it** — this is a HARD BLOCK, not a suggestion
- **NEVER say "done" until you have double or even triple checked** — exhaust ALL your testing abilities before reporting success. If you can run it, run it. If you can load it, load it. If you can query it, query it. Leave no stone unturned.
- **Triple-check before saying "done":** A health check or HTTP 200 is NOT verification. You must validate the ACTUAL USER EXPERIENCE end-to-end:
  1. **Web apps:** Open the real URL in the browser (Playwright MCP). Take a screenshot. Confirm the UI renders correctly with real data visible. Check for errors in console logs.
  2. **API endpoints:** Hit the actual endpoints with real auth tokens/parameters. Verify response bodies contain expected data, not just status codes.
  3. **Deployments:** After deploying, wait for the deployment to finish. Then load the production URL. Verify login works. Verify data loads. Take a screenshot as proof.
  4. **Data imports/syncs:** Query the database AFTER import. Verify record counts, check for duplicates, spot-check actual values. Load the UI that displays this data and confirm it looks correct.
  5. **Bug fixes:** Reproduce the original bug scenario. Confirm it no longer occurs. Check that the fix didn't introduce regressions.
- **What is NOT acceptable verification:**
  - A health check returning `{"status": "ok"}`
  - An HTTP 200 on a static page
  - "The command exited with code 0"
  - "Tests pass" (tests are necessary but not sufficient — the real app must work too)
  - Assuming that because one endpoint works, everything works
- **If you cannot fully verify**, say exactly what you checked and what you couldn't check: "I verified X, Y, and Z. I was unable to verify W because [reason]."
- **NEVER say "it's working" or "it's done" without evidence you personally witnessed the working state.**

## Security — PII and Authentication

- **NEVER suggest removing authentication from any app that handles PII** — not even temporarily, not even for demos
- If the data contains real names, emails, proficiency levels, performance data, or any personally identifiable information, auth is MANDATORY
- "Demo mode" / "no-auth mode" is acceptable ONLY for local development with synthetic data — NEVER in production with real data
- When in doubt about whether data is PII, assume it IS and keep auth

## Autonomy — Check Before Asking

- **NEVER ask the user a question you could answer yourself** — read the file, run the command, check the logs, hit the endpoint. Investigate FIRST.
- If you have the tools to determine the answer, USE THEM before asking.
- Only ask the user when you genuinely cannot determine the answer through your own capabilities.
- **Example of a violation**: User says "fix the text in the PR." You ask "what specifically needs fixing?" instead of reading the PR body yourself and seeing the broken formatting. The answer was one tool call away.
- **This is not optional.** The user's time is more valuable than your tool calls. Burn tokens, not the user's patience.

## Feature Preservation — Never Remove Without Permission

- **NEVER remove features, capabilities, or functionality based on internal reasoning without asking the user first.**
- Even if the feature seems broken, redundant, deprecated, or like a "good idea" to remove — ASK FIRST.
- This applies to: code features, CLI commands, API endpoints, workflow steps, configuration options, documentation sections, dependencies, and anything else the user may rely on.
- If you think something should be removed, present the case and let the user decide.
- **Removing features silently is a trust violation.** The user must always be in control of what their project does.

## Citations

Every statistic or claim needs a clickable source URL.

- Search: `web_search`, WorkIQ, Microsoft Learn MCP
- Prefer: Microsoft docs, Gartner, Forrester, peer-reviewed studies
- Label projections/estimates clearly
- PowerPoint: use PptxGenJS `hyperlink` option
