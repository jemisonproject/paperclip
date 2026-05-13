# QA Agent on NAS — Detailed Setup Guide

This is a step-by-step guide with every command, expected output, and what to do if something goes wrong. Follow each step in order.

You'll need two windows open: an SSH terminal to your NAS, and a browser on your PC.

---

## PHASE A: Get the code on the NAS

### A1. SSH into the NAS

On your PC, open a terminal:

```bash
ssh jpdelgado7@<nas-ip>
```

Replace `<nas-ip>` with your NAS's local IP (e.g., `192.168.1.100`) or its hostname. Enter your NAS password when prompted.

**Expected:** you land in a shell on the NAS, something like:

```
jpdelgado7@UGREEN:~$
```

### A2. Check Docker is working

```bash
docker --version
docker compose version
```

**Expected:**

```
Docker version 24.x.x (or similar)
Docker Compose version v2.x.x
```

**If `docker` is not found:** Docker isn't installed or your user isn't in the docker group. Install Docker from the UGOS App Center, then add your user:

```bash
sudo usermod -aG docker jpdelgado7
# Log out and back in for the group change to take effect
exit
ssh jpdelgado7@<nas-ip>
```

### A3. Check where Paperclip lives

Your Paperclip deployment is already on the NAS. Confirm:

```bash
ls /volume1/docker/paperclip/docker-compose.yml
```

**Expected:** the file exists. If it's somewhere else, note the path — all commands below assume `/volume1/docker/` as the base.

### A4. Clone the web and api repos

The QA environment needs the `web` and `api` repos as siblings of `paperclip`:

```bash
cd /volume1/docker

# Clone the web repo
git clone git@github.com:jemisonproject/web.git

# Clone the api repo
git clone git@github.com:jemisonproject/api.git
```

**Expected:** both repos clone successfully. If you get a permission error, you may need to set up SSH keys on the NAS:

```bash
# Check if you have SSH keys
ls ~/.ssh/id_ed25519.pub

# If not, generate one:
ssh-keygen -t ed25519 -C "jpdelgado7@nas"
cat ~/.ssh/id_ed25519.pub
# Copy the output and add it to GitHub → Settings → SSH Keys
```

**If git is not installed:**

```bash
sudo apt-get update && sudo apt-get install -y git
```

(On UGOS, you may need `opkg install git` or install it via the App Center.)

### A5. Verify the directory structure

```bash
ls -la /volume1/docker/
```

**Expected:** you should see at least these three directories:

```
drwxr-xr-x  api/
drwxr-xr-x  paperclip/
drwxr-xr-x  web/
```

### A6. Create the `paperclip-features` branch in each repo

The engineering agents merge code into this branch. The QA agent tests it before promoting to `main`.

```bash
# API repo
cd /volume1/docker/api
git fetch origin
git checkout -b paperclip-features origin/main
git push -u origin paperclip-features
```

**Expected:**

```
Branch 'paperclip-features' set up to track remote branch 'paperclip-features' from 'origin'.
```

**If the branch already exists** (e.g., you created it on your PC earlier):

```bash
git fetch origin
git checkout paperclip-features
git pull origin paperclip-features
```

Now the same for the web repo:

```bash
# Web repo
cd /volume1/docker/web
git fetch origin
git checkout -b paperclip-features origin/main
git push -u origin paperclip-features
```

### A7. Verify both repos are on paperclip-features

```bash
cd /volume1/docker/api && git branch --show-current
cd /volume1/docker/web && git branch --show-current
```

**Expected:** both print `paperclip-features`.

---

## PHASE B: Start the QA test environment (Docker)

### B1. Copy the QA docker-compose and rebuild script

These files are already in the paperclip repo (we just created them):

```bash
cd /volume1/docker/paperclip

# Verify the files exist
ls docker-compose.qa.yml
ls scripts/qa-rebuild.sh

# Make the rebuild script executable
chmod +x scripts/qa-rebuild.sh
```

**Expected:** both files exist. If they don't, pull the latest paperclip repo:

```bash
git pull origin main
```

### B2. Run the QA rebuild script

This pulls the latest `paperclip-features` code and builds the Docker containers:

```bash
cd /volume1/docker/paperclip
./scripts/qa-rebuild.sh
```

**Expected output** (first run takes 5-15 minutes as it builds everything):

