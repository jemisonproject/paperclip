# paperclip

Shared deployment of [Paperclip](https://paperclip.ing/) — the open-source orchestration control plane for AI agents — for the Koiomi team.

Hosted on Juan's UGREEN NAS via Docker, reachable to the three of us over a private [Tailscale](https://tailscale.com) network. One shared instance keeps the org chart, tasks, agents, budgets and audit log in a single source of truth so we don't conflict on the same work.

## What's in here

- `docker-compose.yml` — Paperclip + Tailscale sidecar stack.
- `Dockerfile` and `entrypoint.sh` — single-container Paperclip build (Node 22 + embedded PostgreSQL).
- `.env.example` — environment variables for the NAS deploy.
- `CLAUDE.md` — conventions every teammate's local Claude follows.
- `docs/NAS_DEPLOYMENT.md` — one-time NAS setup (Juan does this once).
- `docs/TAILSCALE_TEAM_SETUP.md` — what each teammate does on their own laptop.
- `docs/MCP_SETUP.md` — per-teammate `paperclip-mcp` install so local Claude talks to the NAS.
- `docs/TEAM_WORKFLOW.md` — branching, PR, and task-claim conventions.

## Quick start

1. Juan: deploy on the NAS — see `docs/NAS_DEPLOYMENT.md`.
2. Each teammate: install Tailscale and accept Paperclip invite — see `docs/TAILSCALE_TEAM_SETUP.md`.
3. Each teammate: configure the local Claude MCP — see `docs/MCP_SETUP.md`.
4. Read `CLAUDE.md` and `docs/TEAM_WORKFLOW.md` before opening your first task.

## Deployed instance

| Environment | URL |
|-------------|-----|
| Tailnet     | `https://paperclip.<your-tailnet>.ts.net` _(fill in after first deploy)_ |

Reachable only to members of the Koiomi tailnet. Not on the public internet.

## Owners

- Juan Pablo Delgado
- _teammate 2_
- _teammate 3_

## Upstream

- Paperclip source: <https://github.com/paperclipai/paperclip>
- Paperclip docs: <https://docs.paperclip.ing>
