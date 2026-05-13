# Per-teammate `paperclip-mcp` setup

Every teammate runs this once on their own laptop. It's what lets your local Claude (Claude Code, Cowork, or Claude Desktop) call into the shared cloud Paperclip — list your tasks, claim them, update status, post comments — without leaving the editor.

## Mental model

Two layers, easy to conflate:

1. **Local Claude → cloud Paperclip (operator).** Your laptop runs `paperclip-mcp`, which exposes Paperclip's REST API as MCP tools. Your Claude calls those tools. This is what this guide sets up.
2. **Agents inside Paperclip → Anthropic (worker).** Agents you create inside Paperclip's UI need their own Anthropic API key, set per agent in Paperclip's admin. That's separate and is configured once you log in to the deployed instance.

## 1. Get your personal Paperclip API key

1. Log in to the shared Paperclip URL (see project README).
2. Open your user settings → **API keys** → create a new key.
3. Name it after your laptop (e.g. `juan-macbook`). Copy the secret somewhere safe — you won't see it again.

Never share this key, never commit it. It identifies you to Paperclip; everything your local Claude does will look like you did it.

## 2. Install `paperclip-mcp`

The MCP server is a small Python package. Use [`pipx`](https://pipx.pypa.io/) so it lives in its own isolated env:

```bash
pipx install paperclip-mcp
```

Or run it transiently with `uvx`:

```bash
uvx paperclip-mcp --help
```

Pick whichever your machine already has. Verify the install:

```bash
paperclip-mcp --version
```

> **Note.** There are a few community forks (`Wizarck/paperclip-mcp`, `darljed-paperclip-mcp`, `lutzkind-paperclip-mcp`). Tool names and env-var names may differ slightly. After install, run `paperclip-mcp --list-tools` (or equivalent) and confirm the tool names match the ones referenced in `CLAUDE.md`. If they don't, update `CLAUDE.md` rather than rewiring everything.

## 3. Register the MCP server with your local Claude

### Claude Code / Cowork

Add an entry to your Claude config (`~/.claude/mcp_servers.json` on macOS/Linux, or `%USERPROFILE%\.claude\mcp_servers.json` on Windows):

```json
{
  "mcpServers": {
    "paperclip": {
      "command": "paperclip-mcp",
      "args": [],
      "env": {
        "PAPERCLIP_URL": "https://paperclip.your-tailnet.ts.net",
        "PAPERCLIP_API_KEY": "pk_live_..."
      }
    }
  }
}
```

`PAPERCLIP_URL` is the Tailscale URL of the NAS-hosted instance. Tailscale must be running and connected on your laptop for `paperclip-mcp` to reach it.

Then restart Claude. In a new session, ask: *"List the tools you have from the paperclip MCP server."* You should see things like `list_issues`, `claim_issue`, `update_status`, `post_comment` (exact names depend on the fork).

### Claude Desktop

Edit `claude_desktop_config.json`:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "paperclip": {
      "command": "paperclip-mcp",
      "env": {
        "PAPERCLIP_URL": "https://paperclip.your-tailnet.ts.net",
        "PAPERCLIP_API_KEY": "pk_live_..."
      }
    }
  }
}
```

Quit and reopen Claude Desktop.

## 4. Smoke test

First confirm Tailscale is connected (`tailscale status` in a terminal — you should see the `paperclip` device online).

Then in Claude, run:

> List my open Paperclip tasks. Don't change anything.

You should get back a (possibly empty) list of tasks assigned to you, with IDs, titles, priorities, and status. If you instead see an auth error: re-check the URL (no trailing slash), the API key, and that your Paperclip account is actually invited to the company. If you see a connection error: re-check Tailscale is running.

## 5. Day-to-day

Once installed, you don't think about the MCP. The conventions in `CLAUDE.md` describe what your Claude should do at the start of every session — it'll call into the MCP automatically.

## Security reminders

- `paperclip-mcp` binds to `127.0.0.1` only. Don't expose it. It carries credentials.
- Rotate your API key in Paperclip if your laptop is lost/sold/compromised.
- Don't share `PAPERCLIP_API_KEY` in screenshots or screen-shares; it grants your full Paperclip permissions.
