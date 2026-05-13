# Agent tuning playbook

Things to tune on autonomous agents after initial setup. Add new entries here as you discover them.

## Open: bump OpenClaw-backed agents' per-run timeout

**Why.** Paperclip's `openclaw_gateway` adapter defaults to `timeoutSec: 120` (see `/app/server/dist/services/company-portability.js:427`). Two minutes is too short for Opus 4.7 to reason through a typical Koiomi ticket — most runs time out mid-work. Symptom: dozens of `OpenClaw gateway run timed out after 120000ms` notifications.

`claude_local` adapter defaults to `timeoutSec: 0` (no timeout) for reference — only the OpenClaw path has this aggressive default.

**Recommended values.**

| Field | New value | Rationale |
|---|---|---|
| `timeoutSec` | `600` (10 min) | Long enough for one full ticket round-trip with Opus |
| `waitTimeoutMs` | `600000` | Matching, for wait-style invocations |
| `graceSec` | `15` (keep default) | Cleanup window after timeout |
| `maxTurnsPerRun` | `1000` (keep default) | Reasoning loop ceiling |

Don't go higher than 10 min on Claude Max — autonomous agents at long runways burn daily quota fast.

**How to apply (CLI doesn't expose `agent update`; use the REST API).**

On the NAS:

```bash
# Set your API key (from password manager)
API_KEY="paste-rotated-key-here"

# Confirm read access first
docker exec paperclip curl -s \
  -H "Authorization: Bearer $API_KEY" \
  http://localhost:3100/api/companies/10c76edd-839e-4950-aec3-e39d058a315a/agents/4d671d9d-fffe-4358-830c-7d9bd764f80a \
  | head -60
```

You should see Claudio's data with the current `adapterConfig`. If you get 401/403, the API key is wrong or expired — regenerate from Claudio's Configuration tab → API Keys → Create.

Then the actual PATCH:

```bash
docker exec paperclip curl -s -X PATCH \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "adapterConfig": {
      "timeoutSec": 600,
      "waitTimeoutMs": 600000,
      "graceSec": 15,
      "maxTurnsPerRun": 1000,
      "instructionsBundleMode": "managed",
      "dangerouslySkipPermissions": true,
      "sessionKey": "paperclip",
      "sessionKeyStrategy": "fixed",
      "role": "operator",
      "scopes": ["operator.admin"]
    }
  }' \
  http://localhost:3100/api/companies/10c76edd-839e-4950-aec3-e39d058a315a/agents/4d671d9d-fffe-4358-830c-7d9bd764f80a
```

Why pass the full adapterConfig: PATCH semantics in some Paperclip routes replace nested objects rather than merging. Safer to include all existing fields so nothing gets wiped.

**Verify the change.**

```bash
docker exec paperclip curl -s \
  -H "Authorization: Bearer $API_KEY" \
  http://localhost:3100/api/companies/10c76edd-839e-4950-aec3-e39d058a315a/agents/4d671d9d-fffe-4358-830c-7d9bd764f80a \
  | grep -A1 'timeoutSec'
```

Should now show `"timeoutSec": 600`.

**If the PATCH fails.**

Two fallbacks, in order of preference:

1. **Try PUT instead of PATCH.** Some Paperclip routes accept only one or the other.
2. **Direct DB update** (nuclear, but works). Embedded Postgres is at `localhost:54329` inside the container; the `agents` table has a JSONB `adapter_config` column. Connect with `docker exec -it paperclip psql -h localhost -p 54329 -U paperclip -d paperclip` and run:
   ```sql
   UPDATE agents 
   SET adapter_config = adapter_config || '{"timeoutSec":600,"waitTimeoutMs":600000}'::jsonb
   WHERE id = '4d671d9d-fffe-4358-830c-7d9bd764f80a';
   ```

## After applying the timeout fix

1. **Un-pause Claudio** in Paperclip's UI (top-right of his page → unpause).
2. **Reassign just one ticket** to Claudio. The other 84 we created earlier go back to "unassigned" until we know one ticket completes cleanly.
3. **Run Heartbeat manually** from Claudio's dashboard.
4. **Watch three places:**
   - Window 3 (openclaw chat) — Claudio narrating real work
   - Window 2 (gateway logs) — `agent`, `comment_on_issue`, `update_issue` RPC calls
   - Paperclip issue page — comment from Claudio + status flip to Done
5. **If the single ticket succeeds**, gradually re-assign more in batches of 5. Watch Claude Max quota along the way — three teammates running OpenClaw agents 24/7 against a backlog will hit limits fast.

## Future tuning candidates

Add here as you find them:

- **Heartbeat interval per agent.** Currently 600s for Claudio (10 min). For low-priority agents, increase to 3600s or higher.
- **Max concurrent runs.** Set to 1 for now while debugging. Can raise to 2-3 once stable.
- **"Continue after max-turn stop"** is OFF after our debugging session — keep it off until we understand the multi-turn cost profile.
- **Skill enablement.** Claudio has 8 paperclip-related skills enabled. Future agents may want fewer to reduce context overhead per run.
- **Model lane request.** Paperclip's wake_context requests "cheap" model lane but OpenClaw ignores (`adapter_profile_not_supported`). When OpenClaw adds profile support, we can route routine wakes to a cheaper model and reserve Opus for hard problems.

## Cost-tracking reminder

Each timed-out run still costs tokens (Opus reasons for ~2 minutes before getting cut). Pause first → fix → unpause is the right order. Don't leave a misconfigured agent running while you sleep.
