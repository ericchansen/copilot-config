---
name: pr-review-address
description: 'Review, address, and resolve PR feedback — examines all comments, review threads, and requested changes on a GitHub PR. Researches best practices, makes code fixes for valid feedback, pushes back with reasoned replies on items that are wrong or counterproductive, and resolves threads. Use when user says "address PR comments", "review the PR feedback", "fix PR review", "update PR", "handle review comments", or any variant of responding to pull request feedback.'
license: MIT
allowed-tools: Bash
---

# Address PR Review Feedback

When the user asks to address, review, fix, or respond to PR feedback, execute this complete workflow. Do NOT just fix things blindly — exercise engineering judgment on every comment.

## Step 1: Gather All Feedback

1. **Get the PR number and repo** from context (current branch, user message, or ask).
2. **Fetch ALL review threads** using `gh api` or GitHub MCP tools:
   - Review comments (inline code comments)
   - PR-level review comments
   - General PR comments (conversation tab)
   - Requested changes from reviewers
3. **Categorize each piece of feedback:**
   - 🔴 **Bug/Security** — Must fix. Code is wrong, unsafe, or will break.
   - 🟡 **Valid improvement** — Good suggestion, should implement.
   - 🟢 **Style/preference** — Optional, but reasonable. Implement if low-cost.
   - ⚪ **Disagree** — Reviewer is wrong, suggestion would make code worse, or misunderstands intent.
   - 🔵 **Question** — Needs clarification, not a change request.

## Step 2: Research Before Acting

For each non-trivial comment:
1. **Read the surrounding code** — understand the full context, not just the diff hunk.
2. **Check best practices** — use documentation tools (Context7, Microsoft Learn, etc.) to verify claims about APIs, patterns, or conventions.
3. **Check existing tests** — will the suggested change break anything?
4. **Check the PR description** — does the comment align with the stated goals?

## Step 3: Make Code Changes

For feedback categorized as 🔴 Bug/Security or 🟡 Valid improvement:
1. Make the fix in the correct file.
2. Run the build (`tsc`, `npm run build`, etc.) to verify no regressions.
3. Run tests if they exist.
4. Stage and commit with a clear message referencing the review:
   ```
   fix: address PR review — <summary of changes>
   ```

For 🟢 Style/preference items:
- Implement if the change is small and genuinely improves readability.
- Skip if it's purely subjective and adds churn.

## Step 4: Reply to Every Comment

**Every review comment gets a reply.** Never leave feedback unacknowledged.

### For items you FIXED:
```
Fixed in <commit-sha>. <Brief explanation of what changed and why.>
```

### For items you DISAGREE with:
```
I considered this but chose not to implement it because:
<Reasoned explanation with evidence — link to docs, show code context, 
explain the tradeoff. Be respectful but direct.>
```

Do NOT blindly agree. If a reviewer suggests something that would:
- Introduce complexity without proportional benefit
- Contradict the project's established patterns
- Be based on a misunderstanding of the code's purpose
- Hurt performance, readability, or maintainability

...then push back politely with a clear explanation. Good engineering requires defending good decisions.

### For questions:
```
<Direct answer to the question, with context if needed.>
```

## Step 5: Resolve Threads

**CRITICAL: Resolve ALL threads after replying.** Every thread you reply to must be resolved — no exceptions. Unresolved threads signal incomplete work to the PR author.

After replying to a comment:
1. If you **fixed it** → resolve the thread.
2. If you **explained why it's intentional / pushed back** → resolve the thread. Your explanation IS the resolution. Don't leave it hanging — especially for automated reviewers (Copilot, bots) where there's no human to "come back and check."
3. If you **partially addressed** → reply explaining what's done and what's deferred, then resolve. The reply documents the gap.
4. If you **answered a question** → resolve the thread.

Use the GraphQL API to resolve threads:
```
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<THREAD_NODE_ID>"}) { thread { isResolved } } }'
```

