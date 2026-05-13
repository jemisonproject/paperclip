# Per-teammate `paperclip-mcp` setup

Every teammate runs this once on their own laptop. It's what lets your local Claude (Cowork, Claude Code, or Claude Desktop) call into the shared cloud Paperclip — list your tasks, claim them, update status, post comments — without leaving the editor.

## Mental model

Two layers, easy to conflate:

1. **Local Claude → cloud Paperclip (operator).** Your laptop runs `paperclip-mcp`, which exposes Paperclip's REST API as MCP tools. Your Claude calls those tools. This is what this guide sets up.
2. **Agents inside Paperclip → Anthropic (worker).** Agents you create inside Paperclip's UI authenticate separately. That's not part of this setup.

## Prerequisites

- You've already followed `docs/TAILSCALE_TEAM_SETUP.md` and can reach the Paperclip URL from your browser.
- Juan (or an admin) has invited you, you've accepted, and you can sign in to Paperclip as yourself.
- **Juan has created an agent for you in Paperclip** (e.g. `Engineer-<your-name>`) and provisioned an API key on that agent. He'll send you the API key value — guard it like a password.
- Python 3.10+ installed (`python --version`).

> **Why an agent-bound API key?** Paperclip's REST API gates *write* operations (creating issues, posting comments) on either an API key or a trusted browser session. Session cookies from your laptop don't count as "trusted browser origin," so they 403 on writes. API keys bypass that check. Each API key is scoped to an agent — writes you make via the MCP get attributed to that agent in the audit log. For day-to-day work, this is fine: the agent represents "your slot in the team," and your Claude is acting on its behalf.

## 1. Install `paperclip-mcp`

```bash
# Recommended: pipx (isolated)
pipx install paperclip-mcp

# Or, if pipx isn't installed, plain pip --user:
pip install --user paperclip-mcp
```

Verify it runs:

```bash
paperclip-mcp --version
```

If the command isn't found, the binary is installed but not on PATH. On Windows, `pip install --user` puts it in `%USERPROFILE%\AppData\Roaming\Python\Python3XX\Scripts` — add that folder to your User PATH and reopen your shell.

## 2. Get the company ID

You need Paperclip's company UUID for the MCP config. Two ways:

- **Ask Juan / check the deploy notes.** Koiomi's company ID is recorded in the project notes.
- **Find it yourself:** in dev tools → Network tab, open any Paperclip page, look at any `/api/...` request response — `companyId` appears in most of them.

## 3. Register the MCP server with your local Claude

Find the full path to the `paperclip-mcp` binary first:

```bash
# Bash/Linux/macOS
which paperclip-mcp

# Windows PowerShell
Get-Command paperclip-mcp | Select-Object -ExpandProperty Source
```

### Cowork

Cowork → **Settings → Desarrollador (Developer) → Servidores MCP locales (Local MCP servers) → Editar configuración**.

The config file opens. Add the `paperclip` entry to `mcpServers` (keep the existing `preferences` block):

```json
{
  "preferences": { /* ... whatever's already here ... */ },
  "mcpServers": {
    "paperclip": {
      "command": "C:\\Users\\<you>\\AppData\\Roaming\\Python\\Python312\\Scripts\\paperclip-mcp.exe",
      "args": ["--transport", "stdio"],
      "env": {
        "PAPERCLIP_BASE_URL": "https://paperclip.<your-tailnet>.ts.net/api",
        "PAPERCLIP_API_KEY": "<your API key from Juan>",
        "PAPERCLIP_COMPANY_ID": "<koiomi company UUID>"
      }
    }
  }
}
```

Critical details:

- `PAPERCLIP_BASE_URL` (not `PAPERCLIP_URL`) — and it **must end in `/api`**.
- `--transport stdio` — without this, the MCP starts an HTTP server on port 9011 instead of speaking the stdio MCP protocol Cowork expects.
- Double-escape backslashes in the Windows path inside JSON.
- Treat `PAPERCLIP_API_KEY` like a password. Never paste it into chat, screenshots, or git commits.

Save, then **fully quit Cowork** (system tray → right-click → Quit, not just the close button) and reopen. Cowork only spawns MCP servers at startup.

### Claude Code

