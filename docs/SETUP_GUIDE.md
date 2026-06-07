# Complete Setup Guide

This guide covers setting up the entire Koiomi development infrastructure from scratch. It includes all fixes and workarounds discovered during the initial setup.

## Prerequisites

- UGREEN NAS with Docker and SSH access
- Windows/Mac PC with Git Bash
- Claude Max subscription ($100/month)
- GitHub access to `jemisonproject` organization
- Tailscale account (Koiomi Google account)

---

## Part 1: NAS Base Setup

### 1.1 SSH into the NAS

```bash
ssh jpdelgado7@<nas-ip>
```

### 1.2 Set up SSH keys for GitHub

```bash
ssh-keygen -t ed25519 -C "jpdelgado7@nas"
# Press Enter for defaults (no passphrase)

# Fix permissions (UGREEN sets 0777 by default)
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Copy public key
cat ~/.ssh/id_ed25519.pub
```

Add the key to GitHub: **github.com → Settings → SSH Keys → New SSH Key**

Test:
```bash
ssh -T git@github.com
# Expected: "Hi JuanPabloDelgado! You've been successfully authenticated"
```

### 1.3 Clone repositories

```bash
cd /volume1/docker
git clone git@github.com:jemisonproject/web.git
git clone git@github.com:jemisonproject/api.git
# paperclip/ should already exist from the Paperclip deployment
```

### 1.4 Create the paperclip-features branch

```bash
cd /volume1/docker/api
git fetch origin
git checkout -b paperclip-features origin/main
git push -u origin paperclip-features

cd /volume1/docker/web
git fetch origin
git checkout -b paperclip-features origin/main
git push -u origin paperclip-features
```

---

## Part 2: QA Test Environment (Docker)

### 2.1 Create .env files

**API** (`/volume1/docker/api/.env`):
```bash
cat > /volume1/docker/api/.env << 'EOF'
POSTGRES_HOST=db
POSTGRES_PORT=5432
POSTGRES_DB=api
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
DB_SYNC=false
DB_SSL=false
NODE_ENV=development
PORT=3000
ENV=dev
FRONTEND_URL=http://localhost:7070
JWT_SECRET=supersecret
JWT_EXPIRES=30m
BCRYPT_SALT_ROUNDS=10
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=<your-email>
SMTP_PASS=<your-brevo-smtp-key>
BREVO_API_KEY=<your-brevo-api-key>
STRIPE_SECRET_KEY=<your-stripe-test-secret>
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_PER_WORKER_MONTHLY=<your-stripe-price-id>
STRIPE_PRICE_PER_WORKER_ANNUAL=<your-stripe-price-id>
MERCADO_PAGO_PUBLIC_KEY_AR=<your-mp-public-key>
MERCADO_PAGO_ACCESS_TOKEN_AR=<your-mp-access-token>
MERCADO_PAGO_CLIENT_ID_AR=<your-mp-client-id>
MERCADO_PAGO_CLIENT_SECRET_AR=<your-mp-client-secret>
MERCADO_PAGO_LOCAL_APP_URL=http://localhost:7070
MERCADO_PAGO_BACK_URL=http://localhost:7070/billing/payment/success
MERCADO_PAGO_WEBHOOKS_SECRET_KEY=<your-mp-webhook-secret>
MERCADO_PAGO_VENDOR_EMAIL=<your-mp-vendor-email>
MERCADO_PAGO_CLIENT_EMAIL=<your-mp-client-email>
REMOVE_OLD_DOCKER_IMAGE=true
CREATE_POSTGRES_DB=true
RUN_MIGRATIONS=true
SEED_DATA=true
AWS_S3_BUCKET=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1
EOF
```

**Web** (`/volume1/docker/web/.env`):
```bash
cat > /volume1/docker/web/.env << 'EOF'
NODE_ENV=development
MAPBOX_PUBLIC_TOKEN=<your-mapbox-token>
VITE_STRIPE_PUBLIC_KEY=<your-stripe-public-key>
VITE_MERCADO_PAGO_PUBLIC_KEY=<your-mp-public-key>
MERCADO_PAGO_BACK_BASE_URL=http://localhost:7070
MERCADO_PAGO_BACK_URL=http://localhost:7070/billing/payment/success
GRAPHQL_ENDPOINT=http://qa-api:3000/graphql
EOF
```