To get thread node IDs:
```
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
        pageInfo { hasNextPage endCursor }
        nodes { id isResolved comments(first: 1) { nodes { body } } }
      }
    }
  }
}'
```

## Step 6: Fix CI/CD Failures

**Always check CI status on the PR.** Review comments are only half the picture — failing checks block merge.

**Also check branch mergeability / base-branch drift.** A PR with green checks can still be blocked if GitHub shows "This branch is out-of-date with the base branch" or `mergeable_state` is `behind`.

1. **Get check run status:**
   ```
   gh api repos/OWNER/REPO/commits/$(git rev-parse HEAD)/check-runs --jq '.check_runs[] | "\(.name) \(.conclusion)"'
   ```
   Or use the GitHub MCP `get_check_runs` tool on the PR.

2. **For failed checks, get the logs:**
   ```
   gh api repos/OWNER/REPO/actions/jobs/JOB_ID/logs
   ```
   Or use `get_job_logs` with `return_content: true` and `tail_lines: 100`.

3. **Common CI failures after PR review fixes:**
   - **Test timeouts** — New code paths hit external services (APIs, CLIs) that aren't mocked. Add mocks.
   - **Type errors** — Review-driven type changes break downstream tests that used the old types.
   - **Lint failures** — New code doesn't match project style rules. Run the linter locally.
   - **Build failures** — Missing imports, circular dependencies after refactoring.
   - **Version matrix failures** — Passes on one Node/Python/etc. version but fails on another. Check the matrix.

4. **Fix, test locally, push:**
   - Run the exact CI command locally (e.g., `npm run build && npm run test`).
   - Verify ALL matrix variants pass if possible (`node 20` + `node 22`, etc.).
   - Push the fix — CI will re-run automatically.

5. **If CI was already failing before your PR** (pre-existing failure):
   - Note this in a PR comment so reviewers know it's not your regression.
   - Fix it anyway if it's small — bonus points for leaving the repo better than you found it.

6. **If the PR branch is behind the base branch:**
   - Treat this as part of addressing the PR, not as a separate manual task for the user.
   - Fetch the latest base branch and update the PR branch yourself.
   - Prefer `git rebase origin/<base>` for a clean linear history unless the repo specifically prefers merge commits or the rebase is risky/conflicted.
   - Re-run the relevant validations after rebasing/merging.
   - Push the updated branch so GitHub clears the "out-of-date" state and re-runs checks if needed.

## Step 7: Push and Summarize

1. Push the fix commit(s) to the PR branch.
2. Verify CI passes after your push (check run status).
3. Provide a summary to the user:
   - ✅ Fixed: <count> items
   - 💬 Replied (no change needed): <count> items  
   - ❌ Pushed back (with explanation): <count> items
   - 🔄 Branch updated: yes / no
   - 🏗️ CI: passing / still failing (with details)
   - 🧵 Threads: all resolved / <count> unresolved (explain why)

## Anti-Patterns to Avoid

- **DO NOT** make every suggested change without thinking. Reviewers can be wrong.
- **DO NOT** reply with just "Fixed" without saying what changed.
- **DO NOT** leave comments unacknowledged — silence looks like ignoring feedback.
- **DO NOT** leave threads unresolved after replying — reply + resolve is the complete action. Even pushbacks get resolved; your explanation is the resolution.
- **DO NOT** make unrelated changes while addressing review feedback.
- **DO NOT** squash review fixes into previous commits — keep them as separate commits so the reviewer can see what changed.

## Edge Cases

- **Conflicting reviewer opinions**: Note both perspectives, pick the approach that best serves the codebase, explain your choice.
- **Outdated comments**: If the code has already changed and the comment no longer applies, reply noting it's been addressed by a different change and resolve.
- **Nitpicks on generated code**: If the comment targets auto-generated or vendored code, explain that the file is generated and shouldn't be manually modified.