```
═══ Pulling latest paperclip-features ═══
── Updating api → paperclip-features
   api is at abc1234 Some commit message
── Updating web → paperclip-features
   web is at def5678 Some commit message

═══ Rebuilding QA containers ═══
[+] Building ...
[+] Running 3/3
 ✔ Container qa-db     Started
 ✔ Container qa-api    Started
 ✔ Container qa-web    Started

═══ QA environment is up ═══
Web app:  http://localhost:7070
```

**If the build fails:**

- `npm ci failed` → probably a network issue. Try again.
- `COPY failed: file not found` → the repo might not have the right structure. Check `ls /volume1/docker/api/Dockerfile` and `ls /volume1/docker/web/apps/main/Dockerfile.dev`.

### B3. Verify the containers are running

```bash
docker compose -f docker-compose.qa.yml ps
```

**Expected:**

```
NAME      IMAGE          STATUS         PORTS
qa-api    ...            Up             3000/tcp
qa-db     postgres:18    Up (healthy)   5432/tcp
qa-web    ...            Up             0.0.0.0:7070->4000/tcp
```

All three should show `Up`. If `qa-db` shows `(health: starting)`, wait 10 seconds and check again.

### B4. Wait for the web app to compile

The Vite dev server takes 30-60 seconds to compile on first start. Check its logs:

```bash
docker compose -f docker-compose.qa.yml logs qa-web --tail 20
```

**Expected** (when ready):

```
qa-web  | Starting Vite development server...
qa-web  | VITE v5.x.x ready in XXXms
qa-web  | ➜  Local:   http://localhost:4000/
```

If you see errors, wait a bit. The first compilation can take a while.

### B5. Smoke test the web app

```bash
curl -s http://localhost:7070 | head -20
```

**Expected:** HTML content (not an error page). You should see `<!DOCTYPE html>` or similar. If you get `connection refused`, the web app is still compiling — wait and try again.

You can also open `http://<nas-ip>:7070` in your PC's browser to see the app visually (replace `<nas-ip>` with your NAS's LAN IP).

---

## PHASE C: Install Tailscale on the NAS host

The NAS already has Tailscale in a Docker container for Paperclip, but OpenClaw needs Tailscale on the **host** itself (it uses `tailscale serve` to expose the gateway). This creates a second device on your tailnet.

### C1. Check if Tailscale is already on the host

```bash
tailscale version
```

**If it prints a version:** skip to C3.

**If `command not found`:** continue to C2.

### C2. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

**Expected:** installation completes with a message like:

```
Installation complete! You can now run 'tailscale up' to connect.
```

**If curl is not installed:**

```bash
sudo apt-get update && sudo apt-get install -y curl
# Then retry the Tailscale install command
```

**On UGOS specifically:** if `apt-get` isn't available, try:

```bash
# Check what package manager exists
which opkg apk apt-get yum dnf 2>/dev/null
```

Use whichever is available. If none work, you may need to download the Tailscale static binary:

```bash
curl -fsSL https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz | tar xz
sudo cp tailscale_*/tailscale /usr/local/bin/
sudo cp tailscale_*/tailscaled /usr/local/bin/

# Start the daemon
sudo tailscaled --state=/var/lib/tailscale/tailscaled.state &
```

### C3. Join the Koiomi tailnet

```bash
sudo tailscale up
```

**Expected:** it prints a URL like:

```
To authenticate, visit:
https://login.tailscale.com/a/abc123def456
```

Open that URL in your PC's browser, log in with the Koiomi Google account (`koiomi.app@gmail.com`), and approve the device.

### C4. Verify Tailscale is connected

```bash
tailscale status
```

**Expected:** you see your NAS listed, plus the `paperclip` container and your PC:

```
100.x.x.x    nas-ugreen          jpdelgado7@  linux   -
100.x.x.x    paperclip            tagged       linux   -
100.x.x.x    desktop-jd           jpdelgado7@  windows -
```

**Write down your NAS hostname** (e.g., `nas-ugreen`) — you'll need it later. The full tailnet hostname is `<nas-hostname>.tailc002ee.ts.net`.

### C5. Test tailnet connectivity

```bash
# Can the NAS host reach Paperclip via tailnet?
curl -sk https://paperclip.tailc002ee.ts.net | head -5
```

**Expected:** HTML from Paperclip (login page or similar). If you get a timeout, Tailscale might not be fully connected — run `tailscale status` again to verify.

---

## PHASE D: Install Node.js, Claude CLI, and OpenClaw

### D1. Check if Node.js is installed

```bash
node --version
```

**If it prints `v22.x.x` or higher:** skip to D3.

### D2. Install Node.js 22

```bash
# Using NodeSource (most common)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs
```

