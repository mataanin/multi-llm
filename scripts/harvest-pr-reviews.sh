#!/bin/bash
# Harvest review comments from GitHub PR and save as review output files.
# Extracts findings from Copilot, Cursor Bug Bot, and Codex reviews
# and formats them for review-analyze.sh.
#
# Usage: harvest-pr-reviews.sh <pr-number> <timestamp>

set -e

PR_NUMBER="${1:?Usage: harvest-pr-reviews.sh <pr-number> <timestamp>}"
TIMESTAMP="${2:?Usage: harvest-pr-reviews.sh <pr-number> <timestamp>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REVIEW_DIR="$REPO_ROOT/.claude/reviews"
mkdir -p "$REVIEW_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed" >&2
  exit 1
fi

# Verify PR exists
if ! gh pr view "$PR_NUMBER" --json number >/dev/null 2>&1; then
  echo "No PR #$PR_NUMBER found. Skipping harvest."
  exit 0
fi

# Get repo owner/name
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
if [ -z "$REPO" ]; then
  echo "ERROR: Could not determine repository" >&2
  exit 1
fi

echo "Harvesting PR #$PR_NUMBER reviews..."

# Fetch all reviews on the PR
REVIEWS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --paginate 2>/dev/null || echo '[]')

# Fetch all review comments (line-level)
COMMENTS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate 2>/dev/null || echo '[]')

# Map bot usernames to tool names
# copilot[bot] -> copilot-gh, cursor[bot] -> cursor-gh, codex-bot[bot] -> codex-gh
harvest_bot_review() {
  local bot_login="$1"
  local tool_name="$2"
  local output_file="$REVIEW_DIR/${TIMESTAMP}-${tool_name}.txt"

  # Check if we already harvested this (idempotency)
  if [ -f "$output_file" ]; then
    echo "  $tool_name: already harvested (skipping)"
    return
  fi

  # Get review bodies from this bot
  local review_bodies
  review_bodies=$(echo "$REVIEWS" | jq -r --arg login "$bot_login" \
    '[.[] | select(.user.login == $login and .body != null and .body != "") | .body] | join("\n\n---\n\n")')

  # Get line-level comments from this bot
  local line_comments
  line_comments=$(echo "$COMMENTS" | jq -r --arg login "$bot_login" \
    '[.[] | select(.user.login == $login) | "File: `\(.path)\(if (.line // .original_line) != null then ":\(.line // .original_line)" else "" end)`\n\(.body)"] | join("\n\n")')

  # If no content from this bot, skip
  if [ -z "$review_bodies" ] && [ -z "$line_comments" ]; then
    return
  fi

  echo "  $tool_name: found review content"

  # Count findings from line comments
  local finding_count
  finding_count=$(echo "$COMMENTS" | jq --arg login "$bot_login" \
    '[.[] | select(.user.login == $login)] | length')

  # Format as standard review output
  {
    echo "### Code Review Results"
    echo ""
    if [ "$finding_count" -gt 0 ]; then
      echo "Found $finding_count issues:"
      echo ""
      # Format each line comment as a numbered finding
      echo "$COMMENTS" | jq -r --arg login "$bot_login" '
        [.[] | select(.user.login == $login)] | to_entries[] |
        "\(.key + 1). \(.value.body | split("\n") | first)
   File: `\(.value.path)\(if (.value.line // .value.original_line) != null then ":\(.value.line // .value.original_line)" else "" end)`
   Confidence: 75
   \(.value.body)"
      '
    else
      echo "No issues found."
    fi
    echo ""
    if [ -n "$review_bodies" ]; then
      echo "---"
      echo "## Review Summary"
      echo ""
      echo "$review_bodies"
    fi
  } > "$output_file"
}

# Harvest from known bots
harvest_bot_review "copilot[bot]" "copilot-gh"
harvest_bot_review "cursor[bot]" "cursor-gh"
harvest_bot_review "codex-bot[bot]" "codex-gh"

# Also check for any other bot reviewers we haven't seen
OTHER_BOTS=$(echo "$REVIEWS" | jq -r '[.[] | select(.user.login | test("\\[bot\\]$")) | .user.login] | unique | .[] | select(. != "copilot[bot]" and . != "cursor[bot]" and . != "codex-bot[bot]")' 2>/dev/null || true)
if [ -n "$OTHER_BOTS" ]; then
  echo "  Other bot reviewers found: $OTHER_BOTS"
fi

echo "Harvest complete."
