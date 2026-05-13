# Team workflow

Three people, one shared Paperclip. This is how we stay out of each other's way and keep PRs clean.

## The loop

```
Paperclip task  →  branch  →  work  →  PR  →  review  →  merge  →  task: done
```

Everything routes through Paperclip. The repo's git history mirrors the Paperclip task history one-to-one.

## Claiming a task

1. List your assigned tasks via `paperclip-mcp` (your local Claude does this automatically at session start — see `CLAUDE.md`).
2. Pick the highest priority. If two of you are about to claim something in the same area of the codebase (auth, billing, etc.), the second person waits or picks something else — Paperclip's task description should make the area obvious.
3. Mark the task **in progress** via the MCP. This is the signal to the other two that the area is taken.

## Branch naming

`paperclip/<task-id>-<short-kebab-slug>`

Examples:
- `paperclip/PC-42-fix-invite-flow`
- `paperclip/PC-77-add-budget-alerts`

One branch per task. If a task is too big for one branch, split the Paperclip task first, don't split the branch.

## PR rules

- Title: `[PC-42] Fix invite flow race condition`
- Description must include:
  - Link to the Paperclip task
  - One-line summary of the change
  - How you verified it (commands run, manual test steps)
  - Any follow-up Paperclip tasks you opened during the work
- Aim for **under 400 lines of diff**. Past that, split.
- Self-review the diff before requesting review; ask Claude to read the diff with you.
- At least one other teammate approves before merge. Paperclip task moves to **in review** when the PR opens, **done** when the PR merges.

## Avoiding conflicts

The single biggest source of PR conflicts is two people editing the same files in parallel. Three concrete defenses:

1. **Task-level ownership.** Paperclip tasks should describe the *area* clearly enough that two of you don't claim overlapping ones. If you're in doubt, comment on the task and ask before claiming.
2. **Short-lived branches.** Merge within a day or two. The longer a branch lives, the more it diverges from `main`. Rebase onto `main` daily.
3. **Per-file etiquette.** If you have to touch a file that's clearly someone else's current area (e.g. they have an open PR touching it), post a comment on their Paperclip task before you start. Two minutes of coordination saves an hour of conflict resolution.

## Merging

- Squash-merge by default. The commit message on `main` should be `[PC-42] Fix invite flow race condition` so `git log` reads like a Paperclip timeline.
- Delete the branch after merging.
- The author moves the task to **done** in Paperclip with a one-line summary and the merge SHA.

## When something is broken in production

1. Open a Paperclip task with `priority: P0` and assign it to whoever is online.
2. Branch normally (`paperclip/PC-XX-hotfix-...`), but skip the "wait for review" step — get a second pair of eyes on the diff in a quick call, merge, then write up what happened in the task comments.
3. Open a follow-up task for the post-mortem.

## Agent budgets

Paperclip enforces monthly budgets per agent. Two practical implications:

- Don't run long, expensive multi-agent jobs from your own account if you're close to your subscription quota — Anthropic usage is billed against the key on the agent, which is yours.
- If an agent halts because it hit its Paperclip budget, that's the system working as designed. Either raise the budget in Paperclip with explicit team agreement, or scope the work down.

## Onboarding a new teammate

1. Admin invites them in Paperclip's UI (via the deployed instance).
2. They follow `docs/MCP_SETUP.md` on their own laptop.
3. They read this file and `CLAUDE.md`.
4. First task should be deliberately tiny (typo fix, doc tweak) to shake out the toolchain end-to-end.
