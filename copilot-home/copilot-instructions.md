# Global Copilot Instructions

## Git Workflow

- Never work on `main`/`master` — no commits, edits, or pushes, ever. Check `git branch --show-current` first; if on a default branch, create a worktree + feature branch (`<type>/<short-desc>`) and open a PR. Work inside the worktree; follow the repo's `AGENTS.md`/`CONTRIBUTING.md`.
- Run linters and tests after each logical change, not just at push time.
- Treat an unmerged branch's commits as the final history that a GitHub rebase merge will preserve. Each surviving commit must be a finished, independently coherent narrative step.
- If a later change corrects, completes, tweaks, or reverts behavior introduced by an earlier commit in the same unmerged branch, create a temporary `git commit --fixup=<origin-sha>` commit. Do not append an ordinary `fix:`, review-fix, recovery, or follow-up commit. A standalone `fix:` commit is correct only when the defect already exists on the base branch.
- Temporary `fixup!` commits may exist locally while work is in progress, but never push them. Before every push, PR creation, or PR update: identify the actual PR base branch; autosquash any fixup commits noninteractively by setting `GIT_SEQUENCE_EDITOR=true` and running `git rebase -i --autosquash origin/<base>` (use `$env:GIT_SEQUENCE_EDITOR='true'` in PowerShell); rerun the linter, full test suite, and Edge E2E tests if present; scan for secrets and PII; inspect `git log --reverse --oneline origin/<base>..HEAD` and `git diff origin/<base>..HEAD --stat`; then get explicit user confirmation. Use `--force-with-lease` when rewriting an already-pushed branch.
- Preserve multiple coherent commits when they tell a useful story. Do not flatten an entire feature into one commit merely to imitate squash merging.
- Apply this curation automatically before every publication boundary; never wait to be asked or raise it as a separate question. Never push to a default branch, and never merge PRs - the user merges.
- Multi-account auth: if a git/gh operation fails unexpectedly, run `gh auth status`, switch with `gh auth switch --user <account>`, and on SAML/SSO failures retry over HTTPS with `git -c credential.helper="!gh auth git-credential" <command>`.

## Environment

- Docker: never stop, remove, or modify other projects' containers; on a port conflict, change the current project's ports.
- Web dev servers: track which directory serves which port; with worktrees, confirm the browser is hitting the latest server, not a stale instance.

## Long-Running Compute

Before any process expected to run >10 minutes: confirm results save incrementally (read the code; fix if not), that it can be interrupted without losing completed work, and communicate an estimated runtime (smoke-test first if unknown).

## Verification

Before reporting an action complete, confirm the observable result matches what was
asked — don't just trust that a tool returned "success." Applies to every action type:

- Code/deploy: open the URL, hit endpoints with real params, query the DB, screenshot.
  HTTP 200 or "tests pass" is not proof.
- Artifacts & UI (files, canvases, docs, slides): confirm the thing actually rendered
  the intended content at the path/panel the user sees — open it and read it back,
  verify it's not empty, stale, or written to the wrong location.
- Multi-part requests: re-read the original ask and check off each part before summarizing.

If you can't fully verify, state exactly what you checked and what you couldn't. If you
catch your own mistake, fix it before reporting — never hand back a result you know is broken.

## Security

- Never remove authentication from any app that handles PII — not even temporarily, not for demos.
- When unsure whether data is PII, assume it is.

## Autonomy

- Never ask what you could answer yourself — read the file, run the command, check the logs first.
- Never claim a project's tools or frameworks without reading its manifest (`package.json`, `pyproject.toml`, etc.).
- Burn tokens, not the user's patience.

## Citations

Every statistic or claim needs a clickable source URL (prefer Microsoft docs, Gartner, Forrester, peer-reviewed studies). Label projections clearly.