**Verify:**

```bash
node --version
npm --version
```

**Expected:**

```
v22.x.x
10.x.x
```

**If `apt-get` doesn't work on UGOS:** try installing Node via `nvm` (works on any Linux):

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# Reload shell
source ~/.bashrc   # or ~/.zshrc

nvm install 22
nvm use 22
nvm alias default 22
```

Verify with `node --version`.

### D3. Install Claude CLI

```bash
npm install -g @anthropic-ai/claude-code
```

**Expected:**

```
added X packages in Xs
```

**Verify:**

```bash
claude --version
```

Should print the Claude CLI version.

### D4. Log into Claude

```bash
claude login
```

**Expected:** it prints a URL to open in your browser:

```
Please open this URL in your browser to log in:
https://claude.ai/oauth/...
```

Open that URL on your PC, log in with your Claude Max account. The terminal on the NAS will show:

```
Successfully logged in!
```

**Verify:**

```bash
claude whoami
```

**Expected:** your email (e.g., `juandelgadocarp@gmail.com`).

### D5. Install OpenClaw

```bash
npm install -g openclaw
```

**Verify:**

```bash
openclaw --version
```

**Expected:** prints the OpenClaw version number.

**If the binary isn't found after install:**

```bash
# Find where npm installs global packages
npm root -g
# Usually something like /usr/lib/node_modules

# The binary should be at:
ls $(npm prefix -g)/bin/openclaw

# If needed, add to PATH:
export PATH="$(npm prefix -g)/bin:$PATH"
echo 'export PATH="$(npm prefix -g)/bin:$PATH"' >> ~/.bashrc
```

---

## PHASE E: Install Playwright and Chromium

### E1. Install Playwright with Chromium and system dependencies

```bash
npx playwright install --with-deps chromium
```

**Expected:** downloads Chromium and installs system libraries. Takes 2-5 minutes. Output ends with something like:

```
Chromium ... downloaded to /home/jpdelgado7/.cache/ms-playwright/chromium-xxxx
```

**If it fails with missing libraries:** install them manually:

```bash
sudo apt-get install -y \
  libnss3 libatk-bridge2.0-0 libdrm2 libxcomposite1 \
  libxdamage1 libxrandr2 libgbm1 libpango-1.0-0 \
  libcairo2 libasound2 libxshmfence1 libglu1-mesa
```

Then retry:

```bash
npx playwright install chromium
```

### E2. Verify Playwright works

```bash
npx playwright --version
```

**Expected:** prints the Playwright version.

Quick test that Chromium launches headless:

```bash
node -e "
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.goto('http://localhost:7070');
  console.log('Title:', await page.title());
  await browser.close();
  console.log('Chromium works!');
})().catch(e => { console.error(e.message); process.exit(1); });
"
```

**Expected:**

```
Title: Koiomi (or similar)
Chromium works!
```

**If it fails with "browserType.launch: ...":** Chromium can't find its dependencies. Go back to E1 and install the missing system libraries.

---

## PHASE F: Set up OpenClaw

### F1. Run the onboarding wizard

```bash
openclaw onboard
```

Follow the interactive prompts. Choose these options:

| Prompt | What to pick |
|--------|-------------|
| Setup path | **Quickstart** |
| Model/auth provider | **Anthropic (Claude CLI + API key)** — it should detect your claude login from D4 |
| Channel (Telegram/Discord/etc.) | **Skip for now** |
| Search provider | **Skip for now** |
| Configure skills | **Yes**, accept defaults |
| Install missing skill dependencies | **Skip for now** |
| Enable hooks | **Skip for now** |

**Expected:** onboarding completes with a summary showing your OpenClaw config directory (usually `~/.openclaw/`).

### F2. Generate a gateway auth token

```bash
openssl rand -hex 32
```

**Expected:** a 64-character hex string like:

```
a3f8b2c1d4e5f6789012345678901234567890abcdef1234567890abcdef1234
```

**Save this to your password manager.** You'll use it as `YOUR_GATEWAY_TOKEN` in several places. From here on, whenever you see `YOUR_GATEWAY_TOKEN`, paste this value.

### F3. Start the gateway (first run)

Use `tmux` so the gateway survives SSH disconnects:

```bash
# Install tmux if needed
sudo apt-get install -y tmux   # or: opkg install tmux

# Start a named tmux session
tmux new -s openclaw-gateway
```

You're now inside a tmux session. Run the gateway:

```bash
openclaw gateway run \
  --bind loopback \
  --tailscale serve \
  --auth token \
  --token YOUR_GATEWAY_TOKEN \
  --port 18789 \
  --force \
  --verbose
