# Global Copilot Instructions

## Quick Reference

| Rule | Details |
|------|---------|
| **Never commit broken code** | Linter + full test suite must pass first |
| **⚠️ RUN E2E TESTS LOCALLY** | **MANDATORY before ANY push** — no exceptions |
| **Commit locally by default** | Only push when explicitly asked |
| **Cite everything** | Every stat/claim needs a clickable URL |
| **Challenge assumptions** | Question approaches, push back with evidence |
| **Research first** | Use Context7 / Microsoft Learn MCP before implementing |
| **⚠️ 32 skill limit** | Never exceed 32 skills in `~/.copilot/skills/` — Copilot CLI truncates alphabetically beyond ~32, making overflow skills invisible to the model. To add a skill, remove one first. See `$skillAllowlist` in `copilot-config/setup.ps1`. |

## Git Workflow

**Prefixes:** `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`, `perf`

### Branching
- Follow repo-specific instructions (AGENTS.md, CONTRIBUTING.md, etc.)
- If no repo guidance exists, use feature branches: `git checkout -b <type>/<short-description>`

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
- When asked to push:
  ```bash
  git push -u origin <branch-name>
  ```
- Only create a PR if the user asks for one

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

## Citations

Every statistic or claim needs a clickable source URL.

- Search: `web_search`, WorkIQ, Microsoft Learn MCP
- Prefer: Microsoft docs, Gartner, Forrester, peer-reviewed studies
- Label projections/estimates clearly
- PowerPoint: use PptxGenJS `hyperlink` option
