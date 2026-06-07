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

# Post a comment on an issue
post_comment() {
  local issue_id="$1" body="$2"
  paperclip_api POST "/issues/$issue_id/comments" \
    -d "$(jq -n --arg b "$body" '{body: $b}')" >/dev/null 2>&1
}

# Update issue status
update_status() {
  local issue_id="$1" status="$2"
  paperclip_api PATCH "/issues/$issue_id" \
    -d "$(jq -n --arg s "$status" '{status: $s}')" >/dev/null 2>&1
}

# Run QA check on a single ticket using Claude Code
run_qa_check() {
  local issue_id="$1"
  local title="$2"
  local description="$3"
  local identifier="$4"

  blue "── QA checking: $identifier — $title"

  # Build the prompt for Claude Code
  local prompt="You are a QA engineer testing a web application. You don't know or care about the code — you test what users see and experience.

TICKET:
- Title: $title
- Description: $description

FIRST, decide if this ticket describes something you can verify by using the app in a browser. Examples of testable: login page works, search returns results, booking flow completes, UI shows correct data. Examples of NOT testable: backend API scaffold, database migration, JWT guard implementation, code refactor with no UI change.

If the ticket is NOT visually testable (backend-only, infrastructure, code-level):
Respond with:
QA_RESULT: SKIP
This is a backend/infrastructure change with no user-facing impact to verify visually.

If the ticket IS visually testable, do this:
1. Use the Playwright MCP browser tools to navigate to the relevant pages at $QA_WEB_URL
2. Use browser_snapshot to see the page content (accessibility tree)
3. Interact with the app as a real user would — click buttons, fill forms, navigate
4. Check for: pages loading correctly, forms working, data displaying, no errors
5. Use browser_console_messages to check for JavaScript errors

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

  echo "$tickets" | jq -c '.[]' | while read -r ticket; do
    local id title description identifier
    id=$(echo "$ticket" | jq -r '.id')
    title=$(echo "$ticket" | jq -r '.title')
    description=$(echo "$ticket" | jq -r '.description // "No description"')
    identifier=$(echo "$ticket" | jq -r '.identifier // "unknown"')

    run_qa_check "$id" "$title" "$description" "$identifier"
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