```

(Replace `YOUR_GATEWAY_TOKEN` with the actual token from F2.)

**Expected:** two key log lines:

```
[tailscale] serve enabled: https://<nas-hostname>.tailc002ee.ts.net/
[gateway] ready
```

**Write down the hostname** from that log line (e.g., `nas-ugreen.tailc002ee.ts.net`).

**Detach from tmux** (keep the gateway running in the background):

```
Press Ctrl+B, then press D
```

You're back at the normal shell. The gateway continues running in the tmux session.

**Useful tmux commands:**

```bash
tmux attach -t openclaw-gateway   # re-attach to see logs
tmux ls                           # list sessions
# Inside tmux: Ctrl+B, D to detach again
```

---

## PHASE G: Connect the QA agent to Paperclip

### G1. Allowlist the NAS hostname in Paperclip

The NAS host's Tailscale hostname needs to be allowed in Paperclip so it can connect. Run these commands on the NAS:

```bash
# Get your NAS host's tailnet IP and hostname
tailscale status | head -5
```

Note the IP (e.g., `100.106.xxx.yyy`) and hostname (e.g., `nas-ugreen`).

```bash
# Allowlist the hostname in Paperclip
docker exec paperclip pnpm paperclipai allowed-hostname <nas-hostname>.tailc002ee.ts.net

# Add hosts entry so Paperclip's container can resolve it
docker exec -u root paperclip sh -c \
  "echo '<nas-tailnet-ip> <nas-hostname>.tailc002ee.ts.net' >> /etc/hosts"
```

Replace `<nas-hostname>` and `<nas-tailnet-ip>` with your actual values.

**Example with real values:**

```bash
docker exec paperclip pnpm paperclipai allowed-hostname nas-ugreen.tailc002ee.ts.net
docker exec -u root paperclip sh -c \
  "echo '100.106.200.50 nas-ugreen.tailc002ee.ts.net' >> /etc/hosts"
```

**Expected:** no errors. If you see `command not found: pnpm`, the Paperclip container may use a different CLI — check `docker exec paperclip which pnpm npm npx`.

### G2. Generate the OpenClaw invite prompt from Paperclip

On your PC browser, go to:

```
https://paperclip.tailc002ee.ts.net
```

Log in, then navigate to:

```
Settings → General → INVITES → Generate OpenClaw Invite Prompt
```

A large block of text appears. **Copy the entire block** to your clipboard.

### G3. Paste the invite into OpenClaw chat

Back on the NAS SSH terminal, open a new OpenClaw chat:

```bash
openclaw chat
```

When the chat prompt appears, **paste the entire invite prompt** you copied from G2.

**Expected:** OpenClaw reads the prompt and starts connecting to Paperclip. You'll see narration like:

```
I'll set up the connection to Paperclip...
Joining Koiomi company...
Paperclip onboarding complete:
- Joined as QA
- Company: Koiomi
- API key claimed and saved
- Skill installed at ~/.openclaw/skills/paperclip/SKILL.md
```

This takes 30-60 seconds. Watch the gateway tmux session too — you'll see incoming WebSocket connections.

**If it hangs or fails:** check that the gateway is running (`tmux attach -t openclaw-gateway`) and that Tailscale is connected (`tailscale status`).

Exit the chat when done:

```
Type: /exit
```

### G4. Approve device pairings

Paperclip creates two device pairing requests. You need to approve both:

```bash
openclaw devices list
```

**Expected:** one or two pending requests:

```
Pending (1)
  Request ID: req_abc123...
  Note: First-time device pairing request
  ...
```

Approve each one:

```bash
openclaw devices approve req_abc123... --token YOUR_GATEWAY_TOKEN
```

(Replace `req_abc123...` with the actual Request ID shown.)

Check for a second pending request:

```bash
openclaw devices list
```

If there's another pending request, approve it too. Repeat until you see only "Paired" devices and no "Pending" section:

```
Paired (2)
  Device: dev_xxx...
  Device: dev_yyy...
```

### G5. Apply the OpenClaw schema patch

Paperclip sends a metadata field that OpenClaw rejects. This one-line patch fixes it.

**If you already have the patch script** from setting up the engineering agent:

```bash
ls ~/patch-openclaw.js
```

If the file exists, apply it:

```bash
OC="$(npm root -g)/openclaw/dist"
FILE="$OC/server-methods-DStUV8Sh.js"
node ~/patch-openclaw.js "$FILE"
```

**If you don't have the patch script yet**, create it:

```bash
cat > ~/patch-openclaw.js << 'PATCH_EOF'
const fs = require('fs');
const file = process.argv[2];
let src = fs.readFileSync(file, 'utf8');

