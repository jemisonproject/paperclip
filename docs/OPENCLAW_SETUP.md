# OpenClaw setup — your own autonomous agent

This is Phase 2 of teammate onboarding. Only follow if you want a true autonomous agent — one that picks up tickets from your queue and works on them using your Claude Max subscription without you typing prompts each time.

**Heads-up before you start:**

- This is **experimental**. Paperclip and OpenClaw are both fast-moving and their protocols haven't fully converged for self-hosted tailnet deployments. As of when this doc was written, we needed three source patches to make them talk. Future updates may require new patches or break old ones.
- Estimated time: **~60 minutes** of focused work. Don't start when you're tired.
- You need Phase 1 (`docs/TEAMMATE_ONBOARDING.md`) complete first.
- You need **Claude Max** (not just Pro) — autonomous agent runs burn tokens fast and Pro's daily quota won't cut it for sustained work.

## Architecture

```
   Your laptop                                   Koiomi NAS
┌──────────────────────────┐               ┌─────────────────────┐
│ OpenClaw daemon          │               │ Paperclip container │
│   - Your Claude Max      │ ◄─ webhook ──┤   - openclaw_gateway│
│   - Tools (gh, etc.)     │   over WSS    │     adapter         │
│   - localhost:18789      │   Tailscale   │   - your agent      │
│ Tailscale Serve fronts   │               │                     │
│ at <laptop>.ts.net:443   │               │                     │
└──────────────────────────┘               └─────────────────────┘
```

When a ticket gets assigned to your agent and Paperclip's heartbeat fires, Paperclip opens a WebSocket to your laptop's OpenClaw runtime over Tailscale. Your OpenClaw runs the task using your local Claude Max. Result flows back to Paperclip as a comment / status update.

**Critical limitation:** the agent only runs when your laptop is **awake with OpenClaw running**. Sleep = agent stops. Use a sleep schedule that fits how you'd like the agent to work.

## What Juan does for you

Before you start, ask Juan to do these on the NAS (he can run them in one go):

```bash
# Replace <your-laptop-hostname> and <your-tailnet-ip> with your values
# Find them with `tailscale status` on your own laptop

# 1. Allowlist your laptop hostname in Paperclip
docker exec paperclip pnpm paperclipai allowed-hostname <your-laptop-hostname>.tailc002ee.ts.net

# 2. Add /etc/hosts entry so Paperclip's container can resolve it
docker exec -u root paperclip sh -c \
  "echo '<your-tailnet-ip> <your-laptop-hostname>.tailc002ee.ts.net' >> /etc/hosts"
```

(Long-term, we want `TS_ACCEPT_DNS=true` on the tailscale sidecar instead of manual hosts entries — open issue.)

## Step 1 — Install OpenClaw

Open a fresh terminal (Git Bash on Windows, Terminal on macOS/Linux).

```bash
# Confirm Node 22+ (recommended: Node 24)
node --version

# Install OpenClaw globally
npm install -g openclaw

# Verify
openclaw --version
```

If the binary isn't on your PATH after install, find it (usually `~/.local/bin/` or `%APPDATA%\npm\`) and add that directory to your User PATH. On Windows in PowerShell:

```powershell
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Users\<you>\AppData\Roaming\npm", "User")
```

Close + reopen terminals to pick up the PATH change.

## Step 2 — Run the onboarding wizard

```bash
openclaw onboard
```

Choices that work for our setup:

| Prompt | Pick |
|---|---|
| Setup path | **Quickstart** |
| Model/auth provider | **Anthropic (Claude CLI + API key)** |
| Channel (Telegram/Discord/etc.) | **Skip for now** — we don't need a chat channel |
| Search provider | **Skip for now** — add later if useful |
| Configure skills | **Yes**, accept defaults; skip anything that requires external API keys |
| Install missing skill dependencies | **Skip for now** |
| Enable hooks | **Skip for now** |

When it asks about Claude auth, it'll detect your local Claude CLI session. Confirm you're logged in by running `claude whoami` in another terminal — should show your Claude Max email.

## Step 3 — Generate a gateway auth token

You'll need a strong random token for the gateway. Generate once, save to your password manager, use multiple times below.

```bash
openssl rand -hex 32
```

Save the hex string. From here on, anywhere I write `YOUR_GATEWAY_TOKEN`, paste that value.

## Step 4 — Start the gateway

Open a **second terminal** dedicated to running the gateway:

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

Wait for two log lines:

- `[tailscale] serve enabled: https://<your-hostname>.tailc002ee.ts.net/`
- `[gateway] ready`

**Leave this terminal open.** Closing it kills the gateway and your agent stops responding.

Copy down your `<your-hostname>` from that log line (looks like `desktop-marce.tailc002ee.ts.net` or similar). Send this to Juan so he can update the NAS allowlist if he hasn't already.

## Step 5 — Onboard your agent into Paperclip

### 5a. Generate the OpenClaw invite prompt from Paperclip

In Paperclip's browser tab (logged in as yourself):

