# Upstream bugs and workarounds

Issues we hit during the initial Koiomi setup that aren't our deployment's fault — they're bugs or rough edges in `paperclipai/paperclip` or community forks. Documented here so the next teammate doesn't go through the same diagnostic chain.

Check this file's commit history before adding a new bug; some may already be fixed upstream.

## 1. Invite acceptance UI crashes for users without company access

**Symptoms.** Click an invite link, page loads to a blank black screen. Dev tools console shows:

```
Failed to load resource: /api/adapters returned 403
Uncaught TypeError: Cannot read properties of undefined (reading 'filter')
```

**Root cause.** The invite page makes an `/api/adapters` API call that requires company membership. But the *one* state where a user shouldn't yet have membership is when they're trying to accept an invite. The frontend JS crashes before rendering the Accept button.

**Workaround.** Skip the broken UI and create the join request via the API directly. The user opens dev tools → Console on the broken invite page (so the session cookie is available), and pastes:

```javascript
const token = 'pcp_invite_XXXXX';   // from the invite URL
fetch(`/api/invites/${token}/accept`, {
  method: 'POST',
  credentials: 'include',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({ requestType: 'human' }),
}).then(r => r.json()).then(console.log);
```

Expected response: `status: 202` with a join request payload. The admin then approves the request via Settings → Invites → Open join request queue.

**Tracking.** File at `paperclipai/paperclip` with title "Invite acceptance page crashes with TypeError on /api/adapters 403". Workaround above belongs in the report.

## 2. `paperclip-mcp` hardcodes the better-auth default cookie name

**Symptoms.** MCP starts cleanly, tools register in your client, but every call returns:

```
HTTP 401 from Paperclip API: {"error":"Unauthorized"}
```

**Root cause.** `paperclip-mcp` (0.2.1 on PyPI) hardcodes `_COOKIE_NAME = "__Secure-better-auth.session_token"` in `server.py`. But Paperclip self-hosted uses a customized cookie prefix: `__Secure-paperclip-default.session_token`. The MCP sends the right value with the wrong name; Paperclip rejects.

**Workaround.** Patch the source file on each teammate's laptop. See step 2 of `docs/MCP_SETUP.md`.

The patch is one `sed` line:

```bash
SRC=$(python -c "import paperclip_mcp, os; print(os.path.dirname(paperclip_mcp.__file__))")
sed -i 's|__Secure-better-auth\.session_token|__Secure-paperclip-default.session_token|g' "$SRC/server.py"
rm -f "$SRC/__pycache__/server.cpython-3"*".pyc"
```

**Tracking.** File at whichever fork's repo (`paperclipai/paperclip-mcp` if it exists, otherwise the community fork on PyPI). Suggested PR: make `_COOKIE_NAME` configurable via `PAPERCLIP_COOKIE_NAME` env var, defaulting to `__Secure-better-auth.session_token`. Small two-line change.

## 3. No per-user API keys in the UI

**Symptoms.** The MCP setup wants `PAPERCLIP_API_KEY`, but you can't find anywhere in Paperclip's UI to generate one. View profile shows only display name + avatar. Company Settings → Access is Owner-only.

**Root cause.** Per-user API key issuance isn't built yet (as of our deploy in May 2026). Only CLI bootstrap-CEO invites exist.

**Workaround.** Use `PAPERCLIP_SESSION_TOKEN` instead of `PAPERCLIP_API_KEY`. The MCP accepts either; precedence is `API_KEY > SESSION_TOKEN`. The session token is the browser cookie value — see step 3 of `docs/MCP_SETUP.md`.

Downsides of session tokens vs API keys:
- They expire (~30 days, better-auth default), so periodic re-grabbing.
- They're tied to the browser session, so signing out invalidates the MCP too.
- They can't be revoked independently from the user account.

**Tracking.** This is a feature request, not a bug. Probably on Paperclip's near-term roadmap given the volume of stars/forks.

## 4. Paperclip's SSRF guard rejects Tailscale CGNAT addresses

**Symptoms.** Paperclip's `/api/invites/<token>/test-resolution` endpoint and the agent runtime adapter both refuse to connect to URLs that resolve to private/CGNAT addresses (`100.64.0.0/10` — the range Tailscale uses):

```
"error": "url resolves to a private, local, multicast, or reserved address"
```

**Root cause.** `/app/server/dist/routes/access.js` and `/app/server/dist/services/plugin-host-services.js` both use `isPublicIpAddress(address)` which unconditionally rejects RFC-classified private/reserved addresses. There's no config flag or env var to opt out — even though `PAPERCLIP_DEPLOYMENT_EXPOSURE=private` is the documented "I'm running on a private network" signal.

**Workaround.** Patch `isPublicIpAddress` in `access.js` to add an env-gated bypass. Both files use the same function (one imports from the other), so a single patch fixes both.

