---
name: pr-review-address
description: 'Review, address, and resolve PR feedback across comments, review threads, and requested changes. Uses origin-targeted fixup commits for PR-introduced defects and autosquashes before every push or PR update. Researches valid feedback, pushes back on incorrect advice, replies to every thread, and resolves it. Use for "address PR comments", "review PR feedback", "fix PR review", "update PR", "handle review comments", or equivalent requests.'
license: MIT
allowed-tools: Bash, PowerShell
---

# Address PR Review Feedback

Exercise engineering judgment on every comment — don't fix blindly.

## Step 1: Rebase onto Base Branch (GATE)

**Do this first — before reading feedback or making any changes.** Fixing code on a stale branch creates merge conflicts that waste time.

Read the PR's actual base branch, including for stacked PRs, then check whether
the branch is behind it. If behind, rebase now:

```bash
gh pr view --json baseRefName -q .baseRefName
git fetch origin
git rebase origin/<base-branch>
```

If there are conflicts, resolve them, run build + tests to verify nothing broke, then force-push:

```bash
git push --force-with-lease
```

Do NOT proceed to Step 2 until the branch is current with the base branch.

## Step 2: Gather and Categorize Feedback

Fetch all review threads and PR comments. Categorize each:
- 🔴 **Bug/Security** — must fix
- 🟡 **Valid improvement** — should implement
- 🟢 **Style/preference** — implement if low-cost
- ⚪ **Disagree** — push back with explanation
- 🔵 **Question** — answer directly

For non-trivial comments, read the surrounding code and check best practices before acting.

## Step 3: Make Changes

For 🔴 and 🟡 items: fix, run build + tests.

### Where the fix goes (decide this before committing)

**A trailing "fix review feedback" commit is the wrong default.** If the problem was
introduced by this PR, the fix belongs in the commit that introduced it — the reviewer
found a defect in work that isn't in the base branch yet, so there is no reason to
preserve the broken intermediate state.

For each fix, find the origin commit:

```bash
git blame -L <start>,<end> -- <file>          # who last touched these lines
git log --oneline origin/<base-branch>..HEAD  # commits belonging to this PR
```

Then choose:

| Origin commit is… | Action |
| --- | --- |
| A commit in this PR (`origin/<base>..HEAD`) | **Create a temporary `fixup!` commit targeting it.** |
| Already in the base branch (pre-existing bug) | New standalone `fix:` commit - do not rewrite base history. |
| Genuinely new work the reviewer asked for (new test, new feature, docs) | New commit with its own message. |

### Create a temporary fixup commit

Stage the fix and attach it to the origin commit:

```bash
git add <paths-you-fixed>      # stage only the fix — never `git add -A`
git commit --fixup=<origin-sha>
```

Stage only the paths you actually fixed and check `git diff --staged` before
committing — `git add -A` sweeps in unrelated work and any stray secret.

Batch multiple `--fixup` commits and run one `rebase --autosquash` at the end rather
than rebasing after each one. They may exist locally while feedback is being addressed,
but **never push them**. Before every push or PR update, autosquash all fixups against
the actual base branch.

Bash:

```bash
GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash origin/<base-branch>
```

PowerShell:

```powershell
$env:GIT_SEQUENCE_EDITOR = 'true'
git rebase -i --autosquash "origin/<base-branch>"
Remove-Item Env:GIT_SEQUENCE_EDITOR
```

`--autosquash` reorders each fixup beside its target and marks it `fixup`
automatically, so the todo list needs no hand-editing.

After the rebase, re-run build + tests; rewriting history can silently break a
commit that was not the one you edited.

The final PR history should read as if the reviewed defects never existed. Before
publishing, inspect `git log --reverse --oneline origin/<base-branch>..HEAD` and stop
if any `fixup!`, `squash!`, "address review comments", "fix review feedback", or
"PR fixes" subject remains. Create another targeted fixup and autosquash it into
the origin commit.

Once the final history and validation are clean:

```bash
git push --force-with-lease
```

Note: fixing up changes the SHA of the origin commit. Capture the **post-rebase** SHA
for the reply in Step 4 (`git log --oneline`), not the SHA of the fixup commit.

## Step 4: Reply to Every Thread

**Every piece of feedback gets a reply.** Use `addPullRequestReviewThreadReply` for review threads (NOT `gh pr comment`, which adds a general conversation comment):

```powershell
gh api graphql `
  -f query='mutation($threadId: ID!, $body: String!) {
    addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
      comment { id }
    }
  }' `
  -f threadId='PRRT_xxxxx' `
  -f body='Fixed in abc1234. Used generic error message instead of leaking internals.'
```

**Always use single-quoted strings** for `-f body=`. For bodies with single quotes, use the `create` tool to write a temp file, then `$replyBody = Get-Content "$env:TEMP\reply.md" -Raw`.

### Reply format — short and direct:
- **Fixed**: `Fixed in <sha>. <One sentence.>`
- **Disagree**: `<Why, with evidence. Be respectful but direct.>`
- **Question**: `<Direct answer in 1-2 sentences.>`
- **Deferred**: `Good catch. <Why out of scope>. Tracked in #<issue>.`

## Step 5: Resolve Every Thread

After replying to each thread, immediately resolve it:

```powershell
gh api graphql `
  -f query='mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
  }' `
  -f threadId='PRRT_xxxxx'
```

Pushbacks get resolved too — your explanation IS the resolution.

### Fetching threads

```
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") {
  pullRequest(number: NUM) { reviewThreads(first: 100) {
    pageInfo { hasNextPage endCursor }
    nodes { id isResolved comments(first: 1) { nodes { body path line } } }
  } } } }'
```

Paginate with `after: "CURSOR"` if `hasNextPage` is true.

## Step 6: Verify CI

Check CI status. If anything is failing, fix it before moving on. If the failure
was introduced by a commit in this PR, use another origin-targeted `fixup!` commit
and autosquash before pushing. Always re-run build + tests after rebasing - even
conflict-free rebases pull in base-branch changes that can break things.

## Step 7: Push and Summarize

Confirm autosquash left no temporary `fixup!` or `squash!` commits, push, verify
CI passes, then report:
- ✅ Fixed: N items | 💬 Replied: N | ❌ Pushed back: N
- 🔄 Branch updated: yes/no | 🏗️ CI: passing/failing | 🧵 Threads: all resolved
