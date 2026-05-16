# paperclip

Shared deployment of [Paperclip](https://paperclip.ing/) — the open-source orchestration control plane for AI agents — for the Koiomi team.

Hosted on Juan's UGREEN NAS via Docker (the official `ghcr.io/paperclipai/paperclip` image), reachable to the three of us over a private [Tailscale](https://tailscale.com) network. One shared instance keeps the org chart, tasks, agents, budgets and audit log in a single source of truth so we don't conflict on the same work.

## What's in here

- `docker-compose.yml` — Paperclip + Tailscale sidecar stack. No local build — uses the official image.
- `.env.example` — environment variables for the NAS deploy.
- `CLAUDE.md` — conventions every teammate's local Claude follows.
- `docs/TEAMMATE_ONBOARDING.md` — **start here if you're a teammate joining the team.**
- `docs/NAS_DEPLOYMENT.md` — one-time NAS setup (Juan does this once).
- `docs/TAILSCALE_TEAM_SETUP.md` — what each teammate does on their own laptop.
- `docs/MCP_SETUP.md` — per-teammate `paperclip-mcp` install so local Claude talks to the NAS.
- `docs/OPENCLAW_SETUP.md` — optional Phase 2: your own autonomous agent via OpenClaw + Claude Max.
- `docs/TEAM_WORKFLOW.md` — branching, PR, and task-claim conventions.
- `docs/UPSTREAM_BUGS.md` — known Paperclip / OpenClaw bugs and the workarounds we use.
- `docs/AGENT_TUNING.md` — playbook for tuning autonomous agents (timeout, heartbeat interval, etc.).

## Quick start

**For Juan (deploy the NAS once):** see `docs/NAS_DEPLOYMENT.md`.

**For each teammate joining the team:** point them at `docs/TEAMMATE_ONBOARDING.md`. It walks them through everything in order, with a clear split between Phase 1 (Paperclip + MCP — required, 30 min) and Phase 2 (autonomous OpenClaw agent — optional, ~60 min).

## Deployed instance

| Environment | URL |
|-------------|-----|
| Tailnet     | `https://paperclip.<your-tailnet>.ts.net` _(fill in after first deploy)_ |

Reachable only to members of the Koiomi tailnet. Not on the public internet.

## Owners

- Juan Pablo Delgado
- _teammate 2_
- _teammate 3_

Maintained by the jemisonproject organization on GitHub.

## Upstream

- Paperclip source: <https://github.com/paperclipai/paperclip>
- Paperclip image: `ghcr.io/paperclipai/paperclip:latest`
- Paperclip docs: <https://docs.paperclip.ing>
