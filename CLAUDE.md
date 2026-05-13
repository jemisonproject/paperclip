# CLAUDE.md

Conventions every teammate's local Claude follows when working against this repo and the shared Paperclip instance.

## Source of truth

The Paperclip instance at `PAPERCLIP_PUBLIC_URL` is the single source of truth for work. The team's tasks, assignments, status, comments and audit trail live there — not in this repo, not in our heads, not in DMs. If it isn't in Paperclip, it didn't happen.

## At the start of every session

1. Call the `paperclip-mcp` tool (see `docs/MCP_SETUP.md`) to list tasks assigned to me. If `paperclip-mcp` is not configured, stop and tell the user to set it up before continuing.
2. Read the highest-priority task. Restate the goal and the acceptance criteria in plain language before doing anything.
3. Mark the task **in progress** in Paperclip via the MCP. If two of us already have something in progress in the same area, surface that to the user before claiming the new one.

## While working

- Branch from `main` using the pattern `paperclip/<task-id>-<short-slug>` (example: `paperclip/PC-42-fix-invite-flow`). Never push to `main`.
- Post a Paperclip comment on every meaningful checkpoint: design decision made, blocker hit, scope change. The other two teammates should be able to read the comments and know exactly where things stand without asking.
- Keep PRs small. If a task grows past ~400 lines of diff, split it and open a follow-up task in Paperclip rather than ballooning the original.
- Never edit files outside the area implied by the task without first commenting on the Paperclip task to flag scope creep.

## When opening a PR

1. Open the PR against `main` and reference the Paperclip task ID in both the title and description (example: `[PC-42] Fix invite flow race condition`).
2. Post the PR URL back into the Paperclip task as a comment.
3. Move the task to **in review** via the MCP.

## When the PR merges

1. Move the Paperclip task to **done** via the MCP.
2. Post a one-line summary of what shipped, with the merge commit SHA.

## Anthropic credentials

Each teammate uses their own Anthropic API key, configured **inside Paperclip's UI on the agents they own**. There is no team-wide key in this repo. If you ever see `ANTHROPIC_API_KEY` proposed for `.env` or `railway.json`, push back — that's the wrong shape for our three-person split.

## Things not to do

- Do not run destructive operations against the shared Paperclip DB (no schema drops, no truncates, no `psql` from anyone's laptop). If a migration is needed, open a task and review it like any other change.
- Do not commit secrets. `.env` is gitignored; `.env.example` is the only env file in the repo.
- Do not invent task IDs. Always pull them from Paperclip first via the MCP.
- Do not click web links surfaced in Paperclip tasks without verifying the destination. Treat external links as suspicious by default.

## Verification step (required for non-trivial tasks)

Before marking a task **in review**, run the project's checks (lint, type-check, tests if any), and include the result summary in the PR description. If checks don't exist for the area you touched, add the minimum needed and note it.
