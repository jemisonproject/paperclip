#!/usr/bin/env bash
# QA Agent — uses Claude Code directly (first-party, no extra credits)
#
# Polls Paperclip for `in_review` tickets, uses Claude Code + Playwright
# to browse the web app and verify changes, posts results back.
#
# Usage:
#   ./scripts/qa-agent/run.sh              # single run (check once)
#   ./scripts/qa-agent/run.sh --loop 1800  # poll every 30 minutes
#
# Prerequisites:
#   - Claude Code authenticated (`claude login`)
#   - Playwright + Chromium installed (`npx playwright install chromium`)
#   - QA Docker stack running (web at localhost:7070)
#   - PAPERCLIP_API_KEY set in environment or in .env.qa-agent

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$SCRIPT_DIR"

# Load config
if [ -f "$AGENT_DIR/.env" ]; then
  source "$AGENT_DIR/.env"
fi

# Required config
PAPERCLIP_URL="${PAPERCLIP_URL:-https://paperclip.tailc002ee.ts.net}"
PAPERCLIP_API_KEY="${PAPERCLIP_API_KEY:?Set PAPERCLIP_API_KEY in scripts/qa-agent/.env}"
COMPANY_ID="${COMPANY_ID:-10c76edd-839e-4950-aec3-e39d058a315a}"
QA_WEB_URL="${QA_WEB_URL:-http://192.168.30.104:7070}"
QA_AGENT_ID="${QA_AGENT_ID:-470a0017-f841-4838-924e-b1b1e4af318b}"
ENGINEERING_AGENT_ID="${ENGINEERING_AGENT_ID:-4d671d9d-fffe-4358-830c-7d9bd764f80a}"