1. **Settings → General → INVITES → Generate OpenClaw Invite Prompt**
2. A text block appears — copy the entire thing.

### 5b. Paste it into OpenClaw chat

Open a **third terminal**:

```bash
openclaw chat
```

When the chat prompt appears, paste the entire invite prompt from step 5a. OpenClaw's local Claude reads it and starts onboarding itself to Paperclip. You'll see narration like *"I'll set up the connection to Paperclip…"*.

Watch terminal 2 (gateway logs) — you'll see incoming WebSocket connections from Paperclip's tailnet IP. The handshake takes ~30 seconds.

When it finishes, OpenClaw chat prints a summary:

```
Paperclip onboarding complete:
- Joined as <YourAgentName>
- Company: Koiomi
- API key claimed and saved
- Skill installed at ~/.openclaw/skills/paperclip/SKILL.md
```

### 5c. Approve device pairings (twice)

Paperclip pairs **two devices** with your OpenClaw — one for pairing/auth, one for the actual worker. Each needs explicit approval. In your **first terminal** (not the gateway one):

```bash
# See what's pending
openclaw devices list

# It'll show one pending request with note "First-time device pairing request"
# Copy the Request ID (NOT the Device ID — they're different)

# Approve it
openclaw devices approve <request-id> --token YOUR_GATEWAY_TOKEN
```

Repeat for the second pending request that appears (usually a "scope upgrade" for the pairing device). When `openclaw devices list` shows only "Paired (2)" and no "Pending" section, you're done.

## Step 6 — Apply the OpenClaw schema patch

There's a known protocol drift between Paperclip and OpenClaw — Paperclip sends a `paperclip` metadata field that OpenClaw's strict schema rejects. One-line patch fixes it.

Save the patch script to your home directory:

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

# Verify
grep -n 'KOIOMI_STRIP_PAPERCLIP' "$FILE"
```

The `grep` at the end should print one line near `:770` showing the marker. If yes, patch is in. If you see `marker not found`, the file path or OpenClaw version differs — ping Juan with the output.

## Step 7 — Restart the gateway

In terminal 2 (running gateway), press **Ctrl+C** to stop. Re-run the same start command:

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

Wait for the `[gateway] ready` line.

## Step 8 — Test

In Paperclip's browser tab:

1. Go to **Agents → \<YourAgentName\>**
2. Click the **Test** button on the Adapter section. Should turn green with "Gateway connect probe succeeded."
3. Click **+ Assign Task** and create:
   - Title: `Test: introduce yourself`
   - Description: `Post a comment on this issue introducing yourself: your name, role, model you're running, one sentence about your purpose. Then mark this issue as done.`
   - Assignee: you (your agent)
4. Click **▷ Run Heartbeat**.

Within ~30 seconds:

- Terminal 3 (openclaw chat) should narrate Claudio reading the issue and posting a comment
- Terminal 2 (gateway logs) shows actual `agent` and `comment_on_issue` RPC calls
- The Paperclip issue page (reload) shows your agent's comment and status flipped to **Done**

If you see those three things, **your autonomous agent is working**. Welcome to the future.

## Day-to-day operation

- **Keep the gateway running** when you want your agent active. Easiest: put the `openclaw gateway run …` command in a startup script.
- **Heartbeat schedule:** Configure on your agent's page → Configuration tab → Run Policy → "Heartbeat on interval". 1800 sec (30 min) is reasonable.
- **Sleep behavior:** When your laptop sleeps, OpenClaw pauses. When it wakes, OpenClaw reconnects. Existing Paperclip heartbeats during sleep will mark as failed; agent picks them up on the next heartbeat tick.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Gateway won't start, "tailscale serve requires bind=loopback" | Use `--bind loopback`, not `--bind tailnet` |
| Adapter test passes, but task fails with "pairing required" | Re-run `openclaw devices list` + approve any pending requests |
| Task fails with "invalid agent params: unexpected property 'paperclip'" | Step 6 patch not applied or got overwritten by `npm install -g openclaw`. Re-apply. |
| Task fails with "url resolves to private address" | NAS side — Juan needs to set `PAPERCLIP_TRUST_PRIVATE_HOSTS=true` and apply the access.js patch. See `docs/UPSTREAM_BUGS.md`. |
| `openclaw devices list` shows pending requests but they keep coming back | Paperclip is generating a new device key each connection. Ensure your agent has `adapterConfig.devicePrivateKeyPem` persisted — should happen automatically during onboarding. |
| Gateway logs flood with `event_loop_delay liveness warning` | Normal-ish on Windows. Ignore unless it correlates with task failures. |

## When OpenClaw upgrades break the patch

```bash
# Re-apply the patch (the script is idempotent)
node ~/patch-openclaw.js "$(npm root -g)/openclaw/dist/server-methods-DStUV8Sh.js"
```

Long-term fix: file an upstream issue requesting either a `strict: false` option on the agent params schema, or first-class support for a `paperclip` metadata field. See `docs/UPSTREAM_BUGS.md` for the issue template.