if (src.includes('KOIOMI_STRIP_PAPERCLIP')) {
  console.log('already patched');
  process.exit(0);
}

const re = /(const p = params;\s*\n)(\s*)(if \(!validateAgentParams\(p\)\))/;
const m = src.match(re);
if (!m) {
  console.error('marker not found');
  process.exit(1);
}

const inject =
  m[1] +
  m[2] +
  '/* KOIOMI_STRIP_PAPERCLIP */ if (p && typeof p === "object") { delete p.paperclip; }\n' +
  m[2] +
  m[3];

src = src.replace(re, inject);
fs.writeFileSync(file, src);
console.log('patched ' + file);
PATCH_EOF

# Apply
OC="$(npm root -g)/openclaw/dist"
FILE="$OC/server-methods-DStUV8Sh.js"
node ~/patch-openclaw.js "$FILE"
```

**Expected:**

```
patched /usr/lib/node_modules/openclaw/dist/server-methods-DStUV8Sh.js
```

**Verify:**

```bash
grep -n 'KOIOMI_STRIP_PAPERCLIP' "$FILE"
```

Should print one line showing the patch marker.

**If you see `marker not found`:** the OpenClaw version has a different file structure. Check what files exist:

```bash
ls "$(npm root -g)/openclaw/dist/" | grep server-methods
```

The file name may differ. Use the actual filename you find.

### G6. Install the QA skill

```bash
mkdir -p ~/.openclaw/skills/koiomi-qa
cp /volume1/docker/paperclip/openclaw-skills/koiomi-qa/SKILL.md \
   ~/.openclaw/skills/koiomi-qa/SKILL.md
```

**Verify:**

```bash
cat ~/.openclaw/skills/koiomi-qa/SKILL.md | head -10
```

Should show the QA skill frontmatter with `name: koiomi-qa`.

### G7. Configure the Playwright MCP

Edit the OpenClaw config to add the Playwright MCP server:

```bash
nano ~/.openclaw/config.json
```

Find the `"mcpServers"` section and add the `"playwright"` entry. The result should look like this (you may already have other MCP servers listed):

```json
{
  "mcpServers": {
    "paperclip": {
      "...existing paperclip config..."
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless"],
      "env": {}
    }
  }
}
```

Save (`Ctrl+O` → `Enter` → `Ctrl+X`).

**Important:** make sure the JSON is valid. Common mistakes:
- Missing comma between entries in `mcpServers`
- Extra trailing comma after the last entry

**Verify the JSON is valid:**

```bash
node -e "JSON.parse(require('fs').readFileSync('$HOME/.openclaw/config.json')); console.log('Valid JSON')"
```

Should print `Valid JSON`.

### G8. Restart the gateway

The gateway needs to restart to pick up the new config and patch:

```bash
# Re-attach to the tmux session
tmux attach -t openclaw-gateway

# Stop the gateway: press Ctrl+C

# Restart it:
openclaw gateway run \
  --bind loopback \
  --tailscale serve \
  --auth token \
  --token YOUR_GATEWAY_TOKEN \
  --port 18789 \
  --force \
  --verbose

# Wait for "[gateway] ready"

# Detach: Ctrl+B, then D
```

---

## PHASE H: Test the QA agent

### H1. Test the adapter connection

On your PC browser, go to Paperclip:

```
https://paperclip.tailc002ee.ts.net
```

Navigate to **Agents → QA**. In the Adapter section, click **Test**.

**Expected:** turns green with "Gateway connect probe succeeded."

**If it fails:**
- Check the gateway is running: `tmux attach -t openclaw-gateway` on the NAS
- Check Tailscale: `tailscale status` on the NAS
- Check the NAS hostname is allowlisted (step G1)

### H2. Create a test ticket

Still in Paperclip browser, create a new issue:

- **Title:** `[QA-TEST] Verify login page loads`
- **Description:**

  ```
  Navigate to http://localhost:7070/login and verify:
  1. The login page renders correctly
  2. There's an email/username field
  3. There's a password field
  4. There's a submit/login button
  Take a screenshot and report what you see.
  ```

- **Status:** `in_review`
- **Assignee:** QA

### H3. Trigger the heartbeat

On the QA agent's page in Paperclip, click **▷ Run Heartbeat**.

### H4. Watch it work

Re-attach to the gateway tmux session to see the agent in action:

```bash
tmux attach -t openclaw-gateway
```

**Expected:** you'll see WebSocket messages and RPC calls flowing. Within 30-60 seconds, the QA agent should:

1. Read the test ticket
2. Use Playwright to navigate to `http://localhost:7070/login`
3. Take a snapshot / screenshot
4. Post a comment on the ticket
5. Update the ticket status