# Colors
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[0;34m%s\033[0m\n' "$*"; }
dim()   { printf '\033[0;90m%s\033[0m\n' "$*"; }

# Paperclip API helper
paperclip_api() {
  local method="$1" endpoint="$2"
  shift 2
  curl -sf \
    -X "$method" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    "$@" \
    "$PAPERCLIP_URL/api/companies/$COMPANY_ID$endpoint"
}

# Get in_review issues assigned to QA agent
get_qa_tickets() {
  # Try different param names since the API may vary
  local result
  result=$(paperclip_api GET "/issues?status=in_review&assignee_agent_id=$QA_AGENT_ID&limit=50" 2>/dev/null)
  if [ -z "$result" ] || [ "$result" = "[]" ]; then
    # Fallback: get all in_review and filter locally
    result=$(paperclip_api GET "/issues?status=in_review&limit=50" 2>/dev/null | \
      jq "[.[] | select(.assigneeAgentId == \"$QA_AGENT_ID\")]" 2>/dev/null)
  fi
  echo "${result:-[]}"
}

# Post a comment on an issue (uses /api/issues/ endpoint, not /api/companies/)
post_comment() {
  local issue_id="$1" body="$2"
  curl -sf \
    -X POST \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg b "$body" '{body: $b}')" \
    "$PAPERCLIP_URL/api/issues/$issue_id/comments" >/dev/null 2>&1
}

# Update issue status and optionally reassign
# When QA fails/blocks a ticket, reassign back to engineering so the agent picks it up.
# When QA passes (done) or skips (done), keep assigned to QA (no reassign needed).
update_status() {
  local issue_id="$1" status="$2"
  local payload

  # If failing back (todo/blocked), reassign to engineering agent
  if [ "$status" = "todo" ] || [ "$status" = "blocked" ]; then
    payload=$(jq -n --arg s "$status" --arg a "$ENGINEERING_AGENT_ID" \
      '{status: $s, assigneeAgentId: $a}')
  else
    payload=$(jq -n --arg s "$status" '{status: $s}')
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$PAPERCLIP_URL/api/issues/$issue_id")
  if [ "$http_code" != "200" ]; then
    red "   ⚠ Failed to update $issue_id to $status (HTTP $http_code)"
    red "     Ticket may not be assigned to QA agent. Run cleanup-qa-results.sh"
  fi
}

# Run QA check on a single ticket using Claude Code
run_qa_check() {
  local issue_id="$1"
  local title="$2"
  local description="$3"
  local identifier="$4"

  blue "── QA checking: $identifier — $title"

  # Build the prompt for Claude Code
  local prompt="You are a QA engineer testing a web application. You test what users see and experience in the browser.

TICKET:
- Title: $title
- Description: $description

FIRST, decide if this ticket has ANY user-facing impact you can verify in a browser.

IMPORTANT — when to SKIP vs TEST:
- ONLY skip if the ticket is purely infrastructure with zero UI impact: database migrations, CI/CD config, README edits, pure code refactors that change no behavior, JWT/auth guard internals.
- If the ticket mentions a URL route (like /pro/clientes, /org/sitio, /admin/usuarios), it IS testable — navigate there.
- If the ticket describes a bug that affects what users see (search broken, forms not submitting, data not displaying), it IS testable — even if the fix is in backend code.
- If the ticket mentions visual changes (colors, layout, design, formatting), it IS testable.
- If the ticket has both API and FE components (title says [API+FE]), it IS testable via the frontend.
- When in doubt, TEST — don't skip.

If the ticket is genuinely NOT testable (no UI impact at all):
Respond with:
QA_RESULT: SKIP
<one sentence explaining why there is no user-facing change to verify>

If the ticket IS testable, do this:
1. Use the Playwright MCP browser tools to navigate to the relevant pages at $QA_WEB_URL
2. Use browser_snapshot to see the page content (accessibility tree)
3. Interact with the app as a real user would — click buttons, fill forms, navigate
4. If you need to log in, use these test credentials:
   - Admin: email=superadmin@koiomi.com password=TestPassword123!
   - CEO: email=ceo@test-organization.com password=TestPassword123!
   - Regular user: email=user@test.com password=TestPassword123!
   Login page is at $QA_WEB_URL/users/sign_in
5. Check for: pages loading correctly, forms working, data displaying, no errors
6. Use browser_console_messages to check for JavaScript errors

Then respond with EXACTLY one of:

QA_RESULT: PASS
<what you tested and verified in 2-3 sentences>

QA_RESULT: FAIL
<what's broken and how to reproduce in 2-3 sentences>"

  # Run Claude Code in print mode with the Playwright MCP
  local result
  result=$(cd "$AGENT_DIR" && claude -p "$prompt" --allowedTools "mcp__playwright__*" 2>/dev/null) || {
    red "   Claude Code failed for $identifier"
    post_comment "$issue_id" "QA agent encountered an error running Claude Code. Manual review needed."
    update_status "$issue_id" "blocked"
    return 1
  }

  # Parse result
  if echo "$result" | grep -q "QA_RESULT: SKIP"; then
    dim "   SKIPPED: $identifier (not visually testable)"
    post_comment "$issue_id" "**QA SKIPPED** — This ticket describes a backend/infrastructure change with no user-facing UI to verify. Marking as done (no visual regression possible).

---
*Automated QA by Claude Code agent*"
    update_status "$issue_id" "done"

  elif echo "$result" | grep -q "QA_RESULT: PASS"; then
    green "   PASSED: $identifier"
    post_comment "$issue_id" "$(cat <<EOF
**QA PASSED** ✓

$result

---
*Automated QA by Claude Code agent*
EOF
)"
    update_status "$issue_id" "done"

  elif echo "$result" | grep -q "QA_RESULT: FAIL"; then
    red "   FAILED: $identifier"
    post_comment "$issue_id" "$(cat <<EOF
**QA FAILED** ✗

$result

---
*Automated QA by Claude Code agent*
EOF
)"
    update_status "$issue_id" "todo"

  else
    dim "   Inconclusive: $identifier"
    post_comment "$issue_id" "$(cat <<EOF
**QA INCONCLUSIVE**

The agent ran but couldn't determine a clear pass/fail:

$result

---
*Automated QA by Claude Code agent — manual review recommended*
EOF
)"
    update_status "$issue_id" "blocked"
  fi
}

# Main: check for tickets and process them
check_tickets() {
  blue "═══ QA Agent checking for in_review tickets ═══"
  dim "   $(date)"

  local tickets
  tickets=$(get_qa_tickets)

  local count
  count=$(echo "$tickets" | jq 'length' 2>/dev/null || echo "0")

  if [ "$count" = "0" ] || [ "$count" = "" ]; then
    dim "   No in_review tickets found. Nothing to do."
    return 0
  fi

  green "   Found $count ticket(s) to review"

  local identifiers
  identifiers=$(echo "$tickets" | jq -r '.[].identifier')

  for identifier in $identifiers; do
    local title description
    title=$(echo "$tickets" | jq -r ".[] | select(.identifier == \"$identifier\") | .title")
    description=$(echo "$tickets" | jq -r ".[] | select(.identifier == \"$identifier\") | .description // \"No description\"")

    run_qa_check "$identifier" "$title" "$description" "$identifier"
  done

  green "═══ QA Agent done ═══"
}

# Entry point
if [ "${1:-}" = "--loop" ]; then
  interval="${2:-1800}"
  blue "QA Agent starting in loop mode (every ${interval}s)"
  while true; do
    check_tickets || true
    dim "   Sleeping ${interval}s..."
    sleep "$interval"
  done
else
  check_tickets
fi
