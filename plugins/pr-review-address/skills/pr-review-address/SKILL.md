---
name: pr-review-address
description: 'Review, address, and resolve PR feedback — examines all comments, review threads, and requested changes on a GitHub PR. Researches best practices, makes code fixes for valid feedback, pushes back with reasoned replies on items that are wrong or counterproductive, and resolves threads. Use when user says "address PR comments", "review the PR feedback", "fix PR review", "update PR", "handle review comments", or any variant of responding to pull request feedback.'
license: MIT
allowed-tools: Bash, PowerShell
---

# Address PR Review Feedback

Exercise engineering judgment on every comment — don't fix blindly.

## Step 1: Rebase onto Base Branch (GATE)

**Do this first — before reading feedback or making any changes.** Fixing code on a stale branch creates merge conflicts that waste time.

Check if the PR branch is behind its base (`main`/`master`). If behind, rebase now:

```bash
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
| A commit in this PR (`origin/<base>..HEAD`) | **Fix up into that commit.** |
| Already in the base branch (pre-existing bug) | New standalone commit — do not rewrite base history. |
| Genuinely new work the reviewer asked for (new test, new feature, docs) | New commit with its own message. |

### Fixing up into a PR commit

Stage the fix and attach it to the origin commit, then autosquash:

```bash
git add <paths-you-fixed>      # stage only the fix — never `git add -A`
git commit --fixup=<origin-sha>
GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash origin/<base-branch>
```

`--autosquash` reorders the fixup and marks it `fixup` automatically, so the todo list
needs no hand-editing — `GIT_SEQUENCE_EDITOR=true` accepts it unattended. Git ≥ 2.38
also accepts `--autosquash` without `-i`, but keep `-i` for compatibility with older
installs (Ubuntu 22.04 ships 2.34). In PowerShell, set the env var separately:
`$env:GIT_SEQUENCE_EDITOR = 'true'`.

Stage only the paths you actually fixed and check `git diff --staged` before
committing — `git add -A` sweeps in unrelated work and any stray secret.

If the fix belongs in the tip commit and nothing else is pending, `git commit --amend
--no-edit` is equivalent and faster.

Batch multiple `--fixup` commits and run one `rebase --autosquash` at the end rather
than rebasing after each one.

After the rebase, re-run build + tests (rewriting history can silently break a commit
that wasn't the one you edited), then:

```bash
git push --force-with-lease
```

The final PR history should read as if the reviewed defects never existed. If you end
up with a commit whose message is a variation of "address review comments", "fix
review feedback", or "PR fixes", that is a signal you skipped this step — squash it
into its origin commit.

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

Check CI status. If anything is failing, fix it before moving on. Always re-run build + tests after rebasing — even conflict-free rebases pull in base-branch changes that can break things.

## Step 7: Push and Summarize

Push, verify CI passes, then report:
- ✅ Fixed: N items | 💬 Replied: N | ❌ Pushed back: N
- 🔄 Branch updated: yes/no | 🏗️ CI: passing/failing | 🧵 Threads: all resolved
