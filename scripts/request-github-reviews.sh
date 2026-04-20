#!/bin/bash
# Request reviews from GitHub Copilot, Cursor Bug Bot, and Codex on a PR.
#
# Usage: request-github-reviews.sh <pr-number>
#
# NOTE: This script is for use from bash/CI. When running inside Claude Code,
# prefer the MCP tool `mcp__github__request_copilot_review` directly.

set -e

PR_NUMBER="${1:?Usage: request-github-reviews.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed" >&2
  exit 1
fi

REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "empowersleep/dream")
OWNER="${REPO_FULL%%/*}"
REPO="${REPO_FULL##*/}"

echo "Requesting reviews on PR #$PR_NUMBER..."

# Request from Copilot via GitHub API
# gh pr edit --add-reviewer does NOT work for Copilot (it's a GitHub App, not a user).
# Use the REST API endpoint instead.
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/requested_reviewers" \
  -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]" 2>/dev/null \
  && echo "  Requested: Copilot" \
  || echo "  Copilot: skipped (may not be available or already reviewed)"

# Fetch all comment bodies once for idempotency checks
ALL_COMMENTS=$(gh pr view "$PR_NUMBER" --comments --json comments --jq '[.comments[].body]' 2>/dev/null || echo "[]")

# Request from Cursor Bug Bot (triggered via PR comment, not --add-reviewer)
if echo "$ALL_COMMENTS" | grep -q "@cursor review"; then
  echo "  Cursor Bug Bot: already requested"
else
  gh pr comment "$PR_NUMBER" --body "@cursor review this PR" 2>/dev/null && echo "  Requested: Cursor Bug Bot" || echo "  Cursor Bug Bot: skipped (may not be available)"
fi

# Request from Codex (triggered via PR comment, not --add-reviewer)
if echo "$ALL_COMMENTS" | grep -q "@codex review"; then
  echo "  Codex: already requested"
else
  gh pr comment "$PR_NUMBER" --body "@codex review this PR" 2>/dev/null && echo "  Requested: Codex" || echo "  Codex: skipped (may not be available)"
fi

echo "Done requesting reviews on PR #$PR_NUMBER"
