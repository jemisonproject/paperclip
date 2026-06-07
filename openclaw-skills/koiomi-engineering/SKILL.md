---
name: koiomi-engineering
description: >
  How to execute engineering work for the Koiomi company: where repos live,
  branch naming, commit and PR conventions, when to escalate vs when to
  proceed autonomously. Use this whenever a Paperclip issue assigned to you
  asks for code changes, fixes, features, or refactors in any Koiomi
  repository.
---

# Koiomi engineering workflow

## Where the code lives

All Koiomi repos are pre-cloned under `~/.openclaw/workspace/Koiomi/`:

- `api/` — service-oriented appointments backend
- `web/` — appointments web app (frontend)
- `quality-assurance-web/` — QA frontend
- `terraform/` — infrastructure as code
- `paperclip/` — this Paperclip deployment + team docs
- (do not touch `argo-cd/` unless an issue explicitly mentions it — that's prod GitOps config)

Each is a clean clone of `jemisonproject/<repo>`. `origin` is configured. Push access works via the `gh` CLI auth on this machine.

## Picking the right repo from an issue

Every actionable engineering issue **must** include a line starting with `Repo:` naming the target repository. Examples:

- `Repo: api`
- `Repo: web`
- `Repo: paperclip`

If the issue body has no `Repo:` line:

1. **Do not guess.** Wrong repo = wrong work = wasted PR.
2. Post a comment asking which repo this belongs to.
3. Set the issue status to `blocked`.
4. Exit the heartbeat.

If multiple repos are involved (for example an API change that needs a matching web change), split into multiple issues with `parentId` linking them. See the Paperclip skill's "Delegate if needed" guidance.

## Standard workflow per issue

Once you've checked out an issue and confirmed the repo, do the following inside that repo's directory:

```bash
cd ~/.openclaw/workspace/Koiomi/<repo>

# Sync with the integration branch (paperclip-features)
git fetch origin paperclip-features
git checkout paperclip-features
git pull --ff-only

# Branch - use the actual Paperclip issue identifier
git checkout -b paperclip/<ISSUE-KEY>-<short-slug>
# e.g. paperclip/KOI-42-fix-onboarding-validation
```

Branch slug rules: lowercase, hyphen-separated, derived from the issue title, max about 5 words.

## Making the change

1. Read the existing code in the area you'll be touching. Do not bulk-rewrite. Small, targeted diffs only.
2. Match the project's existing patterns (naming, structure, imports, error handling). Look at neighboring files for style.
3. Write tests if the project has a test setup. If you add behavior, add a test for it. If you fix a bug, add a regression test.
4. Run the project's checks before committing:
   - `npm run lint` or `pnpm run lint`
   - `npm run typecheck` or `pnpm run typecheck`
   - `npm test` or `pnpm test`
   - Whatever build script exists
5. If a check fails, fix the underlying issue. Never commit broken code, even if the failing check seems unrelated. It probably isn't.

## Commit

One commit per logical change. Squash cleanup commits before pushing if needed.

Format:

```
[KOI-42] Fix onboarding validation rule

<optional 1-2 sentence body explaining why, not what>

Co-Authored-By: Paperclip <noreply@paperclip.ing>
```

The `Co-Authored-By` line is required per the Paperclip skill. Do not omit it.

## Push and open the PR

```bash
git push -u origin <branch-name>

gh pr create \
  --base paperclip-features \
  --title "[KOI-42] Fix onboarding validation rule" \
  --body "Closes KOI-42

## What changed
- Fixed X
- Added test for Y

## How to verify
- Run \`npm test\` - Z passes.
- Manual: do A, expect B."
```

The PR body should make it easy for a reviewer to verify in under 2 minutes. Always include `Closes KOI-XX` so merging the PR auto-closes the Paperclip issue.

## Self-merge into paperclip-features

PRs targeting `paperclip-features` are **auto-merged by you** — no human review is needed for this integration branch. After creating the PR:

```bash
# Merge the PR yourself (squash merge to keep history clean)
gh pr merge <PR-NUMBER> --squash --delete-branch
```

**Important:** This only applies to PRs targeting `paperclip-features`. Never merge PRs targeting `main` — those always require human review.

## Communicate back to Paperclip

After the PR is merged into `paperclip-features`, post a comment on the Paperclip issue with the PR URL and update status to `in_review`:

- Use the Paperclip-skill API patterns (see that skill).
- The comment must include the full `https://github.com/jemisonproject/<repo>/pull/<n>` URL.
- Status must move to `in_review`, not `done`. The QA agent will pick it up and verify the changes.

Then exit the heartbeat.

## When QA passes (ticket reaches `done`)

When the QA agent sets a ticket to `done`, it means the changes in `paperclip-features` are verified. Your job is to **promote the code to `main`**:

```bash
cd ~/.openclaw/workspace/Koiomi/<repo>
git fetch origin
git checkout main
git pull origin main
git merge origin/paperclip-features --no-edit
git push origin main
```

Do this for each repo the ticket touched (check the PR URL in the comments to know which repo). After merging, post a comment on the ticket confirming the merge to main.

## When QA fails (ticket goes back to `todo`)

If the QA agent finds issues, it will:
1. Post a comment explaining what's wrong
2. Set the ticket back to `todo`
3. Assign it back to you

When you pick it up again, read the QA comment carefully, fix the issues, and follow the standard workflow (branch from `paperclip-features`, PR, self-merge, set to `in_review`).

## Ticket lifecycle (your role)

```
todo          → you pick it up, start working
in_progress   → you're coding, testing, creating PR
in_review     → you set this AFTER self-merging PR to paperclip-features
                (QA agent takes over from here)
done          → QA passed — you merge paperclip-features into main
```

**You never set a ticket to `done`.** Only the QA agent does that after verification.

## When you can't proceed

Hit any of these → post a comment with details, set status to `blocked`, exit:

- Permission error on `git push` (token expired, lost repo access, etc.).
- Failing tests you've genuinely tried to fix but can't.
- The issue is ambiguous and you've already asked a clarifying question. Don't re-ask, wait.
- The change requires schema migrations, secrets rotation, or anything that needs explicit human approval. Use Paperclip's `request_board_approval` for those.
- The repo is in a broken state you didn't cause (existing main fails to build).

## Hard rules - never do these

- Never force-push. No `git push --force`, no `git push --force-with-lease`. If history needs rewriting, ask first.
- Never merge PRs targeting `main`. PRs always target `paperclip-features`. Merging `paperclip-features` into `main` happens only after QA passes (ticket status is `done`).
- Never set a ticket to `done`. Only the QA agent does that after verification. You set tickets to `in_review` after self-merging your PR.
- Never delete branches. Humans clean up post-merge.
- Never touch repos outside the `Repo:` line. If you think two repos need changes, open a sibling issue for the second one.
- Never commit secrets, .env files, API keys, tokens, private keys, or anything matching `.gitignore`. Double-check `git diff --staged` before committing.
- Never run destructive ops (DROP TABLE, rm -rf, dropping migrations, deleting customer data) without first opening a Paperclip approval request via `request_board_approval` and waiting for explicit human approval.
- Never modify `argo-cd/` repo without an explicit human-confirmed approval. That's our prod GitOps config; bad commits there break production.

## Examples of well-formed issues

Good:

> **Title:** Fix off-by-one in pagination
>
> **Body:**
> Repo: api
>
> The `/v1/appointments` endpoint returns one fewer result than `limit` on the last page. See `src/routes/appointments.ts:88`. Should return up to `limit` items per page including the final page.

Good (with acceptance criteria):

> **Title:** Add CSV export button to dashboard
>
> **Body:**
> Repo: web
>
> ## Acceptance criteria
> - New button on the dashboard top-right labeled "Export CSV"
> - Clicking it downloads `dashboard-YYYY-MM-DD.csv` with the currently filtered rows
> - Works in Chrome, Firefox, Safari
> - Add a Playwright test in `tests/dashboard.spec.ts`

Bad (don't try to work on these - comment back asking for clarification):

> **Title:** Fix the appointment thing
>
> **Body:**
> It's broken.

If you get one like the bad example, your job is to ask the right clarifying questions and wait, not to guess.
