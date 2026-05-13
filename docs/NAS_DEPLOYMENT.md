# Deploying Paperclip on a UGREEN NAS (UGOS) with Tailscale

Step-by-step setup for the shared Paperclip instance on Juan's UGREEN NAS, reachable to the three teammates over a private Tailscale network.

You do this once. The other two teammates only follow `docs/TAILSCALE_TEAM_SETUP.md`.

## Architecture in one diagram

```
 LAN / WAN
     │
     ▼
 ┌─────────────────────────────────────────────────────┐
 │  UGREEN NAS (UGOS, Docker)                          │
 │  ┌───────────────────────────────────────────────┐  │
 │  │  docker compose stack                         │  │
 │  │                                               │  │
 │  │  ┌───────────────┐    shared netns            │  │
 │  │  │  tailscale    │ ◄──────────────┐           │  │
 │  │  └───────────────┘                │           │  │
 │  │                                   │           │  │
 │  │  ┌──────────────────────────┐     │           │  │
 │  │  │  paperclip               │ ────┘           │  │
 │  │  │  ghcr.io/paperclipai/    │                 │  │
 │  │  │  paperclip:latest :3100  │                 │  │
 │  │  └──────────────────────────┘                 │  │
 │  │                                               │  │
 │  │  /paperclip   ./data/paperclip on NAS storage │  │
 │  └───────────────────────────────────────────────┘  │
 └─────────────────────────────────────────────────────┘
                      │ WireGuard (Tailscale)
                      ▼
       https://paperclip.<your-tailnet>.ts.net
              (reachable only by Tailscale members)
```

We use the **official prebuilt image** from GitHub Container Registry — no local build. Embedded Postgres and all Paperclip state live under `/paperclip` inside the container, which is bind-mounted to `./data/paperclip` on the NAS.

## 1. Prerequisites on the NAS

- UGOS Pro (or equivalent) with **Docker** installed from the App Center.
- SSH access enabled (UGOS → `Panel de Control` → `Terminal y SNMP` → Habilitar servicio SSH).
- The user (e.g. `jpdelgado7`) added to the `docker` group. After adding, log out and back in.
- A storage pool that exposes a world-writable Docker stacks folder. On UGREEN DXP NASes this is typically `/volume1/docker/`.

## 2. Prerequisites in Tailscale

1. Sign up at <https://tailscale.com/> with the **project Google account** (`koiomi.app@gmail.com`).
2. **Access controls** → enable the `tag:paperclip` tag in the JSON policy editor:
   ```json
   {
     "tagOwners": {
       "tag:paperclip": ["autogroup:admin"]
     },
     "grants": [
       { "src": ["*"], "dst": ["*"], "ip": ["*"] }
     ]
   }
   ```
   Save.
3. **Settings → Keys → Generate auth key** with: Description `paperclip-nas`, Reusable **on**, Ephemeral **off**, Tags **`tag:paperclip`**, Expiration 90 days. Copy the `tskey-auth-…` value — it's shown only once.

## 3. Get the repo onto the NAS

SSH into the NAS:

```bash
ssh jpdelgado7@<nas-ip>
cd /volume1/docker
git clone https://github.com/jemisonproject/paperclip.git
cd paperclip
```

Create the host folders for persistent state, with ownership matching the container's `node` user (UID 1000):

```bash
mkdir -p data/paperclip data/tailscale-state
sudo chown -R 1000:1000 data/paperclip
```

## 4. Configure `.env`

```bash
cp .env.example .env

# Generate the auth secret first — you'll paste this value below
openssl rand -hex 32

nano .env
```

Fill in:

| Variable | What to put |
|----------|-------------|
| `TS_AUTHKEY` | The `tskey-auth-…` from step 2.3 |
| `PAPERCLIP_PUBLIC_URL` | Leave the placeholder for now — fill in after step 5 |
| `BETTER_AUTH_SECRET` | The 64-char hex output of `openssl rand -hex 32` |

Save (`Ctrl+O` → `Enter` → `Ctrl+X`). Confirm `.env` is gitignored:

```bash
git status        # .env should NOT appear
```

## 5. Bring up the stack

```bash
docker compose up -d
docker compose logs -f
```

