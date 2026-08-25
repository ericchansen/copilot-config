---
name: git-commit
description: 'Create and curate conventional commits with safe staging and rebase-ready history. MUST use before creating or rewriting commits, pushing a branch, creating a PR, or updating a PR, even when the user did not explicitly ask to commit. Uses origin-targeted fixup commits for corrections to unmerged work and autosquashes them before publication. Use github-writer alongside this skill when writing PR content.'
license: MIT
allowed-tools: Bash, PowerShell
---

# Curated Git Commits

Create standardized commits whose final branch history reads as if the work was
done correctly the first time. Optimize for GitHub rebase merges: the commits in
the PR are the commits that should land on the base branch.

## Pre-Flight

1. Check repository guidelines (`CONTRIBUTING.md`, `AGENTS.md`). Repository rules override defaults below.
2. Ensure you are on a feature branch - never commit to `main`/`master`.
3. Identify the actual base branch. For an existing PR, read its base with `gh pr view --json baseRefName -q .baseRefName`; otherwise inspect `origin/HEAD` and repository guidance. Fetch `origin` before comparing history.
4. Run the repository's required safety or secret scan before committing or pushing. If the `git-safety-scan` skill is installed, use it.

## Format

```
<type>[optional scope]: <description>

[optional body — explain what and why, not how]

[optional footer(s)]
```

## Types

| Type | Purpose | Type | Purpose |
|------|---------|------|---------|
| `feat` | New feature | `test` | Add/update tests |
| `fix` | Bug fix | `build` | Build/dependencies |
| `docs` | Documentation | `ci` | CI/config changes |
| `refactor` | Refactor (no feature/fix) | `chore` | Maintenance |
| `perf` | Performance | `revert` | Revert commit |

## Rules

- Subject: target ≤50 chars, hard max 72; capitalized, imperative mood, no trailing period
- Validation: "If applied, this commit will _[subject]_"
- Body wraps at 72 chars, explains what and why
- Breaking changes: `feat!: ...` or `BREAKING CHANGE:` footer

## Workflow

### 1. Read the branch as a narrative

```bash
git fetch origin
git log --reverse --oneline origin/<base>..HEAD
git diff origin/<base>...HEAD
```

Each surviving commit must be a finished, independently coherent step. Preserve
multiple commits when they explain the change well; do not flatten the whole
feature merely to imitate squash merging.

### 2. Classify the pending change

Before choosing a commit message, determine who owns the behavior:

| Pending change | Commit action |
| --- | --- |
| Corrects, completes, tweaks, or reverts behavior introduced by a commit in this unmerged branch | Create `git commit --fixup=<origin-sha>`. |
| Fixes a defect already present on the base branch | Create a new conventional `fix:` commit. |
| Adds genuinely new logical work | Create a new conventional commit of the appropriate type. |

Use `git blame`, `git log -p`, and `git diff origin/<base>...HEAD` to find the
origin commit. Do not infer ownership from the newest commit alone.

### 3. Stage deliberately

Inspect `git diff` and stage only the paths or hunks belonging to this logical
change. Never use `git add -A` as a shortcut and never commit secrets.

For corrections to unmerged work:

```bash
git add <paths>
git diff --staged
git commit --fixup=<origin-sha>
```

`fixup!` commits are temporary local implementation artifacts. They are the
default even when the target is the tip commit. Use `git commit --amend` only
when the target is an unpublished tip commit, there are no unrelated changes,
and amending cannot obscure which earlier commit owns the correction.

For genuinely new work, generate a Conventional Commit message from the staged
diff and create one commit per coherent narrative step.

### 4. Validate the completed logical change

Run the repository's targeted tests and lint after each logical change. Before a
push or PR update, run the repository's full required validation.

## Publication Gate

Run this gate before **every** push, PR creation, or PR update. Never publish
temporary `fixup!` or `squash!` commits.

1. If `fixup!` or `squash!` commits exist, autosquash them against the actual
   base branch.

   Bash:

   ```bash
   GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash origin/<base>
   ```

   PowerShell:

   ```powershell
   $env:GIT_SEQUENCE_EDITOR = 'true'
   git rebase -i --autosquash "origin/<base>"
   Remove-Item Env:GIT_SEQUENCE_EDITOR
   ```

2. Rerun required lint, tests, build, and E2E validation after the rewrite.
3. Inspect the final narrative:

   ```bash
   git log --reverse --oneline origin/<base>..HEAD
   git log --format=%s origin/<base>..HEAD
   git diff origin/<base>..HEAD --stat
   ```

4. Stop if any `fixup!`/`squash!`, WIP, "address review", "PR fixes",
   "follow-up", "recovery", or "oops" subject remains. Also stop if a later
   commit knowingly repairs an earlier commit from this branch; create another
   targeted fixup and autosquash again.
5. Run the required secret/PII scan and show the final history and diff summary
   at the repository's confirmation boundary.
6. Push normally when history is new. If already-pushed commits were rewritten,
   use `git push --force-with-lease`, never plain `--force`.

## Safety

- Never update Git config or install hooks as part of this workflow
- Never run destructive commands without explicit request
- Never skip hooks (`--no-verify`) unless user asks
- Never force push to main/master
- Never use an ordinary `fix:` commit for a defect introduced by the same unmerged branch
