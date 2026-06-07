# Koiomi Platform Architecture

This document describes the complete Koiomi development infrastructure: where things run, how agents work, how code flows from development to production, and how all the pieces connect.

## Overview

Koiomi is a SaaS platform for appointment booking. The development infrastructure uses an AI-powered agent pipeline where engineering agents write code, a QA agent verifies it, and code is promoted from an integration branch to production automatically.

```
┌──────────────────────────────────────────────────────────────────────┐
│                        KOIOMI INFRASTRUCTURE                        │
│                                                                      │
│  ┌─────────────┐    ┌─────────────────┐    ┌───────────────────┐    │
│  │ Teammates'  │    │  UGREEN NAS     │    │  AWS (Staging)    │    │
│  │ PCs         │◄──►│  (DXP2800)      │    │  K3s + RDS        │    │
│  │             │    │                 │    │                   │    │
│  │ - Cowork    │    │ - Paperclip     │    │ - Web app         │    │
│  │ - OpenClaw  │    │ - QA agent      │    │ - API             │    │
│  │ - Claude    │    │ - QA web stack  │    │ - PostgreSQL      │    │
│  │   Code      │    │ - Tailscale     │    │                   │    │
│  └──────┬──────┘    └────────┬────────┘    └───────────────────┘    │
│         │                    │                                       │
│         │    Tailscale VPN   │                                       │
│         └────────────────────┘                                       │
│                                                                      │
│  ┌────────────────────────────────────────────────────────┐          │
│  │ GitHub (jemisonproject org)                            │          │
│  │ Repos: web, api, paperclip, terraform, argo-cd,       │          │
│  │        quality-assurance-web                           │          │
│  └────────────────────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Paperclip (Agent Orchestration)

**What:** Self-hosted project management and AI agent orchestration platform.

**Where:** UGREEN NAS (DXP2800), running as a Docker container fronted by a Tailscale sidecar.

**URL:** `https://paperclip.tailc002ee.ts.net` (accessible only via Tailscale)

**How it works:**
- Runs the official `ghcr.io/paperclipai/paperclip:latest` Docker image
- Uses an embedded PostgreSQL database for state (persisted at `./data/paperclip`)
- The Tailscale sidecar terminates TLS and makes Paperclip reachable at its tailnet hostname
- All state lives in `/paperclip` inside the container, bind-mounted to the NAS

**Docker architecture:**
```
┌─────────────── shared network namespace ──────────────────┐
│                                                           │
│  tailscale container    ←  joins tailnet, terminates TLS  │
│  paperclip container    ←  listens on :3100 (internal)    │
│                                                           │
└───────────────────────────────────────────────────────────┘
         │ WireGuard
         ▼
  https://paperclip.tailc002ee.ts.net
```

**Config files:**
- `docker-compose.yml` — Paperclip + Tailscale stack
- `.env` — secrets (TS_AUTHKEY, BETTER_AUTH_SECRET, etc.)

### 2. Agents

There are four agents configured in Paperclip:

| Agent | Role | Where it runs | Adapter | Purpose |
|-------|------|--------------|---------|---------|
| **CEO** | `ceo` | Juan's PC | `claude_local` | Strategic decisions, workflow management, PR triage |
| **Claudio (JD)** | `general` (VP Engineering) | Juan's PC | `openclaw_gateway` | Engineering work on Koiomi repos |
| **Claudio (Brian)** | `general` (VP Engineering) | Brian's PC | `openclaw_gateway` | Engineering work on Koiomi repos |
| **QA** | `qa` | NAS (Claude Code script) | Script-based | Visual verification of changes |

#### How engineering agents connect (OpenClaw)

Engineering agents use OpenClaw — an autonomous agent runtime that connects to Paperclip:

```
Teammate's PC                           UGREEN NAS
┌──────────────────────┐          ┌─────────────────────┐
│ OpenClaw daemon      │          │ Paperclip container  │
│  - Claude Max sub    │◄─ WSS ──┤  - openclaw_gateway  │
│  - Tools (gh, etc.)  │ Tailscale│    adapter           │
│  - localhost:18789   │          │  - agent config      │
│ Tailscale Serve      │          │                     │
│ at <pc>.ts.net:443   │          │                     │
└──────────────────────┘          └─────────────────────┘
```