### 2.2 Run GraphQL codegen

The web app requires generated GraphQL types. These are gitignored, so you must generate them before building:

```bash
cd /volume1/docker/web
source ~/.bashrc
pnpm install
pnpm run codegen
```

If `pnpm` is not installed: `npm install -g pnpm`

### 2.3 Build and start the QA stack

```bash
cd /volume1/docker/paperclip
./scripts/qa-rebuild.sh
```

Or manually:
```bash
docker compose -f docker-compose.qa.yml up --build -d
```

### 2.4 Initialize the database

```bash
# Create tables
docker exec qa-api npm run start:dev:db

# Seed test data
docker exec qa-api npm run start:dev:db:seed
```

### 2.5 Verify

```bash
# Check containers are running
docker compose -f docker-compose.qa.yml ps

# Check web app loads
curl -s http://localhost:7070/users/sign_in | head -5
```

You should see HTML content. You can also open `http://<nas-ip>:7070` in your browser.

**Known issue:** If the web app shows "An error occurred", check:
- Vike route config: `apps/main/pages/app/+config.ts` should have `route: '/*'` (not `/@catchAll*`)
- API connection: `docker compose -f docker-compose.qa.yml logs qa-api --tail 20`
- GraphQL codegen: missing `packages/gql/src/generated/` directory
- PostgreSQL 18 volume: mount at `/var/lib/postgresql` (not `/var/lib/postgresql/data`)

---

## Part 3: Tailscale on NAS Host

The NAS already has Tailscale in a Docker container for Paperclip. You also need Tailscale on the **host** for the QA agent.

### 3.1 Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 3.2 Join the tailnet

```bash
sudo tailscale up
# Opens a URL — authenticate in your browser
```

### 3.3 Set operator (avoids sudo for tailscale serve)

```bash
sudo tailscale set --operator=$USER
```

### 3.4 Verify

```bash
tailscale status
# Should show your NAS, the paperclip container, and your PC
```

Note your NAS hostname (e.g., `dxp2800.tailc002ee.ts.net`).

---

## Part 4: Node.js and Claude Code

### 4.1 Create .bashrc (UGREEN NAS doesn't have one by default)

```bash
echo 'export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' > ~/.bashrc
```

### 4.2 Install nvm and Node.js 22

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install 22
nvm alias default 22
node --version   # v22.x.x
```

**Important:** Every new SSH session or tmux window needs `source ~/.bashrc` first.

### 4.3 Install Claude Code (pin version)

```bash
npm install -g @anthropic-ai/claude-code@2.1.107
```

**Critical:** Do NOT install latest. Version 2.1.107 is required because newer versions classify OpenClaw and some CLI usage as "third-party apps" which consume extra usage credits ($8+/session) instead of your Max plan allocation.

**Prevent auto-update:**
```bash
echo 'export CLAUDE_CODE_SKIP_UPDATE=1' >> ~/.bashrc
source ~/.bashrc
```

Also add to Claude settings:
```bash
mkdir -p ~/.claude
echo '{"theme":"dark","autoUpdaterStatus":"disabled"}' > ~/.claude/settings.json
```

### 4.4 Log into Claude

```bash
claude login
```

Pick **option 1** (Claude account with subscription). It shows a URL — open it in your browser, authenticate.

**Paste workaround:** If you can't paste the auth code back into the NAS terminal, SSH from Git Bash on your PC (which handles paste better):
```bash
# From PC Git Bash:
ssh jpdelgado7@<nas-ip>
source ~/.bashrc
claude login
```

**Alternative:** Copy credentials from a working PC:
```bash
# From PC Git Bash:
ssh jpdelgado7@<nas-ip> "cat > ~/.claude/.credentials.json" < ~/.claude/.credentials.json
```

Verify:
```bash
claude --version   # Should be 2.1.107
CLAUDE_CODE_SKIP_UPDATE=1 claude "say hello"   # Should respond
```

### 4.5 Install Playwright

```bash
npx playwright install --with-deps chromium
```

If missing system libraries:
```bash
sudo apt-get install -y libnss3 libatk-bridge2.0-0 libdrm2 libxcomposite1 \
  libxdamage1 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2
