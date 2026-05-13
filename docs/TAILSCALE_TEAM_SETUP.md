# Tailscale team setup (per teammate)

What each of the three teammates does on their own laptop, once, so they can reach the NAS-hosted Paperclip.

You only need to do this when you first join the team. Five minutes.

## 1. Accept the Tailscale invite

Juan invites you to the Koiomi tailnet from Tailscale admin. You'll get an email from Tailscale — accept it and sign in with the same Google account you use for Koiomi.

If you're not sure whether you've been invited yet, ask Juan to check **Tailscale Admin → Users**.

## 2. Install the Tailscale client

| OS | How |
|----|-----|
| macOS | `brew install --cask tailscale` or download from <https://tailscale.com/download/mac> |
| Windows | <https://tailscale.com/download/windows> |
| Linux | `curl -fsSL https://tailscale.com/install.sh \| sh` |

Launch Tailscale and sign in with the same Google account from step 1.

## 3. Verify the tailnet connection

Open a terminal:

```bash
tailscale status
```

You should see a list of devices on the tailnet — including `paperclip` (the NAS-hosted instance) and the other teammates' laptops. If `paperclip` is missing or marked offline, ping Juan.

## 4. Open Paperclip in your browser

Go to the tailnet URL Juan shared with you — looks like:

```
https://paperclip.tail-abc123.ts.net
```

You should land on the login page (or, if you have a pending invite from Paperclip itself, the invite-accept page). Tailscale handles TLS automatically; if your browser flags the cert, wait 30 seconds and reload — Tailscale provisions certs lazily.

## 5. Accept your Paperclip invite

Juan sends you a separate invite from inside Paperclip's UI (this is a different invite from the Tailscale one).

> **Heads-up.** The invite acceptance page is currently broken upstream — clicking the link loads a blank black screen. This is a known bug, not a Tailscale or local-config problem. Workaround steps are in `docs/UPSTREAM_BUGS.md` (issue #1). Roughly: sign up at the bare URL with the invited email, then run a one-line `fetch()` in your browser dev tools console to create the join request. Juan then approves it from the admin side. Takes about 60 seconds end-to-end once you know the steps.

Once Juan approves your join request, refresh the Paperclip URL — you'll land on the Koiomi dashboard.

## 6. Generate your personal API key

Inside Paperclip, **User settings → API keys → New key**. Name it after your laptop. Save the value securely — you'll use it for the local MCP setup next.

## 7. Set up the MCP

Follow `docs/MCP_SETUP.md`. The only NAS-specific thing: when the doc tells you to set `PAPERCLIP_URL`, use the Tailscale URL from step 4.

## Sanity check

In your Claude (Claude Code, Cowork, or Desktop), open a new session and ask:

> List my open Paperclip tasks via the paperclip MCP.

You should see your queue (possibly empty). If you get an auth error, recheck the URL and API key. If the tool isn't found, recheck the MCP config and restart Claude.

## Troubleshooting

- **`tailscale status` works but the URL won't load.** Make sure you're connected to the tailnet (the Tailscale tray icon should be green/blue, not gray). If you're on a corporate VPN, it may be conflicting — turn the VPN off and retry.
- **Browser says "this site can't be reached".** The NAS might be offline. Ping Juan; he can check `docker compose ps` on the NAS.
- **You see Paperclip's login but your invite email never arrived.** Check spam. If still nothing, Juan can re-send from **Paperclip Admin → People**.
- **You can reach Paperclip from one device but not another.** Each device needs the Tailscale client installed and signed into the same account.

## Security note

The Paperclip URL is **only reachable while you're signed in to Tailscale on this device**. Don't bookmark it in a way that implies it's a public URL — it isn't. If you ever lose a device, revoke it in Tailscale admin and rotate your Paperclip API key.
