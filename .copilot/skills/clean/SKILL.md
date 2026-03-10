---
name: clean
description: 'Post-merge git cleanup — checkout main/master, pull latest, delete merged local and remote branches, verify clean working state. Use when user says "clean up", "rebased and merged", "merged, clean up", "cleanup branches", "back to main", or any variant of post-merge housekeeping.'
license: MIT
allowed-tools: Bash
---

# Post-Merge Git Cleanup

When the user signals a merge is complete and wants cleanup, execute this workflow. Be concise — report what you did, not what you're about to do.

## Workflow

### 1. Identify current state

```bash
git branch --show-current
git status --short
```

Note the current branch name — if it's not main/master, this is the branch that was just merged.

### 2. Stash or warn about uncommitted changes

If `git status --short` shows uncommitted changes:
- **If on a feature branch that was merged:** warn the user that there are uncommitted changes on the merged branch and ask if they want to discard them before switching.
- **If changes are trivial (untracked files only):** proceed.

### 3. Switch to the default branch

Detect the default branch name:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

If that fails, try `main` then `master`. Checkout and pull:

```bash
git checkout <default-branch>
git pull --ff-only
```

If `--ff-only` fails, use `git pull --rebase` and report it.

### 4. Delete merged branches

Delete local branches that have been merged into the default branch:

```bash
git branch --merged | grep -v '^\*\|main\|master\|develop' | xargs -r git branch -d
```

On Windows (PowerShell), use:

```powershell
git branch --merged | Where-Object { $_ -notmatch '^\*|main|master|develop' } | ForEach-Object { git branch -d $_.Trim() }
```

### 5. Prune remote tracking branches

```bash
git fetch --prune
```

### 6. Report results

Print a brief summary:

```
✅ Cleaned up
  Branch: main @ <short-sha>
  Deleted: feat/my-branch, fix/other-branch (or "none")
  Working tree: clean (or list remaining untracked files)
```

Keep the output tight — this is a routine operation.

### 7. Suggest next steps

After cleanup, briefly surface what's actionable. Check these sources (in parallel when possible):

1. **Open PRs**: `gh pr list --state open --limit 5` — mention any awaiting review/merge
2. **Open issues**: `gh issue list --state open --limit 5` — mention unaddressed issues
3. **Changesets bot PR**: if `changeset-release/main` branch exists, note a release is pending
4. **Session plan**: if `plan.md` exists in the session workspace, check for incomplete tasks
5. **Session todos**: query the SQL `todos` table for pending/in-progress items

Synthesize into 2–4 bullet points under a `📋 Next steps:` heading. Use your judgement — only surface items that are genuinely actionable right now. Skip anything already done or blocked on external factors. Example:

```
📋 Next steps:
  • Merge Changesets release PR #36 to publish @wingmanjs/core@0.2.2
  • Issue #42 (add retry logic) is unassigned — pick it up?
  • 2 pending todos in session plan: "write integration tests", "update changelog"
```

If everything is clean and there's nothing pending, just say "Nothing pending — you're all caught up." Don't invent busywork.