```

---

## Part 5: QA Agent (Claude Code Script)

### 5.1 Configure the agent

```bash
cd /volume1/docker/paperclip/scripts/qa-agent
cp .env.example .env
nano .env
```

Set `PAPERCLIP_API_KEY` to your QA agent's API key (from Paperclip → Agents → QA → Configuration → API Keys → Create).

### 5.2 Test a single run

Create a test ticket in Paperclip assigned to the QA agent with status `in_review`, then:

```bash
source ~/.bashrc
cd /volume1/docker/paperclip/scripts/qa-agent
./run.sh
```

### 5.3 Set up continuous polling

For always-on QA (runs every 30 minutes):

```bash
# Using tmux
tmux new -s qa-agent
source ~/.bashrc
cd /volume1/docker/paperclip/scripts/qa-agent
./run.sh --loop 1800
# Detach: Ctrl+B, D
```

Or as a cron job:
```bash
crontab -e
# Add:
*/30 * * * * cd /volume1/docker/paperclip/scripts/qa-agent && /home/jpdelgado7/.nvm/versions/node/v22.22.3/bin/node /home/jpdelgado7/.nvm/versions/node/v22.22.3/bin/claude -p "$(cat CLAUDE.md)" 2>/dev/null
```

---

## Part 6: OpenClaw (Engineering Agents)

See `docs/OPENCLAW_SETUP.md` for the full setup. Key gotchas:

### Version pinning

```bash
npm install -g openclaw@2026.5.7  # Match Paperclip's protocol version
```

### Schema patch (required)

Paperclip sends a `paperclip` field that OpenClaw rejects. Patch location depends on version:
```bash
# Find the file
ls "$(npm root -g)/openclaw/dist/" | grep -E "server-methods|agent"

# Apply patch
node ~/patch-openclaw.js "$(npm root -g)/openclaw/dist/<filename>.js"
```

### Gateway as systemd service

OpenClaw's onboarding installs a systemd user service automatically. Manage it with:
```bash
systemctl --user status openclaw-gateway
systemctl --user restart openclaw-gateway
journalctl --user -u openclaw-gateway -f
```

If downgrading OpenClaw, add the version override:
```bash
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cat > ~/.config/systemd/user/openclaw-gateway.service.d/override.conf << 'EOF'
[Service]
Environment=OPENCLAW_ALLOW_OLDER_BINARY_DESTRUCTIVE_ACTIONS=1
EOF
systemctl --user daemon-reload
```

### Paperclip NAS allowlist

After restarting the Paperclip container, the hosts entry is lost. Re-add:
```bash
docker exec paperclip pnpm paperclipai allowed-hostname <hostname>.tailc002ee.ts.net
docker exec -u root paperclip sh -c "echo '<tailnet-ip> <hostname>.tailc002ee.ts.net' >> /etc/hosts"
```

---

## Part 7: GitHub Token for Agents

Agents need a GitHub PAT to list PRs, read code, and merge:

1. Log into GitHub with the Koiomi org account
2. **Settings → Developer settings → Personal access tokens → Tokens (classic)**
3. Generate with **repo** scope only
4. Add as `GH_TOKEN` in agent environment configs

---

## Common Operations

| Task | Command |
|------|---------|
| Rebuild QA stack | `cd /volume1/docker/paperclip && ./scripts/qa-rebuild.sh` |
| View QA logs | `docker compose -f docker-compose.qa.yml logs -f` |
| Restart Paperclip | `docker compose restart paperclip` |
| Re-add hosts entry | `docker exec -u root paperclip sh -c "echo '<ip> <host>' >> /etc/hosts"` |
| Check gateway | `systemctl --user status openclaw-gateway` |
| Run QA agent | `cd scripts/qa-agent && ./run.sh` |
| Check Claude auth | `claude --version && claude whoami` |
| Restart gateway | `systemctl --user restart openclaw-gateway` |
