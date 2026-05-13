# Teammate onboarding

Welcome to Koiomi's shared Paperclip instance. This doc walks you through getting connected, end-to-end. It has two phases — pick how deep you want to go.

| | Time | What you get |
|---|---|---|
| **Phase 1** (required) | ~30 min | You can browse Paperclip in your browser, your Cowork can list/work on tickets via the MCP. This is "Pattern A — humans drive, Claude assists." |
| **Phase 2** (optional) | ~60 min | Your own autonomous agent that picks up tickets assigned to you and works on them using your Claude Max subscription — no prompting needed. This is "Pattern B — agent runs autonomously." Experimental; requires source patches that may break on upstream updates. |

**Recommendation:** everyone does Phase 1. Phase 2 is for teammates who want hands-off agents and are comfortable with terminal work and the occasional patch.

## Prerequisites

- Windows / macOS / Linux laptop
- Google account that Juan has invited to the Koiomi Tailscale tailnet
- Python 3.10+ (`python --version`)
- For Phase 2: Node.js 22+ (`node --version`) and a Claude.ai **Max** subscription
- Reasonable comfort with a terminal (Git Bash on Windows, Terminal on macOS/Linux)

## What Juan handles for you on the admin side

You don't need to do these — Juan does them. Listed so you know what to expect:

- Invite you to the Koiomi tailnet (Tailscale email).
- Generate your Paperclip invite link and send it to you (Slack/DM/email).
- Approve your join request after you accept the invite.
- **Create your agent in Paperclip** (e.g., `Engineer-<your-name>`) so tickets can be assigned to you.
- **Generate an API key on your agent** and send you the value via a secure channel (password-manager share, encrypted DM). You'll use this key in your MCP config. Treat it like a password.
- For Phase 2: allowlist your laptop's tailnet hostname on the NAS, add a hosts entry.

## Phase 1 — Required setup

### Step 1.1 [You] Install Tailscale

Follow `docs/TAILSCALE_TEAM_SETUP.md`. Stop after the smoke check (`tailscale status` shows `paperclip` device online).

### Step 1.2 [You] Open the Paperclip URL

Open `https://paperclip.tailc002ee.ts.net` in any browser. You should see a sign-up / sign-in page. If you see a TLS error, wait 30 seconds and reload (Tailscale provisions certs lazily on first hit).

### Step 1.3 [Juan] Send you the Paperclip invite link

Juan generates an Admin-role invite at **Settings → Invites → Create Invite** and DMs you the URL (looks like `https://paperclip.tailc002ee.ts.net/invite/pcp_invite_XXXX`).

### Step 1.4 [You] Sign up

Heads-up: the invite UI is currently broken upstream — clicking the link loads a blank page. Workaround in `docs/UPSTREAM_BUGS.md` issue #1. Short version:

1. Open `https://paperclip.tailc002ee.ts.net/auth/sign-up` (in a private/incognito window if you already used the URL).
2. Sign up with your email and a strong password (use your password manager).
3. After signup, you'll see a "No company access" message. That's expected.
4. Open browser dev tools (F12) → Console tab.
5. Paste this, replacing `<TOKEN>` with the token from the invite link Juan sent you (the part after `/invite/`):

   ```javascript
   fetch('/api/invites/<TOKEN>/accept', {
     method: 'POST',
     credentials: 'include',
     headers: {'Content-Type': 'application/json'},
     body: JSON.stringify({ requestType: 'human' }),
   }).then(r => r.json()).then(d => console.log(JSON.stringify(d, null, 2)));
   ```

6. Press Enter. You should see a `202` response with a join request payload. That created your join request.

### Step 1.5 [Juan] Approve your join request

Juan goes to **Settings → Invites → Open join request queue** and approves the one with your email.

### Step 1.6 [You] Reload — you're in

Refresh the Paperclip browser tab. You should land on the Koiomi dashboard as yourself.

### Step 1.7 [You] Install `paperclip-mcp` and wire into Cowork

Follow `docs/MCP_SETUP.md`. Important steps that often trip people up:

- **Apply the cookie-name patch** (step 2 of MCP_SETUP). The MCP fork on PyPI hardcodes the wrong cookie name; without the patch you'll get 401 errors from every call.
- **Use `--transport stdio`** in the Cowork command args. The default HTTP transport doesn't work with desktop Claude clients.
- **Use `PAPERCLIP_BASE_URL`** with `/api` suffix, not `PAPERCLIP_URL`.

### Step 1.8 [You] Smoke test

In a new Cowork conversation, ask:

> *"What tools do you have from the paperclip MCP server? Then list my Paperclip tasks."*

You should see ~21 tools listed (`list_issues`, `create_issue`, `comment_on_issue`, etc.) and a possibly-empty task list. If you see auth errors, check:

- Tailscale is connected (`tailscale status`)
- Your session token in the MCP config is current (cookies expire every ~30 days)
- The cookie patch from step 2 of MCP_SETUP is applied

### Step 1.9 [You] Read the team conventions

Skim `CLAUDE.md` and `docs/TEAM_WORKFLOW.md`. These describe how we name branches, how to mark tickets, what your Claude should do at the start of every session, etc.

**You're done with Phase 1.** You can now use Paperclip from your browser + your Cowork can do work on tickets assigned to you.

## Phase 2 — Optional: your own autonomous agent (OpenClaw)

Only do this if you want a true "agent picks up tickets from queue and works on them while you do other things" workflow.

Follow `docs/OPENCLAW_SETUP.md`. It's ~5 steps but each has surface area. Allow ~60 minutes.

After completing Phase 2 you'll have:
- An OpenClaw runtime on your laptop, authenticated to your Claude Max account
- A new agent in Paperclip (e.g. `Engineer-Marce`) tied to your OpenClaw via the gateway adapter
- The ability to assign a ticket to your agent and have it work without you typing prompts

## Troubleshooting

| Symptom | First thing to try |
|---|---|
| Browser can't load Paperclip URL | `tailscale status` — confirm Tailscale is connected, `paperclip` device is online |
| "No company access" after signing in | Juan needs to approve your join request (Phase 1.5) |
| Cowork shows no Paperclip tools | MCP config issue — re-check `docs/MCP_SETUP.md` and restart Cowork |
| Cowork sees tools but every call returns 401 | Cookie name patch missing (`docs/MCP_SETUP.md` step 2) or session token expired |
| OpenClaw "device not approved" | `openclaw devices list` → `openclaw devices approve <request-id>` (see `docs/OPENCLAW_SETUP.md`) |
| Any 500/502 from Paperclip API | Container hiccup on the NAS — ping Juan, he can `docker compose restart paperclip` |

## When you join an existing task

Once you have a Paperclip identity:
1. Open `https://paperclip.tailc002ee.ts.net/koi/dashboard`
2. Click on an issue assigned to you
3. From there it's normal git workflow — branch, work, PR, comment back on the ticket
4. Or ask your Cowork to do steps 1-3 for you ("what's on my queue, pick the top one, do it")
