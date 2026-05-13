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
 │  │  ┌───────────────┐                │           │  │
 │  │  │  paperclip    │ ───────────────┘           │  │
 │  │  │  :3000        │                            │  │
 │  │  └───────────────┘                            │  │
 │  │                                               │  │
 │  │  /data    ./data/paperclip on NAS storage     │  │
 │  └───────────────────────────────────────────────┘  │
 └─────────────────────────────────────────────────────┘
                      │ WireGuard (Tailscale)
                      ▼
       https://paperclip.<your-tailnet>.ts.net
              (reachable only by Tailscale members)
```

## 1. Prerequisites on the NAS

- UGOS Pro or equivalent with **Docker** enabled. UGREEN's package manager calls it "Docker" — install it from the App Center if not already there.
- SSH access to the NAS. Enable it in **UGOS → Control Panel → Terminal & SNMP → SSH** if it isn't already.
- A storage pool / shared folder where Paperclip data will live. We'll put everything under one folder, e.g. `/volume1/docker/paperclip`. Adjust the path to wherever your storage pool is mounted.

## 2. Prerequisites in Tailscale

1. Go to <https://tailscale.com/> and sign up with the team's Google account (or Juan's personal one — same tailnet works either way; Tailscale is free for up to 3 users + 100 devices on the Personal plan).
2. Invite the other two teammates by email from **Admin → Users**.
3. Define a tag for this device. In **Admin → Access controls (ACL)**, edit the ACL JSON to declare the `paperclip` tag, e.g.:
   ```json
   {
     "tagOwners": {
       "tag:paperclip": ["juandelgadocarp@gmail.com"]
     },
     "acls": [
       { "action": "accept", "src": ["*"], "dst": ["tag:paperclip:443"] }
     ]
   }
   ```
   Save the ACL.
4. Generate an auth key for the NAS container at <https://login.tailscale.com/admin/settings/keys>:
   - Reusable: **yes**
   - Ephemeral: **no**
   - Tags: **tag:paperclip**
   - Expiry: 90 days (default) — you'll rotate this twice a year.
   - Copy the key (`tskey-auth-...`). You won't see it again.

## 3. Get the repo onto the NAS

SSH into the NAS:

```bash
ssh juan@<nas-ip>
cd /volume1/docker          # or wherever your docker stack folder lives
git clone https://github.com/jemisonproject/paperclip.git
cd paperclip
```

Create the folders that will hold persistent data:

```bash
mkdir -p data/paperclip data/tailscale-state
chown -R 1000:1000 data/paperclip      # paperclip container runs as node user
```

## 4. Configure `.env`

```bash
cp .env.example .env
nano .env
```

Fill in:

| Variable | What to put |
|----------|-------------|
| `TS_AUTHKEY` | The `tskey-auth-...` from step 2.4 |
| `PAPERCLIP_PUBLIC_URL` | Leave the placeholder for now — fill in after step 5 |
| `PAPERCLIP_SECRET` | Run `openssl rand -hex 32` and paste the output |
| `PAPERCLIP_ADMIN_EMAIL` | `juandelgadocarp@gmail.com` |

Save the file. Confirm it's gitignored:

```bash
git status        # .env should NOT appear
```

## 5. Bring up the stack

```bash
docker compose up -d
docker compose logs -f
```

Wait for two things in the logs:

1. **Tailscale joins the tailnet.** You'll see lines like `Success.` and `100.x.x.x is the IP for paperclip`.
2. **Paperclip prints the admin invite URL** on first boot — something like `Open this URL to claim the admin account: http://...`. Note that the URL printed will be the internal `http://localhost:3000`; that's expected.

Once both are healthy, get the real Tailscale hostname:

```bash
docker exec paperclip-tailscale tailscale status
```

Look for the `paperclip` device — it'll show a full hostname like `paperclip.tail-abc123.ts.net`.

## 6. Tell Tailscale to serve Paperclip on HTTPS

```bash
docker exec paperclip-tailscale tailscale serve --bg --https=443 http://127.0.0.1:3000
```

This tells Tailscale's edge to terminate TLS at the tailnet hostname and forward to Paperclip's port. It only needs to run once per device — Tailscale persists the config.

Verify:

```bash
docker exec paperclip-tailscale tailscale serve status
```

Expected output:

```
https://paperclip.tail-abc123.ts.net (tailnet only)
|-- / proxy http://127.0.0.1:3000
```

## 7. Set the public URL and restart Paperclip

Now that you know the Tailscale hostname, update `.env`:

```bash
nano .env
# Set PAPERCLIP_PUBLIC_URL=https://paperclip.tail-abc123.ts.net
```

Restart so Paperclip picks it up:

```bash
docker compose up -d
```

## 8. Claim the admin account

1. On Juan's laptop with Tailscale installed and connected, open the URL: `https://paperclip.tail-abc123.ts.net`.
2. The first time you'd see the invite/setup flow — follow it to create the admin user and company.
3. If the deploy logs printed an invite URL, that's the one to open (with the hostname rewritten from `localhost:3000` to your tailnet URL).

## 9. Invite the other two teammates

Inside Paperclip's admin UI, invite both teammates by email. They'll then follow `docs/TAILSCALE_TEAM_SETUP.md` to get on the tailnet, then click the invite link.

## 10. Backups

The whole instance lives under `./data/paperclip` on the NAS. Two practical patterns — pick one:

- **NAS snapshots.** If UGOS supports snapshots on the volume that holds `/volume1/docker`, schedule daily snapshots with 14-day retention. Easiest.
- **Off-box pg_dump.** Add a cron entry that runs `docker exec paperclip pg_dump paperclip > backup-$(date +%F).sql` daily and rsyncs to another machine.

Test a restore once before you rely on it.

## Operational tips

- **View logs:** `docker compose logs -f paperclip` (or `tailscale`).
- **Restart after a config change:** `docker compose up -d` (compose only restarts changed services).
- **Stop everything:** `docker compose down`. Data persists under `./data/`.
- **Update Paperclip:** `git pull && docker compose build paperclip --no-cache && docker compose up -d`. The `--no-cache` rebuilds with the latest upstream Paperclip commit. Always take a snapshot/backup first.
- **Rotate the Tailscale auth key:** Generate a new one in Tailscale admin, replace `TS_AUTHKEY` in `.env`, `docker compose up -d --force-recreate tailscale`.

## If something goes wrong

- **Container won't start:** `docker compose logs paperclip` and `docker compose logs tailscale`. Most failures are a typo in `.env` or a missing `/data` folder permission.
- **Tailscale joins but `tailscale serve` errors:** usually means the tag in the ACL doesn't allow port 443. Re-check step 2.3.
- **Paperclip starts but the URL gives a TLS warning:** Tailscale takes ~30 seconds to provision a cert on first run; wait a minute and reload.
- **Paperclip build fails:** the Dockerfile clones upstream Paperclip from `paperclipai/paperclip`. If upstream has changed structure, see [the Paperclip docs](https://docs.paperclip.ing) and adjust `entrypoint.sh`'s entry-point detection.
