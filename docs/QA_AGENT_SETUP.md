# QA Agent — NAS setup

The QA agent runs on the UGREEN NAS alongside Paperclip. It picks up `in_review` tickets, rebuilds the web app from `paperclip-features`, browses it with Playwright to visually verify changes, and either merges to `main` (pass) or creates bug tickets (fail).

The QA agent is already created in Paperclip (name: **QA**, role: `qa`, icon: `bug`).

## Architecture

```
   UGREEN NAS
┌─────────────────────────────────────────────────────┐
│                                                     │
│  Tailscale (host)  ◄── Paperclip heartbeats         │
│       │                                             │
│  OpenClaw gateway (:18789)                          │
│  Claude CLI (your Claude Max subscription)          │
│  Playwright MCP (@playwright/mcp, headless)         │
│       │                                             │
│       │ browses                                     │
│       ▼                                             │
│  ┌── Docker: koiomi-qa ──────────────────────┐      │
│  │  qa-web  (web app, :7070 on host)         │      │
│  │  qa-api  (API, :3000 internal)            │      │
│  │  qa-db   (PostgreSQL)                     │      │
│  └───────────────────────────────────────────┘      │
│                                                     │
│  ┌── Docker: paperclip (existing) ───────────┐      │
│  │  tailscale sidecar                        │      │
│  │  paperclip (:3100 via tailnet)            │      │
│  └───────────────────────────────────────────┘      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

When Paperclip fires a heartbeat, it opens a WebSocket to the OpenClaw gateway on the NAS (via Tailscale). OpenClaw runs the QA task using Claude Max, browses the local QA web app with Playwright, and posts results back to Paperclip.

**Key advantage over running on your PC:** the NAS is always on, so the QA agent is always available.

## Prerequisites

- Phase 1 onboarding complete (you can access Paperclip in the browser)
- SSH access to the NAS
- Docker and Docker Compose installed on the NAS
- The `web`, `api`, and `paperclip` repos cloned side-by-side on the NAS
- A **Claude Max** subscription (autonomous agent runs burn tokens)

## Step 1 — Clone repos on the NAS

SSH into the NAS and clone the repos in a dedicated directory:

```bash
ssh nas   # or however you connect

mkdir -p ~/koiomi
cd ~/koiomi

git clone git@github.com:jemisonproject/web.git
git clone git@github.com:jemisonproject/api.git
git clone git@github.com:jemisonproject/paperclip.git

# Create paperclip-features branch in each repo (if not done already)
cd ~/koiomi/api
git fetch origin
git checkout -b paperclip-features origin/main 2>/dev/null || git checkout paperclip-features
git push -u origin paperclip-features 2>/dev/null || true

cd ~/koiomi/web
git fetch origin
git checkout -b paperclip-features origin/main 2>/dev/null || git checkout paperclip-features
git push -u origin paperclip-features 2>/dev/null || true
```

If `paperclip/` is already on the NAS from the Paperclip deployment, just make sure `api/` and `web/` are siblings.

## Step 2 — Start the QA test environment

```bash
cd ~/koiomi/paperclip

# First run: builds web + API + database from paperclip-features
./scripts/qa-rebuild.sh

# Verify everything is running
docker compose -f docker-compose.qa.yml ps

# Quick smoke test
curl -s http://localhost:7070 | head -5
```

You should see `qa-db`, `qa-api`, and `qa-web` containers running, and the web app responding on port 7070.

## Step 3 — Install Tailscale on the NAS host

The NAS already has Tailscale in a Docker container for Paperclip, but OpenClaw needs Tailscale on the **host** (it uses `tailscale serve` to expose the gateway). This adds the NAS as a second device on the tailnet.

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Join the Koiomi tailnet
tailscale up

# Verify
tailscale status
```

Note your NAS hostname (e.g., `nas-ugreen.tailc002ee.ts.net`). You'll need it for the OpenClaw setup.

## Step 4 — Install Node.js, Claude CLI, and OpenClaw

```bash
# Node.js 22 (use NodeSource or nvm)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs

# Verify
node --version   # should be 22.x

# Claude CLI
npm install -g @anthropic-ai/claude-code

# Log into Claude (opens a URL — copy it to your browser on another machine)
claude login

# Verify
claude whoami   # should show your Claude Max email

# OpenClaw
npm install -g openclaw
openclaw --version
```

## Step 5 — Install Playwright and Chromium

The QA agent uses the `@playwright/mcp` server for headless browsing.

```bash
# Install Playwright's Chromium (plus system deps)
npx playwright install --with-deps chromium
```

On some NAS Linux distributions, you may need additional libraries:

```bash
# If Chromium fails to launch, try:
sudo apt-get install -y libnss3 libatk-bridge2.0-0 libdrm2 libxcomposite1 \
  libxdamage1 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2
```

## Step 6 — Run the OpenClaw onboarding wizard

```bash
openclaw onboard
```

| Prompt | Pick |
|---|---|
| Setup path | **Quickstart** |
| Model/auth provider | **Anthropic (Claude CLI + API key)** |
| Channel | **Skip** |
| Search provider | **Skip** |
| Skills | **Yes**, accept defaults |
| Missing deps | **Skip** |
| Hooks | **Skip** |

## Step 7 — Generate a gateway auth token

```bash
openssl rand -hex 32
```

Save this to your password manager. Used as `YOUR_GATEWAY_TOKEN` below.

## Step 8 — Start the gateway

Open a dedicated terminal (or use `tmux` / `screen` so it survives SSH disconnects):

```bash
tmux new -s openclaw-gateway

openclaw gateway run \
  --bind loopback \
  --tailscale serve \
  --auth token \
  --token YOUR_GATEWAY_TOKEN \
  --port 18789 \
  --force \
  --verbose
```

