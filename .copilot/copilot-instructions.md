# Global Copilot Instructions

## Quick Reference

| Rule | Details |
|------|---------|
| **Never commit broken code** | Linter + full test suite must pass first |
| **⚠️ RUN E2E TESTS LOCALLY** | **MANDATORY before ANY push** — no exceptions |
| **Never commit to main** | Always use feature branches |
| **Cite everything** | Every stat/claim needs a clickable URL |
| **Challenge assumptions** | Question approaches, push back with evidence |
| **Research first** | Use Context7 / Microsoft Learn MCP before implementing |

## Git Workflow

**Prefixes:** `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`, `perf`

### Start Work
```bash
git checkout main && git pull
git checkout -b <type>/<short-description>
```

### During Development
- Run tests after each logical change—catch failures early
- Commit frequently; one PR per logical piece of work

### Before Any Commit
1. Run linter (`ruff check .`, `npm run lint`, etc.)
2. Start test infra if needed (`docker-compose up -d`)
3. Run FULL unit test suite—all tests, not just affected
4. **⚠️ RUN E2E TESTS LOCALLY — THIS IS MANDATORY**
   - Command: `npx playwright test --project="Desktop Edge"`
   - Do NOT skip this step. Do NOT push without running E2E first.
   - E2E tests catch integration bugs that unit tests miss.
   - If E2E tests fail locally, they WILL fail in CI. Fix them first.
5. UI apps: validate with Playwright MCP browser tools (uses **Edge**, not Chrome)
6. Azure apps: deploy and validate with Playwright MCP browser tools
7. **If tests fail**: fix first, never commit broken code
8. **If tests won't run**: research (Context7, MS Learn), then ask user

### Commit & Push
```bash
git commit -m "<type>: <description>"  # Use git-commit skill
git push -u origin <branch-name>
gh pr create --title "<type>: <description>" --body "..."
```

### After PR Creation
1. Monitor CI: `gh pr checks <pr-number> --watch`
2. If tests fail: fix locally, commit, push, repeat
3. Before merge, rebase to clean history:
   ```bash
   git fetch origin main
   git rebase -i origin/main
   git push --force-with-lease
   ```
4. Do not request review from user until CI is green (or you get stuck)

### After Merge
```bash
git checkout main && git pull && git branch -d <branch>
```

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
