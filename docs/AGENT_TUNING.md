# Agent tuning playbook

Things to tune on autonomous agents after initial setup. Add new entries here as you discover them.

## Open: bump OpenClaw-backed agents' per-run timeout

**Why.** Paperclip's `openclaw_gateway` adapter defaults to `waitTimeoutMs: 120000` (2 min). Opus 4.7 reasoning a real ticket usually takes longer; runs time out mid-work. Symptom: notifications like `OpenClaw gateway run timed out after 120000ms`.

**Recommended values.**

| Field | Current | New | Why |
|---|---|---|---|
| `waitTimeoutMs` | `120000` | `600000` (10 min) | Long enough for one full ticket round-trip with Opus |
| `timeoutSec` | not set on agent (defaults to 120 from openclaw_gateway template) | `600` | Mirror of waitTimeoutMs in seconds |

Don't go higher than 10 min on Claude Max — autonomous agents at long runways burn daily quota fast.

**How to apply.**

The route is `PATCH /api/agents/:id` (line 2026 of `/app/server/dist/routes/agents.js`). The script below does GET → merge → PATCH → verify in one shot, so you don't have to copy sensitive fields (gateway token, device private key) around manually.

### Step 1 — Get your admin API key

If you don't already have a dedicated admin-tuning API key:

1. Paperclip UI → **Agents → Claudio → Configuration → API Keys → Create API Key**
2. Name: `admin-tuning`
3. Save the value to your password manager — Paperclip only shows it once.

### Step 2 — Load the key into your shell (no echo)

On the NAS:

```bash
read -s -p "Paste your Paperclip API key: " API_KEY
echo
```

Paste, Enter. The value is now in `$API_KEY`. Nothing prints to the terminal.

### Step 3 — Write the patch script

```bash
cat > /tmp/patch-claudio.js << 'EOF'
const http = require('http');
const apiKey = process.env.API_KEY;
const agentId = '4d671d9d-fffe-4358-830c-7d9bd764f80a';
const apiPath = '/api/agents/' + agentId;

function request(method, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost', port: 3100, path: apiPath, method,
      headers: { 'Authorization': 'Bearer ' + apiKey }
    };
    if (body) {
      options.headers['Content-Type'] = 'application/json';
      options.headers['Content-Length'] = Buffer.byteLength(body);
    }
    const req = http.request(options, (res) => {
      let chunks = '';
      res.on('data', c => chunks += c);
      res.on('end', () => resolve({status: res.statusCode, body: chunks}));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

(async () => {
  const get = await request('GET');
  if (get.status !== 200) {
    console.error('GET failed:', get.status, get.body.slice(0, 400));
    process.exit(1);
  }
  const agent = JSON.parse(get.body);
  console.log('BEFORE:', JSON.stringify({
    waitTimeoutMs: agent.adapterConfig.waitTimeoutMs,
    timeoutSec: agent.adapterConfig.timeoutSec
  }));

  const newAdapterConfig = Object.assign({}, agent.adapterConfig, {
    waitTimeoutMs: 600000,
    timeoutSec: 600
  });

  const patch = await request('PATCH', JSON.stringify({ adapterConfig: newAdapterConfig }));
  console.log('PATCH status:', patch.status);

  if (patch.status >= 200 && patch.status < 300) {
    const updated = JSON.parse(patch.body);
    console.log('AFTER:', JSON.stringify({
      waitTimeoutMs: updated.adapterConfig.waitTimeoutMs,
      timeoutSec: updated.adapterConfig.timeoutSec
    }));
    console.log('SUCCESS');
  } else {
    console.error('PATCH failed:', patch.body.slice(0, 500));
  }
})();
EOF
```

### Step 4 — Run it inside the container

```bash
docker cp /tmp/patch-claudio.js paperclip:/tmp/patch-claudio.js
docker exec -e API_KEY="$API_KEY" paperclip node /tmp/patch-claudio.js
```

Expected output:

```
BEFORE: {"waitTimeoutMs":120000}
PATCH status: 200
AFTER: {"waitTimeoutMs":600000,"timeoutSec":600}
SUCCESS
```

### If the PATCH errors

- **`PATCH failed: ... validation failed`** — the `updateAgentSchema` doesn't accept full adapterConfig replacement. Modify the script to send a smaller PATCH body like `{"adapterConfig": {"waitTimeoutMs": 600000}}` and see if it merges. Or inspect: `grep -n 'updateAgentSchema' /app/server/dist/routes/agents.js | head -5`.
- **`PATCH status: 403`** — API key isn't being honored. Re-check the key is current and not the leaked one (`initial-join-key` — see Credential rotation section below).
- **`PATCH status: 404`** — wrong agent ID, or URL pattern changed. Confirm with the GET first.

### Tuning the script for other agents

For other agents than Claudio, change the `agentId` constant at the top of the script. Get the UUID from `Agents → <agent name> → URL` or via `paperclipai agent list`.

## After applying the timeout fix

1. **Un-pause Claudio** (Paperclip UI, top-right of his page → click the pause button to unpause).
2. **Reassign just one ticket** to Claudio. Reassign the other ~83 back to "unassigned" until we know one ticket completes cleanly.
3. **Run Heartbeat manually** from Claudio's dashboard.
4. **Watch three places:**
   - Window 3 (openclaw chat) — Claudio narrating real work
   - Window 2 (gateway logs) — `agent`, `comment_on_issue`, `update_issue` RPC calls
   - Paperclip issue page — comment from Claudio + status flip to Done
5. **If the single ticket succeeds**, gradually re-assign more in batches of 5. Watch Claude Max quota along the way.

## Credential rotation (separate task — also tomorrow)

During the diagnostic session of 2026-05-13, several credentials were briefly exposed in chat or in API response output that was pasted to chat:

| Credential | Where exposed | Severity |
|---|---|---|
| Personal session token (rotated 2x already) | First-time MCP setup | low (rotated) |
| Claudio API key (`pcp_21062cd7…`) | API-key auth setup | medium (revoke `initial-join-key` after rotating OpenClaw's local copy) |
| Gateway token (`x-openclaw-token`) | API GET response paste | medium (tailnet-only attack surface) |
| Device private key (`devicePrivateKeyPem`) | API GET response paste | medium (same tailnet surface) |

Tomorrow, after the timeout fix:

1. Revoke `initial-join-key` in Claudio's Configuration → API Keys → Active Keys.
2. Update OpenClaw's local config to use a fresh key (or re-onboard from scratch).
3. Generate a new gateway token, restart the gateway with `--token NEW_VALUE`, update Claudio's `adapterConfig.headers["x-openclaw-token"]` via the same PATCH route.
4. Consider re-pairing Claudio's device entirely (regenerate `devicePrivateKeyPem`) — easiest path is running the OpenClaw invite-prompt flow again.

Tailnet-only deployment limits the practical blast radius to the three of you, but better hygiene long-term.

## Future tuning candidates

Add here as you find them:

- **Heartbeat interval per agent.** Currently 600s for Claudio (10 min). For low-priority agents, increase to 3600s or higher.
- **Max concurrent runs.** Set to 1 for now while debugging. Can raise to 2-3 once stable.
- **"Continue after max-turn stop"** is OFF after our debugging session — keep it off until we understand the multi-turn cost profile.
- **Skill enablement.** Claudio has 8 paperclip-related skills enabled. Future agents may want fewer to reduce context overhead per run.
- **Model lane request.** Paperclip's wake_context requests "cheap" model lane but OpenClaw ignores (`adapter_profile_not_supported`). When OpenClaw adds profile support, we can route routine wakes to a cheaper model and reserve Opus for hard problems.

## Cost-tracking reminder

Each timed-out run still costs tokens (Opus reasons for ~2 minutes before getting cut). Pause first → fix → unpause is the right order. Don't leave a misconfigured agent running while you sleep.
