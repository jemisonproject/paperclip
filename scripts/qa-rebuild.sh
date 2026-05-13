#!/usr/bin/env bash
# qa-rebuild.sh — pull latest paperclip-features and rebuild the QA environment.
#
# Run from anywhere. The script figures out repo paths relative to the
# paperclip directory (assumes api/ and web/ are siblings).
#
# Usage:
#   ./scripts/qa-rebuild.sh          # full rebuild
#   ./scripts/qa-rebuild.sh --quick  # skip git pull, just rebuild containers
#
# Environment overrides:
#   QA_API_PATH   path to the api repo   (default: ../api)
#   QA_WEB_PATH   path to the web repo   (default: ../web)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAPERCLIP_DIR="$(dirname "$SCRIPT_DIR")"
API_DIR="${QA_API_PATH:-$PAPERCLIP_DIR/../api}"
WEB_DIR="${QA_WEB_PATH:-$PAPERCLIP_DIR/../web}"
BRANCH="paperclip-features"

red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[0;34m%s\033[0m\n' "$*"; }

pull_branch() {
  local repo_dir="$1"
  local repo_name="$(basename "$repo_dir")"

  blue "── Updating $repo_name → $BRANCH"
  cd "$repo_dir"

  git fetch origin "$BRANCH" 2>/dev/null || {
    red "   Branch $BRANCH does not exist in $repo_name. Create it first:"
    red "   git branch $BRANCH origin/main && git push origin $BRANCH"
    return 1
  }

  # If we're on a different branch, switch
  current=$(git branch --show-current)
  if [ "$current" != "$BRANCH" ]; then
    blue "   Switching from $current → $BRANCH"
    git checkout "$BRANCH"
  fi

  git pull --ff-only origin "$BRANCH"
  green "   $repo_name is at $(git log --oneline -1)"
}

# ── Step 1: Pull latest code (unless --quick)
if [ "${1:-}" != "--quick" ]; then
  blue "═══ Pulling latest $BRANCH ═══"
  pull_branch "$API_DIR"
  pull_branch "$WEB_DIR"
  echo
fi

# ── Step 2: Rebuild and restart containers
blue "═══ Rebuilding QA containers ═══"
cd "$PAPERCLIP_DIR"

docker compose -f docker-compose.qa.yml down --remove-orphans 2>/dev/null || true
docker compose -f docker-compose.qa.yml up --build -d

echo
green "═══ QA environment is up ═══"
green "Web app:  http://localhost:7070"
green "API:      http://localhost:3000 (internal, via qa-api container)"
green ""
green "Rebuild logs: docker compose -f docker-compose.qa.yml logs -f"