Check the Paperclip issue page (reload in your browser) — you should see the QA agent's comment.

### H5. Celebrate

If you see the QA agent's comment on the ticket, **the pipeline is working**. The QA agent is running on your NAS, always available, and ready to test changes automatically.

---

## PHASE I: Configure automatic heartbeats

By default, the QA agent only checks for work when you manually click "Run Heartbeat." To make it check automatically:

### I1. Set up heartbeat interval

In Paperclip browser, go to **Agents → QA → Configuration tab → Run Policy**.

Set **Heartbeat on interval** to `1800` (every 30 minutes).

This means every 30 minutes, Paperclip sends a heartbeat to the QA agent. If there are `in_review` tickets assigned to it, it picks them up.

### I2. (Optional) Set up the gateway as a systemd service

Instead of using tmux, you can run the gateway as a proper system service:

```bash
sudo nano /etc/systemd/system/openclaw-gateway.service
```

Paste:

```ini
[Unit]
Description=OpenClaw Gateway (QA agent)
After=network.target

[Service]
Type=simple
User=jpdelgado7
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/openclaw gateway run --bind loopback --tailscale serve --auth token --token YOUR_GATEWAY_TOKEN --port 18789 --force
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

(Replace `YOUR_GATEWAY_TOKEN` with the actual token, and fix the path to `openclaw` if different — check with `which openclaw`.)

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw-gateway
sudo systemctl start openclaw-gateway

# Check it's running:
sudo systemctl status openclaw-gateway

# View logs:
sudo journalctl -u openclaw-gateway -f
```

Now the gateway starts automatically on NAS boot and restarts if it crashes.

---

## Quick reference: common operations

| What | Command |
|------|---------|
| SSH into NAS | `ssh jpdelgado7@<nas-ip>` |
| Check QA containers | `cd /volume1/docker/paperclip && docker compose -f docker-compose.qa.yml ps` |
| View QA web logs | `docker compose -f docker-compose.qa.yml logs qa-web --tail 50` |
| Rebuild QA from latest code | `./scripts/qa-rebuild.sh` |
| Rebuild without git pull | `./scripts/qa-rebuild.sh --quick` |
| Check gateway | `tmux attach -t openclaw-gateway` (or `systemctl status openclaw-gateway`) |
| Restart gateway | Kill and re-run (tmux) or `sudo systemctl restart openclaw-gateway` |
| Update QA skill | `cp /volume1/docker/paperclip/openclaw-skills/koiomi-qa/SKILL.md ~/.openclaw/skills/koiomi-qa/SKILL.md` |
| Check Tailscale | `tailscale status` |
| Re-apply OpenClaw patch | `node ~/patch-openclaw.js "$(npm root -g)/openclaw/dist/server-methods-DStUV8Sh.js"` |

---

## Troubleshooting

### QA containers won't build

```bash
docker compose -f docker-compose.qa.yml logs
```

Common causes:
- Docker not running → `sudo systemctl start docker`
- Out of disk space → `docker system prune -a` (careful: removes unused images)
- Network issue during npm install → retry

### Web app returns blank page or errors

```bash
docker compose -f docker-compose.qa.yml logs qa-web --tail 50
```

- If you see Vite compilation errors, the code on `paperclip-features` has issues
- If you see "Cannot connect to API," check `qa-api` logs too

### Playwright can't connect to the web app

The QA agent runs Playwright on the NAS **host**, but the web app runs in Docker on port 7070. Verify:

```bash
curl http://localhost:7070
```

If this fails, the web container isn't exposing the port correctly. Check `docker compose -f docker-compose.qa.yml ps` — the PORTS column should show `0.0.0.0:7070->4000/tcp`.

### Claude auth expires

```bash
claude whoami
# If it fails:
claude login
# Then restart the gateway
```

### OpenClaw patch gets overwritten

After updating OpenClaw (`npm install -g openclaw`), re-apply:

```bash
node ~/patch-openclaw.js "$(npm root -g)/openclaw/dist/server-methods-DStUV8Sh.js"
# Restart the gateway
```