```bash
# macOS / Linux
mkdir -p ~/.claude && nano ~/.claude/mcp_servers.json

# Windows
notepad %USERPROFILE%\.claude\mcp_servers.json
```

Same JSON structure as Cowork above (without the `preferences` wrapper). Restart Claude Code.

### Claude Desktop

Same JSON structure, in `claude_desktop_config.json`:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Quit and reopen Claude Desktop.

## 4. Smoke test

First confirm Tailscale is connected:

```bash
tailscale status
```

You should see the `paperclip` device online. The Paperclip server listens on port 3100 inside the NAS, but Tailscale Serve fronts it on HTTPS at `:443`, so you only ever hit the `https://paperclip.<tailnet>.ts.net` URL.

Then in Claude, ask:

> What tools do you have from the paperclip MCP server?

You should see 21 tools including `list_issues`, `create_issue`, `checkout_issue`, `get_dashboard`, etc. Then test a read:

> Call `get_dashboard` on the paperclip MCP.

Should return JSON with company info, agent counts, and 14-day activity. Then test a write:

> Create a test Paperclip issue titled "MCP write test" and assign it to me.

If the write succeeds (no 403), you're fully wired up. Delete the test issue when done.

## Session-token fallback (read-only, not recommended)

If for some reason you don't have an API key, the MCP also supports session-token auth from your browser cookie. This is **read-only** for practical purposes — any write call returns `403 "Board mutation requires trusted browser origin"` because Paperclip gates writes on either an API key or a real browser session.

If you need to use the session-token fallback temporarily:

1. Open Paperclip in your browser → dev tools (F12) → **Application → Cookies → `https://paperclip.<tailnet>.ts.net`**.
2. Copy the value of `__Secure-paperclip-default.session_token`.
3. Apply the cookie-name patch from `docs/UPSTREAM_BUGS.md` issue #2 (the MCP hardcodes the wrong cookie name for self-hosted Paperclip).
4. Set `PAPERCLIP_SESSION_TOKEN=<value>` in your MCP env instead of `PAPERCLIP_API_KEY`.

This works for reading tickets but you won't be able to create or update anything. **Use the API-key path whenever possible.**

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Could not reach Paperclip at http://localhost:3100/api` | `PAPERCLIP_BASE_URL` env var not picked up | Check the variable name is exactly `PAPERCLIP_BASE_URL`, not `PAPERCLIP_URL`. Also confirm `/api` suffix. |
| `Missing required environment variable: PAPERCLIP_COMPANY_ID` | Company ID not set | Get it from step 2 and add to env block. |
| `HTTP 401 from Paperclip API: Unauthorized` | API key wrong, expired, or revoked | Ask Juan to mint you a new key from your agent's Configuration tab. Update env, restart Cowork. |
| `HTTP 403 from Paperclip API: Board mutation requires trusted browser origin` | You're using session-token auth instead of API key | Switch to `PAPERCLIP_API_KEY` (see step 3). Session tokens can read but not write. |
| No tools at all when asking Claude | MCP failed to start | Check Cowork's MCP log (varies by client). Most likely cause: wrong path to the binary, or JSON syntax error in the config. |
| Browser can't load the Paperclip URL | Tailscale not connected | Run `tailscale status` and reconnect. |

## Rotating your API key

API keys don't have an expiry, but you should rotate if:
- Your laptop is lost / stolen / sold
- The key was exposed (committed, screenshot, paste in chat)
- A teammate left and they had access

Rotation flow:

1. Tell Juan you need a key rotation.
2. Juan goes to **Agents → \<your agent\> → Configuration → API Keys → Create API Key** (new name like `mcp-rotated`).
3. Juan sends you the new key value via DM/password-manager-share.
4. You update `PAPERCLIP_API_KEY` in your MCP config.
5. Fully quit + reopen Cowork.
6. Juan **revokes the old key** in the same Configuration tab.

## Security reminders

- `paperclip-mcp` binds to `127.0.0.1` only. Don't expose it. It carries credentials.
- The API key is effectively your write permission. Don't share it in screenshots, screen-shares, commits, or chat.
- If you ever accidentally expose the key (committed it, pasted in chat, screenshot it), rotate **immediately** using the flow above.

## Day-to-day

Once installed, you don't think about the MCP. The conventions in `CLAUDE.md` describe what your Claude should do at the start of every session — it'll call into the MCP automatically.
