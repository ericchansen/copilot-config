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


## Git Workflow

**Prefixes:** `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`, `perf`

### Branching
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
   - Command: `npx playwright test --project="Desktop Edge"`
   - Do NOT skip this step. Do NOT push without running E2E first.
   - E2E tests catch integration bugs that unit tests miss.
   - If E2E tests fail locally, they WILL fail in CI. Fix them first.
5. **🔑 Scan staged diff for secrets — MANDATORY**
   - Check `git diff --staged` for: API keys, tokens, passwords, connection strings, private keys, `.pem`/`.pfx` files
   - Common patterns: `sk-`, `ctx7sk-`, `ghp_`, `Bearer `, `password=`, `connectionString`, `-----BEGIN`
   - If ANY secrets are found: **STOP — do not commit**
   - Alert the user with the exact file and line
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
  - CLI tests: Always use `--project="Desktop Edge"`, never "Desktop Chrome"
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

## Citations

Every statistic or claim needs a clickable source URL.

- Search: `web_search`, WorkIQ, Microsoft Learn MCP
- Prefer: Microsoft docs, Gartner, Forrester, peer-reviewed studies
- Label projections/estimates clearly
- PowerPoint: use PptxGenJS `hyperlink` option
