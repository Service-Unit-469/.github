#!/usr/bin/env bash
#
# Copy workflows/dependabot-auto-merge.yml to every repository in the organization.
# Requires: gh CLI (authenticated), jq
#
# Usage: ./copy-dependabot-workflow.sh <org>
# Example: ./copy-dependabot-workflow.sh Service-Unit-469

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_SOURCE="${SCRIPT_DIR}/../workflows/dependabot-auto-merge.yml"
WORKFLOW_PATH=".github/workflows/dependabot-auto-merge.yml"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <org>"
  echo "Example: $0 Service-Unit-469"
  exit 1
fi

ORG="$1"

if ! command -v gh &> /dev/null; then
  echo "Error: gh CLI is required. Install from https://cli.github.com/"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

# Get all repos (exclude archived - they're read-only)
REPOS=$(gh repo list "$ORG" --limit 1000 --no-archived --json nameWithOwner -q '.[].nameWithOwner')

SUCCESS=0
SKIPPED=0
FAILED=0

while IFS= read -r REPO; do
  [[ -z "$REPO" ]] && continue

  printf "%-50s " "$REPO"

  # Base64 encode (omit newlines for API compatibility)
  CONTENT_B64=$(base64 < "$WORKFLOW_SOURCE" | tr -d '\n')

  # Check if file exists to get SHA for update
  EXISTING=$(gh api "repos/$REPO/contents/$WORKFLOW_PATH" 2>/dev/null | jq -r '.sha // empty' || true)

  if [[ -n "$EXISTING" ]]; then
    # Update existing file
    RESPONSE=$(gh api -X PUT "repos/$REPO/contents/$WORKFLOW_PATH" \
      -f message="chore: update dependabot-auto-merge workflow" \
      -f content="$CONTENT_B64" \
      -f sha="$EXISTING" 2>&1) || true
  else
    # Create new file (may need to create .github/workflows first)
    RESPONSE=$(gh api -X PUT "repos/$REPO/contents/$WORKFLOW_PATH" \
      -f message="chore: add dependabot-auto-merge workflow" \
      -f content="$CONTENT_B64" 2>&1) || true
  fi

  if echo "$RESPONSE" | jq -e '.content.sha' &>/dev/null; then
    echo "✓"
    SUCCESS=$((SUCCESS + 1))
  elif echo "$RESPONSE" | jq -e '.message' 2>/dev/null | grep -qiE "not found|permission|denied|archived|read-only"; then
    echo "⊘ (no write access)"
    SKIPPED=$((SKIPPED + 1))
  else
    echo "✗"
    echo "  $RESPONSE" | head -c 200
    echo ""
    FAILED=$((FAILED + 1))
  fi

done <<< "$REPOS"

echo ""
echo "Done: $SUCCESS updated/added, $SKIPPED skipped, $FAILED failed"