```bash
docker exec -u root paperclip node -e "
const fs = require('fs');
const path = '/app/server/dist/routes/access.js';
let src = fs.readFileSync(path, 'utf8');
const marker = 'function isPublicIpAddress(address) {';
const inject = ' if (process.env.PAPERCLIP_TRUST_PRIVATE_HOSTS === \"true\" && (isIP(address) === 4 || isIP(address) === 6)) return true;';
if (src.includes('PAPERCLIP_TRUST_PRIVATE_HOSTS')) { console.log('already patched'); process.exit(0); }
if (!src.includes(marker)) { console.error('marker not found'); process.exit(1); }
src = src.replace(marker, marker + inject);
fs.writeFileSync(path, src);
console.log('patched');
"
```

Then add `PAPERCLIP_TRUST_PRIVATE_HOSTS=true` to `docker-compose.yml` and recreate the container.

Note: the patch lives in the container's writable layer. `docker compose up -d --force-recreate` will wipe it. Apply after every recreate.

**Tracking.** File upstream as: "Add config option to trust private hosts (tailnet / CGNAT) in invite test-resolution and plugin-host adapters."

## 5. Paperclip ↔ OpenClaw protocol drift: `paperclip` root field not accepted

**Symptoms.** OpenClaw is paired and reachable, but every agent invocation fails with:

```
[openclaw-gateway] request failed: invalid agent params: at root: unexpected property 'paperclip'
```

**Root cause.** Paperclip's `openclaw_gateway` adapter sends a payload that includes a `paperclip` root-level object (run metadata for traceability). OpenClaw's Ajv-compiled schema at `server-methods-DStUV8Sh.js:770` rejects unknown root properties. The invite prompt even hints that "Paperclip metadata can be included for traceability if the adapter supports it" — but this OpenClaw version doesn't.

**Workaround.** Strip the `paperclip` property from the request before validation. Patch in OpenClaw's installed source on each teammate's laptop:

```bash
cat > ~/patch-openclaw.js << 'PATCH_EOF'
const fs = require('fs');
const file = process.argv[2];
let src = fs.readFileSync(file, 'utf8');
if (src.includes('KOIOMI_STRIP_PAPERCLIP')) { console.log('already patched'); process.exit(0); }
const re = /(const p = params;\s*\n)(\s*)(if \(!validateAgentParams\(p\)\))/;
const m = src.match(re);
if (!m) { console.error('marker not found'); process.exit(1); }
const inject = m[1] + m[2] + '/* KOIOMI_STRIP_PAPERCLIP */ if (p && typeof p === "object") { delete p.paperclip; }\n' + m[2] + m[3];
src = src.replace(re, inject);
fs.writeFileSync(file, src);
console.log('patched ' + file);
PATCH_EOF

OC="$(npm root -g)/openclaw/dist"
node ~/patch-openclaw.js "$OC/server-methods-DStUV8Sh.js"
```

Then restart the OpenClaw gateway.

Note: `npm install -g openclaw` (any future upgrade) will overwrite the patch. Re-apply afterwards. The script is idempotent.

**Tracking.** File upstream at OpenClaw's repo: "Accept (or strip) `paperclip` root property in agent params for Paperclip integration." Suggested fix: change the Ajv schema from `additionalProperties: false` to `additionalProperties: true` for the agent params (or whitelist `paperclip`).

## 6. Write operations require API-key auth (session tokens 403 with "trusted browser origin")

**Symptoms.** The MCP can read everything fine (`list_issues`, `get_dashboard`, etc.) but any write — `create_issue`, `create_goal`, `comment_on_issue`, `update_issue` — fails with:

```
HTTP 403: Board mutation requires trusted browser origin
```

**Root cause.** Paperclip distinguishes between two auth modes:
- **API key (Bearer)** — full permissions, no origin check
- **Session token (Cookie)** — read-only over API; writes require requests to come from a "trusted browser origin" (a CSRF-style guard, since session cookies could be hijacked by malicious scripts running in the browser)

The MCP uses cookie auth when `PAPERCLIP_SESSION_TOKEN` is set, so writes always fail. There's no way to register the `paperclip-mcp` process as a "trusted browser origin" — it isn't a browser.

**Workaround.** Always use `PAPERCLIP_API_KEY` instead of `PAPERCLIP_SESSION_TOKEN` in the MCP config. Each teammate gets an API key by:
1. Having Juan create an agent for them (e.g., `Engineer-<name>`)
2. From that agent's Configuration tab → API Keys → Create API Key
3. Copy the value, paste into the teammate's MCP env as `PAPERCLIP_API_KEY`

The MCP source explicitly prefers API key over session token when both are set: *"Auth precedence: API key (Bearer) > session token (Cookie)."* But the cleaner config has only the API key.

**Tracking.** Not strictly a bug — it's intentional security design. But the failure mode is confusing because it shows up only on write attempts. Worth filing a docs improvement upstream asking that this distinction be made explicit when generating MCP-style integrations.

## How to file an upstream issue

When reporting any of these (or new ones), include:

- Paperclip version: `docker compose exec paperclip cat /app/package.json | grep version`
- Image digest: `docker compose images paperclip`
- Steps to reproduce
- Expected vs actual behavior
- The workaround you found (if any)

GitHub repo: <https://github.com/paperclipai/paperclip/issues>