Wait for two signals in the logs:

1. **Tailscale joins the tailnet** — `Success.` and a `100.x.x.x is the IP for paperclip` line.
2. **Paperclip starts on port 3100** — a server-ready log line.

Once both look healthy, get the assigned Tailscale hostname:

```bash
docker exec paperclip-tailscale tailscale status
```

Look for the `paperclip` device — its full name is something like `paperclip.tail-abc123.ts.net`.

## 6. Tell Tailscale to serve Paperclip on HTTPS

```bash
docker exec paperclip-tailscale tailscale serve --bg --https=443 http://127.0.0.1:3100
```

This tells Tailscale's edge to terminate TLS at the tailnet hostname and forward to Paperclip's `:3100` inside the shared netns. The config persists across container restarts.

Verify:

```bash
docker exec paperclip-tailscale tailscale serve status
```

Expected:

```
https://paperclip.tail-abc123.ts.net (tailnet only)
|-- / proxy http://127.0.0.1:3100
```

## 7. Set the public URL and restart Paperclip

Now that you have the real Tailscale hostname, update `.env`:

```bash
nano .env
# Set PAPERCLIP_PUBLIC_URL=https://paperclip.tail-abc123.ts.net
```

Restart only the paperclip container so it picks up the new URL:

```bash
docker compose up -d paperclip
```

## 8. Claim the admin account

1. On Juan's laptop, with Tailscale installed and connected, open `https://paperclip.tail-abc123.ts.net`.
2. The first request loads the signup / setup flow. Create the admin account with `koiomi.app@gmail.com` and set the company name.
3. Future logins use this account, plus the two teammates you'll invite next.

## 9. Invite the other two teammates

Inside Paperclip's admin UI: **Settings → Invites → Create invite**. Choose role **Admin** for peer teammates (Operator can't create their own agents). Each invite link is single-use and goes to your clipboard — paste it somewhere safe with the recipient's name next to it so you don't mix them up, then send via DM/email.

Heads-up: **the invite acceptance UI is currently broken upstream.** See `docs/UPSTREAM_BUGS.md` (issue #1) for the workaround. Each teammate will need to run a one-line `fetch()` in their browser console after signing up. You'll then approve the join request from your admin tab at **Settings → Invites → Open join request queue**.

Each teammate next follows `docs/TAILSCALE_TEAM_SETUP.md` to get on the tailnet, then `docs/MCP_SETUP.md` to wire their local Claude to the NAS.

## 10. Backups

All state lives under `./data/paperclip` on the NAS. Two practical patterns — pick one:

- **NAS snapshots.** Schedule daily snapshots on the volume that holds `/volume1/docker/`, 14-day retention. Easiest if UGOS supports it.
- **Off-box dump.** Cron a daily script that copies `./data/paperclip` to another machine via `rsync`. Stop the container first if the embedded Postgres is mid-write: `docker compose stop paperclip && rsync … && docker compose start paperclip`.

Test a restore once before you rely on it.

## Operational tips

- **View logs:** `docker compose logs -f paperclip` (or `tailscale`).
- **Restart after a config change:** `docker compose up -d`. Compose only restarts changed services.
- **Stop everything:** `docker compose down`. Data persists in `./data/`.
- **Update Paperclip:** `docker compose pull paperclip && docker compose up -d paperclip`. Take a snapshot/backup first.
- **Rotate the Tailscale auth key:** Generate a new key in Tailscale admin, replace `TS_AUTHKEY` in `.env`, `docker compose up -d --force-recreate tailscale`.

## If something goes wrong

- **Container won't start:** `docker compose logs paperclip` and `docker compose logs tailscale`. Most failures are a typo in `.env` or wrong permissions on `data/paperclip`.
- **Tailscale joins but `tailscale serve` errors:** the tag in the ACL may not allow port 443. Re-check step 2.2.
- **TLS warning in the browser:** Tailscale provisions a cert on first run; wait ~30 seconds and reload.
- **`Permission denied` writing to `/paperclip`:** the host folder isn't owned by UID 1000. Run `sudo chown -R 1000:1000 data/paperclip` and `docker compose up -d --force-recreate paperclip`.
