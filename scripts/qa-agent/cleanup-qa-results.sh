#!/usr/bin/env bash
# Cleanup script for QA run results
# Run from the qa-agent directory on the NAS after a QA run
# Usage: ./cleanup-qa-results.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config (same .env as the QA agent)
if [ -f "$SCRIPT_DIR/.env" ]; then
  source "$SCRIPT_DIR/.env"
fi

PAPERCLIP_URL="${PAPERCLIP_URL:-https://paperclip.tailc002ee.ts.net}"
PAPERCLIP_API_KEY="${PAPERCLIP_API_KEY:?Set PAPERCLIP_API_KEY in .env}"

# Agent IDs
CLAUDIO_JD="4d671d9d-fffe-4358-830c-7d9bd764f80a"
QA_AGENT="21c5f0bc-c738-4434-82c8-78764111404e"

# Colors
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[0;34m%s\033[0m\n' "$*"; }
dim()   { printf '\033[0;90m%s\033[0m\n' "$*"; }

# API helpers
update_issue() {
  local identifier="$1"
  shift
  curl -sf \
    -X PATCH \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$@" \
    "$PAPERCLIP_URL/api/issues/$identifier" 2>&1
}

post_comment() {
  local identifier="$1" body="$2"
  curl -sf \
    -X POST \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg b "$body" '{body: $b}')" \
    "$PAPERCLIP_URL/api/issues/$identifier/comments" 2>&1
}

blue "═══ QA Results Cleanup ═══"
dim "   $(date)"
echo ""

# ──────────────────────────────────────────────
# 1. WRONGLY SKIPPED: Fix merged, needs re-test
# ──────────────────────────────────────────────
blue "── Step 1: Fix wrongly-skipped tickets (set to in_review, assign to QA) ──"

for ticket in KOI-156 KOI-122; do
  blue "   Updating $ticket → in_review, assigned to QA agent"
  result=$(update_issue "$ticket" "$(jq -n \
    --arg status "in_review" \
    --arg agent "$QA_AGENT" \
    '{status: $status, assigneeAgentId: $agent}')")
  if [ $? -eq 0 ]; then
    green "   ✓ $ticket updated"
  else
    red "   ✗ $ticket failed: $result"
  fi

  post_comment "$ticket" "**QA Classification Error:** The automated QA agent incorrectly skipped this ticket as 'not visually testable.' This change HAS user-visible impact and needs visual verification. Reassigning to QA for proper testing." >/dev/null 2>&1
done

echo ""

# ──────────────────────────────────────────────
# 2. FAILED: Set to todo, assign to Claudio (JD)
# ──────────────────────────────────────────────
blue "── Step 2: Set failed tickets to todo for engineering ──"

# These all failed QA and need engineering fixes
FAILED_TICKETS="KOI-139 KOI-48 KOI-140 KOI-94 KOI-124 KOI-161 KOI-72"

for ticket in $FAILED_TICKETS; do
  blue "   Updating $ticket → todo, assigned to Claudio (JD)"
  result=$(update_issue "$ticket" "$(jq -n \
    --arg status "todo" \
    --arg agent "$CLAUDIO_JD" \
    '{status: $status, assigneeAgentId: $agent}')")
  if [ $? -eq 0 ]; then
    green "   ✓ $ticket set to todo"
  else
    red "   ✗ $ticket failed: $result"
  fi

  post_comment "$ticket" "**QA FAILED** — Setting back to todo for engineering to fix. Check the QA agent's previous comment for details on what's broken." >/dev/null 2>&1
done

echo ""

# ──────────────────────────────────────────────
# 3. NOT BUILT YET: Set to todo for engineering
# ──────────────────────────────────────────────
blue "── Step 3: Set unbuilt features to todo ──"

for ticket in KOI-26 KOI-126; do
  blue "   Updating $ticket → todo, assigned to Claudio (JD)"
  result=$(update_issue "$ticket" "$(jq -n \
    --arg status "todo" \
    --arg agent "$CLAUDIO_JD" \
    '{status: $status, assigneeAgentId: $agent}')")
  if [ $? -eq 0 ]; then
    green "   ✓ $ticket set to todo"
  else
    red "   ✗ $ticket failed: $result"
  fi

  post_comment "$ticket" "**Not built yet** — This feature hasn't been implemented. Setting to todo for engineering to build from scratch. Branch from paperclip-features." >/dev/null 2>&1
done

echo ""

# ──────────────────────────────────────────────
# 4. CORRECT SKIPS: Set to done
# ──────────────────────────────────────────────
blue "── Step 4: Close correctly-skipped meta/infra tickets ──"

for ticket in KOI-170 KOI-97; do
  blue "   Updating $ticket → done"
  result=$(update_issue "$ticket" "$(jq -n '{status: "done"}')")
  if [ $? -eq 0 ]; then
    green "   ✓ $ticket done"
  else
    red "   ✗ $ticket failed: $result"
  fi
done

echo ""

# ──────────────────────────────────────────────
# 5. INCONCLUSIVE: Set to todo for re-review
# ──────────────────────────────────────────────
blue "── Step 5: Handle inconclusive ticket ──"

blue "   Updating KOI-75 → todo"
result=$(update_issue "KOI-75" "$(jq -n \
  --arg status "todo" \
  --arg agent "$CLAUDIO_JD" \
  '{status: $status, assigneeAgentId: $agent}')")
if [ $? -eq 0 ]; then
  green "   ✓ KOI-75 set to todo"
else
  red "   ✗ KOI-75 failed: $result"
fi

post_comment "KOI-75" "**QA Inconclusive** — The QA agent couldn't determine a clear pass/fail for Pro/Config Licencias. Needs manual investigation or a re-run with more specific test instructions." >/dev/null 2>&1

echo ""
green "═══ Cleanup complete ═══"
echo ""
dim "Summary:"
dim "  - KOI-156, KOI-122: → in_review (QA agent) for re-test"
dim "  - KOI-139, KOI-48, KOI-140, KOI-94, KOI-124, KOI-161, KOI-72: → todo (engineering fix)"
dim "  - KOI-26, KOI-126: → todo (not built, needs implementation)"
dim "  - KOI-170, KOI-97: → done (meta/infra, correctly skipped)"
dim "  - KOI-75: → todo (inconclusive, needs re-review)"
echo ""
dim "Next: run ./run.sh again to re-test KOI-156 and KOI-122"
