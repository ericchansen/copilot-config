---
name: land-this-plane
description: Wrap-up workflow for ending coding sessions cleanly. Use when asked to "land this plane", "land the plane", "wrap up", "finish up session", or "let's land it". Ensures everything is committed, pushed, and documented.
---

# Land This Plane

A wrap-up workflow skill for ending coding sessions cleanly. Use this when you're ready to wrap up work and ensure everything is committed, pushed, and documented.

**Trigger phrases:** "land this plane", "land the plane", "wrap up", "finish up session", "let's land it"

## Mandatory Workflow

When invoked, you MUST complete ALL steps below. The plane is NOT landed until `git push` succeeds.

### 1. File Issues for Remaining Work
Create GitHub issues for any follow-up work identified during the session:
```bash
gh issue create --title "Follow-up task description" --label "task"
gh issue create --title "Bug discovered during work" --label "bug"
```

### 2. Run Quality Gates (if code changes were made)
```bash
# Run linters (adapt to project - examples below)
# Go: golangci-lint run ./... or make lint
# Node: npm run lint
# Python: ruff check . or pylint

# Run tests (adapt to project)
# Go: go test ./... or make test  
# Node: npm test
# Python: pytest
```
- If quality gates fail, file high-priority issues:
  ```bash
  gh issue create --title "Fix failing tests: [description]" --label "bug,priority:high"
  ```

### 3. PUSH AND CREATE PR - NON-NEGOTIABLE

**For commit messages, invoke the `git-commit` skill.**
```bash
# Push branch to remote
git push -u origin $(git branch --show-current)

# Create Pull Request
gh pr create --title "<type>: <description>" --body "Description of changes"

# MANDATORY: Verify PR was created
gh pr view --web  # Opens PR in browser for review
```

**CRITICAL RULES:**
- The plane has NOT landed until `git push` completes successfully
- NEVER stop before `git push` - that leaves work stranded locally
- NEVER say "ready to push when you are!" - YOU must push, not the user
- If `git push` fails, resolve the issue and retry until it succeeds

### 4. Handle Uncommitted Changes - MANDATORY
Before cleanup, `git status` must show a clean working tree. If there are uncommitted changes:

1. **Staged/unstaged changes from current work:** Commit them on the current branch
2. **Changes from previous sessions:** Either:
   - Create a `wip/<description>` branch, commit, and push
   - Or discard if trivial: `git checkout -- <file>`
3. **Untracked files:**
   - Screenshots/temp files: Delete them
   - Code files: Commit or add to `.gitignore`

**NEVER stash** - stashes are invisible and forgotten. Either commit on a discoverable branch or discard.

### 5. Clean Up Git State
```bash
git stash clear                    # Remove old stashes (legacy cleanup)
git remote prune origin            # Clean up deleted remote branches
```

### 6. Verify Clean State
- Run `git status` - **MUST** show clean working tree, up to date with remote
- No untracked files that should be committed
- If not clean, go back to step 4

### 7. Provide Session Summary

Report to the user:
- **Completed:** What was accomplished this session
- **Filed:** Issues created for follow-up work
- **Quality Gates:** Status (all passing / issues filed for failures)
- **Push Status:** Confirmation that ALL changes have been pushed

## Example Session Summary Format

```
## Session Complete ✓

**Completed:**
- Implemented user authentication endpoint
- Added unit tests for auth service

**Follow-up Issues Filed:**
- #42: Add integration tests for auth flow
- #43: Update API documentation

**Quality Gates:** All passing ✓

**Git Status:** All changes pushed to origin/feat/user-auth ✓
```

## Remember

- Landing means EVERYTHING is pushed to remote. No exceptions.
- The user may be coordinating multiple agents - unpushed work breaks coordination.
- Leave the codebase in a state where anyone can pick up where you left off.
- Use the `git-commit` skill when crafting commit messages.
