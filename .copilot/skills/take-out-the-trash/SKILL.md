---
name: take-out-the-trash
description: Clean up unused git branches, merged/closed pull requests, and stale stashes. Use when asked to "clean up", "take out the trash", "prune branches", "delete merged branches", or "remove stale PRs".
---

# Take Out the Trash

Clean up unused git resources to keep repositories tidy.

## What This Skill Cleans

1. **Local branches** - Branches that have been merged or whose PRs are closed/merged
2. **Remote tracking branches** - Prune stale remote references
3. **Pull requests** - Delete branches for merged/closed PRs (remote)
4. **Git stashes** - Review and optionally clear stale stashes

## Workflow

### 1. Analyze Current State

```bash
# List all branches
git --no-pager branch -a

# List stashes
git --no-pager stash list

# List PRs with their states
gh pr list --state all --limit 50 --json number,title,state,headRefName
```

### 2. Identify Cleanup Candidates

**Branches safe to delete:**
- Local branches whose PRs are MERGED or CLOSED
- Remote branches for MERGED/CLOSED PRs (except `main`/`master`)
- Branches that have been fully merged into main/master

**Never delete:**
- `main`, `master`, `develop` branches
- Branches with OPEN PRs
- The currently checked out branch

### 3. Clean Up Process

```bash
# First, switch to main/master
git checkout main && git pull

# Prune remote tracking branches
git fetch --prune

# Delete local branches that are merged
git branch --merged | grep -v "main\|master\|develop" | xargs -r git branch -d

# For branches with closed PRs (not merged), use -D
git branch -D <branch-name>

# Delete remote branches for closed PRs
git push origin --delete <branch-name>
```

### 4. Stash Cleanup

```bash
# List stashes with details
git stash list

# Show stash contents before dropping
git stash show -p stash@{0}

# Drop specific stash
git stash drop stash@{0}

# Clear all stashes (use with caution)
git stash clear
```

## Safety Rules

1. **Always ask before deleting** - Show the user what will be deleted and get confirmation
2. **Never force-delete branches with unmerged work** unless explicitly confirmed
3. **Check stash contents** before dropping - they may contain important WIP
4. **Keep open PR branches** - Only clean up merged/closed PRs
5. **Prune remotes first** - Run `git fetch --prune` before local cleanup

## Example Cleanup Session

```bash
# 1. Update and prune
git checkout main && git pull && git fetch --prune

# 2. Show candidates
echo "=== Local branches ===" && git --no-pager branch
echo "=== Merged branches ===" && git branch --merged | grep -v "main\|master"
echo "=== Stashes ===" && git stash list
echo "=== Closed/Merged PRs ===" && gh pr list --state closed --json number,headRefName,state

# 3. After user confirms, delete
git branch -d <merged-branch>
git push origin --delete <closed-pr-branch>
git stash drop stash@{N}
```

## Quick Commands

| Task | Command |
|------|---------|
| Delete merged local branches | `git branch --merged \| grep -v "main\|master" \| xargs git branch -d` |
| Prune remote tracking | `git fetch --prune` |
| Delete remote branch | `git push origin --delete <branch>` |
| Drop stash | `git stash drop stash@{N}` |
| List closed PRs | `gh pr list --state closed --json number,headRefName` |