Wait for:
- `[tailscale] serve enabled: https://<nas-hostname>.tailc002ee.ts.net/`
- `[gateway] ready`

Detach with `Ctrl+B, D`. Re-attach later with `tmux attach -t openclaw-gateway`.

## Step 9 — Onboard the QA agent into Paperclip

### 9a. Generate the invite prompt

In Paperclip's browser tab: **Settings → General → INVITES → Generate OpenClaw Invite Prompt**. Copy the full text block.

### 9b. Paste into OpenClaw chat

In a new terminal on the NAS:

```bash
openclaw chat
```

Paste the invite prompt. OpenClaw connects to Paperclip and registers as the QA agent.

### 9c. Approve device pairings

```bash
openclaw devices list
openclaw devices approve <request-id> --token YOUR_GATEWAY_TOKEN
# Repeat for any second pending request
```

## Step 10 — Apply the OpenClaw schema patch

Same patch as the engineering agent (see `OPENCLAW_SETUP.md` step 6):

```bash
node ~/patch-openclaw.js "$(npm root -g)/openclaw/dist/server-methods-DStUV8Sh.js"
grep -n 'KOIOMI_STRIP_PAPERCLIP' "$(npm root -g)/openclaw/dist/server-methods-DStUV8Sh.js"
```

## Step 11 — Install the QA skill

```bash
mkdir -p ~/.openclaw/skills/koiomi-qa
cp ~/koiomi/paperclip/openclaw-skills/koiomi-qa/SKILL.md \
   ~/.openclaw/skills/koiomi-qa/SKILL.md
```

## Step 12 — Configure the Playwright MCP

Edit `~/.openclaw/config.json` and add the Playwright MCP server:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless"],
      "env": {}
    }
  }
}
```

## Step 13 — NAS allowlist in Paperclip (Juan does this)

On the NAS, run these commands so Paperclip can reach the gateway:

```bash
# Get the NAS host's tailnet hostname and IP
tailscale status | grep $(hostname)

# Allowlist in Paperclip
docker exec paperclip pnpm paperclipai allowed-hostname <nas-hostname>.tailc002ee.ts.net

# Add hosts entry so Paperclip's container can resolve it
docker exec -u root paperclip sh -c \
  "echo '<nas-tailnet-ip> <nas-hostname>.tailc002ee.ts.net' >> /etc/hosts"
```

## Step 14 — Restart gateway and test

Restart the gateway (re-attach to tmux, Ctrl+C, re-run the command from Step 8).

In Paperclip's browser tab:

1. Go to **Agents → QA**
2. Click **Test** on the Adapter section — should turn green
3. Create a test ticket:
   - Title: `[QA-TEST] Verify login page loads`
   - Description: `Navigate to http://localhost:7070/login and verify the login page renders correctly. Take a screenshot and report back.`
   - Status: `in_review`
   - Assignee: QA
4. Click **▷ Run Heartbeat**

The QA agent should pick up the ticket, browse the login page, take a screenshot, and post a comment.

## How the pipeline works end-to-end

```
Engineering agent (on teammate's PC)       QA agent (on NAS)
       │                                        │
       ├─ picks up `todo` ticket                │
       ├─ writes code, creates PR               │
       ├─ self-merges to paperclip-features     │
       ├─ sets ticket → `in_review`             │
       │                                        │
       │                    ┌───────────────────┤
       │                    │ picks up `in_review` ticket
       │                    │ rebuilds QA env from latest code
       │                    │ browses app with Playwright
       │                    │ compares with ticket description
       │                    │
       │                    ├─ PASS → merges paperclip-features → main
       │                    │         sets ticket → `done`
       │                    │
       │                    └─ FAIL → creates bug ticket(s)
       │                              sets ticket → `todo`
       │                              (engineering picks those up)
       │
       ├─ picks up bug tickets...
       └─ (cycle continues)
```

## Day-to-day operation

- **Gateway must stay running.** Use `tmux` or set up a systemd service (see below).
- **QA environment must be up.** The Docker containers run with `restart: unless-stopped` so they survive NAS reboots.
- **Heartbeat schedule:** Configure on the QA agent's page → Configuration tab → Run Policy → "Heartbeat on interval". 1800 sec (30 min) is reasonable.

### Optional: systemd service for the gateway

Create `/etc/systemd/system/openclaw-gateway.service`:

```ini
[Unit]
Description=OpenClaw Gateway (QA agent)
After=network.target tailscaled.service

[Service]
Type=simple
User=your-nas-user
ExecStart=/usr/bin/openclaw gateway run --bind loopback --tailscale serve --auth token --token YOUR_GATEWAY_TOKEN --port 18789 --force
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw-gateway
sudo systemctl start openclaw-gateway
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| QA containers won't build | Check Docker is running, repos are cloned, and paperclip-features branch exists |
| Web app not responding on :7070 | `docker compose -f docker-compose.qa.yml logs qa-web` — may need time to compile |
| Playwright can't launch Chromium | Run `npx playwright install --with-deps chromium` — missing system libraries |
| Gateway won't start | Ensure Tailscale is running on the host (`tailscale status`), not just in Docker |
| Adapter test fails | Re-check device approvals (`openclaw devices list`) and NAS allowlist (Step 13) |
| Schema validation error | Re-apply the OpenClaw patch (Step 10) — may have been overwritten by npm update |
| Agent doesn't pick up tickets | Check heartbeat config in Paperclip, verify agent is assigned to the ticket |
| `qa-api` crashes on startup | Check `docker compose -f docker-compose.qa.yml logs qa-api` — may need DB migrations |