When Paperclip fires a heartbeat:
1. Paperclip opens a WebSocket to the agent's OpenClaw gateway via Tailscale
2. OpenClaw receives the task and runs Claude (using the teammate's Claude Max subscription)
3. Claude reads the ticket, writes code, creates PRs, posts comments
4. Results flow back to Paperclip as status updates and comments

**Key files on each teammate's PC:**
- `~/.openclaw/openclaw.json` — main config (gateway auth, model selection)
- `~/.openclaw/skills/` — agent skills (koiomi-engineering, paperclip)
- `~/.openclaw/workspace/Koiomi/` — cloned repos

**Known issues:**
- OpenClaw protocol versions must match Paperclip. If OpenClaw updates and Paperclip doesn't, you get `protocol mismatch` errors. Pin OpenClaw version to match.
- Paperclip sends a `paperclip` metadata field that OpenClaw rejects. A source patch is needed (see `OPENCLAW_SETUP.md` step 6).
- Newer Claude Code versions (2.1.160+) classify OpenClaw as a "third-party app" which requires extra usage credits. Pin Claude Code to 2.1.107 to avoid this.

#### How the QA agent works (Claude Code script)

The QA agent does NOT use OpenClaw. It uses a simple bash script that calls Claude Code directly:

```
NAS
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  scripts/qa-agent/run.sh                                │
│    │                                                    │
│    ├─ 1. Polls Paperclip API for in_review tickets      │
│    │                                                    │
│    ├─ 2. For each ticket:                               │
│    │      claude -p "browse and verify..."              │
│    │        └─ Playwright MCP (headless Chromium)        │
│    │            └─ browses http://localhost:7070          │
│    │                                                    │
│    └─ 3. Posts results back to Paperclip API             │
│         (comment + status update)                       │
│                                                         │
│  Docker: koiomi-qa stack                                │
│    qa-web  (:7070) ─► qa-api (:3000) ─► qa-db (PG)     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Why not OpenClaw for QA?**
- OpenClaw classifies as a "third-party app" in newer Claude Code versions, consuming extra usage credits ($8.63+ per session)
- Claude Code CLI (`claude -p`) is first-party and uses the Max plan's built-in allocation (no extra cost)
- The script approach is simpler, more predictable, and cheaper

**Key files:**
- `scripts/qa-agent/run.sh` — main polling script
- `scripts/qa-agent/.mcp.json` — Playwright MCP config
- `scripts/qa-agent/.env` — Paperclip API key and config
- `scripts/qa-agent/CLAUDE.md` — instructions for Claude Code

### 3. QA Test Environment (Docker)

The QA agent needs a running instance of the web app to browse. This runs on the NAS in Docker:

```
Docker: koiomi-qa stack
┌──────────────────────────────────────────────┐
│                                              │
│  qa-web (Vite dev server)                    │
│    - Built from paperclip-features branch    │
│    - Port 7070 on host, 4000 internal        │
│    - Express proxies /api/graphql to qa-api  │
│    - Reads tokens from ../web/.env           │
│                                              │
│  qa-api (NestJS, ts-node)                    │
│    - Built from paperclip-features branch    │
│    - Port 3000 internal                      │
│    - Source volume-mounted from ../api/      │
│    - Reads secrets from ../api/.env          │
│    - DB overridden to use qa-db              │
│                                              │
│  qa-db (PostgreSQL 18)                       │
│    - Isolated QA database (koiomi_qa)        │
│    - Volume: qa-pgdata                       │
│                                              │
└──────────────────────────────────────────────┘
```

**Config:** `docker-compose.qa.yml`

**Important details:**
- The API's `dev` Dockerfile stage only copies `package.json`, so source code is **volume-mounted** from `../api/`
- The web Dockerfile.dev copies and builds source at build time (no volume mount)
- `DB_SSL=false` is required — the local PostgreSQL doesn't support SSL
- The web app uses Vike for SSR on the landing page (`/`) and serves an SPA shell for all other routes (`/*`)
- GraphQL codegen must be run before building the web container: `cd ../web && pnpm run codegen`

**Rebuild process:**
```bash
cd /volume1/docker/paperclip
./scripts/qa-rebuild.sh    # pulls paperclip-features, rebuilds containers
```

### 4. GitHub Repositories

Organization: `jemisonproject`

| Repo | Purpose | Deployment |
|------|---------|------------|
| `web` | Next.js/Vike frontend (pnpm monorepo) | AWS staging via ArgoCD |
| `api` | NestJS GraphQL backend | AWS staging via ArgoCD |
| `paperclip` | Paperclip deployment, docs, skills, scripts | NAS (manual) |
| `terraform` | AWS infrastructure (VPC, K3s, RDS) | Terraform apply |
| `argo-cd` | Kubernetes manifests, Helm values | ArgoCD GitOps |
| `quality-assurance-web` | Playwright E2E test suite | Docker on NAS |

### 5. Tailscale Network

All infrastructure communicates over a private Tailscale tailnet:

| Device | Hostname | IP | Purpose |
|--------|----------|-----|---------|
| NAS (Paperclip container) | `paperclip.tailc002ee.ts.net` | `100.106.199.118` | Paperclip server |
| NAS (host) | `dxp2800.tailc002ee.ts.net` | `100.118.116.37` | OpenClaw gateway, QA agent |
| Juan's PC | `desktop-jd.tailc002ee.ts.net` | `100.106.157.27` | Engineering agent |
| Brian's PC | varies | varies | Engineering agent |

### 6. AWS Staging

- **Region:** us-east-1
- **Compute:** t4g.medium EC2 (ARM Graviton) running K3s
- **Database:** RDS PostgreSQL 18 (db.t3.micro)
- **Deployment:** ArgoCD watches the `argo-cd` repo and auto-deploys
- **Branch mapping:** `develop` → staging, `main` → production (currently disabled)

## Code Flow (Development Pipeline)

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEVELOPMENT PIPELINE                        │
│                                                                 │
│  1. ASSIGN                                                      │
│     Paperclip ticket (status: todo)                             │
│     Assigned to engineering agent                               │
│         │                                                       │
│  2. DEVELOP                                                     │
│     Engineer agent picks up ticket on heartbeat                 │
│     Creates branch from paperclip-features                      │
│     Writes code, tests, creates PR                              │
│     Self-merges PR into paperclip-features                      │
│     Sets ticket to in_review                                    │
│         │                                                       │
│  3. VERIFY                                                      │
│     QA agent picks up in_review ticket                          │
│     Rebuilds QA Docker stack from paperclip-features            │
│     Browses web app with Playwright (headless)                  │
│     Compares what it sees with ticket description               │
│         │                                                       │
│         ├─── PASS ──► Sets ticket to done                       │
│         │              Engineer merges paperclip-features → main │
│         │                                                       │
│         └─── FAIL ──► Posts comment explaining issue             │
│                       Sets ticket back to todo                  │
│                       Engineer picks it up again                │
│                                                                 │
│  4. DEPLOY                                                      │
│     Push to main triggers GitHub Actions                        │
│     Builds Docker image, pushes to GHCR                         │
│     Updates ArgoCD values                                       │
│     ArgoCD syncs to K3s cluster                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Branch Strategy

```
main                    ← production code (deployed via ArgoCD)
  ↑ merge (by engineer after QA passes)
paperclip-features      ← integration branch (agents merge PRs here)
  ↑ PR + self-merge
paperclip/KOI-XX-slug   ← feature branches (created by agents)
```

- `paperclip-features` is the integration branch where all agent work lands
- `main` only receives code that has passed QA verification
- Feature branches are deleted after merge to `paperclip-features`
- PRs always target `paperclip-features`, never `main`

### Ticket Lifecycle

```
todo            Engineer picks up, starts working
    ↓
in_progress     Engineer is coding, testing, creating PR
    ↓
in_review       Engineer self-merged PR to paperclip-features
                QA agent takes over
    ↓
done            QA passed — engineer merges to main
    or
todo            QA failed — comment explains issue, engineer fixes
```

**Rules:**
- Engineers NEVER set tickets to `done` — only QA does
- Engineers NEVER merge to `main` directly — only after QA passes
- QA NEVER modifies code — only verifies and reports
- If QA fails, it adds a comment with details and assigns back to the engineer

## Directory Layout on the NAS

```
/volume1/docker/
├── paperclip/                    ← Paperclip deployment
│   ├── docker-compose.yml        ← Paperclip + Tailscale
│   ├── docker-compose.qa.yml     ← QA test environment
│   ├── .env                      ← Paperclip secrets
│   ├── data/                     ← Persistent state
│   │   ├── paperclip/            ← Paperclip DB + state
│   │   └── tailscale-state/      ← Tailscale keys
│   ├── docs/                     ← All documentation
│   ├── scripts/
│   │   ├── qa-rebuild.sh         ← Rebuild QA Docker stack
│   │   └── qa-agent/             ← QA agent (Claude Code)
│   │       ├── run.sh            ← Polling script
│   │       ├── .mcp.json         ← Playwright MCP config
│   │       ├── .env              ← Paperclip API key
│   │       └── CLAUDE.md         ← Agent instructions
│   └── openclaw-skills/          ← OpenClaw skill definitions
│       ├── koiomi-engineering/
│       │   └── SKILL.md
│       └── koiomi-qa/
│           └── SKILL.md
├── api/                          ← API repo (paperclip-features)
│   └── .env                      ← API secrets (gitignored)
├── web/                          ← Web repo (paperclip-features)
│   └── .env                      ← Web tokens (gitignored)
└── quality-assurance-web/        ← E2E test suite
```

## Authentication and Access

### Paperclip access
- Browser: sign up at `https://paperclip.tailc002ee.ts.net`, get invited by admin
- MCP: `paperclip-mcp` Python package with session cookie auth
- API: agent API keys (created per agent in Paperclip UI)

### GitHub access
- Agents use `GH_TOKEN` (GitHub Personal Access Token with `repo` scope)
- Token created from the Koiomi org account (`koiomi.app@gmail.com`)
- Set as environment variable in agent configs

### Claude access
- Each teammate uses their own Claude Max subscription ($100/month)
- OpenClaw agents authenticate via `claude login` (OAuth)
- QA agent uses Claude Code CLI directly (first-party, no extra credits)
- **Important:** Pin Claude Code to v2.1.107 to avoid "third-party app" extra charges

### Tailscale access
- Tailnet: `tailc002ee.ts.net`
- Admin: Koiomi Google account
- Each teammate installs Tailscale and joins the tailnet

## Costs

| Item | Monthly Cost | Notes |
|------|-------------|-------|
| Claude Max (per teammate) | $100 | Covers engineering agent + QA |
| AWS staging (EC2 + RDS) | ~$30 | t4g.medium + db.t3.micro |
| Tailscale | Free | Up to 100 devices on free plan |
| GitHub | Free | Org with private repos |
| NAS electricity | ~$5 | Always on |
| Paperclip | Free | Self-hosted |

## Troubleshooting Quick Reference

| Problem | Fix |
|---------|-----|
| Paperclip unreachable | `tailscale status`, check NAS Docker is running |
| Agent 401 auth error | Re-run `claude login`, pin Claude Code to 2.1.107 |
| Protocol mismatch | Pin OpenClaw version to match Paperclip's protocol |
| QA web app blank page | Run `pnpm run codegen` in web repo, rebuild container |
| QA API SSL error | Ensure `DB_SSL=false` in environment |
| QA API no source code | Volume mount required in docker-compose.qa.yml |
| Vike route not matching | Use `/*` catch-all (not `/@catchAll*` — broke in Vike 0.4.258) |
| OpenClaw patch needed | `node ~/patch-openclaw.js` on the agent file |
| Hosts entry lost | Re-add after Paperclip container restart |
