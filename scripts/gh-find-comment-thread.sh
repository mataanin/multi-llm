#!/bin/bash
# Find existing comment thread by searching for a pattern
# Usage: gh-find-comment-thread.sh <pr_number> <search_pattern>
#
# Returns the comment ID of the first matching TOP-LEVEL comment
# (used for threading replies)

set -e

PR_NUMBER="$1"
SEARCH_PATTERN="$2"

if [ -z "$PR_NUMBER" ] || [ -z "$SEARCH_PATTERN" ]; then
  echo "Usage: gh-find-comment-thread.sh <pr_number> <search_pattern>" >&2
  exit 1
fi

# Get repo information
REPO_INFO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
REPO=$(echo "$REPO_INFO" | cut -d'/' -f2)

# Fetch all review comments and find matching top-level comment
# Pipe to jq separately to use --arg for safe variable passing (prevents injection/escaping issues)
COMMENT_ID=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
  | jq --arg pattern "$SEARCH_PATTERN" -r '.[] | select(.in_reply_to_id == null) | select(.body | contains($pattern)) | .id' \
  | head -1)

if [ -n "$COMMENT_ID" ]; then
  echo "$COMMENT_ID"
  exit 0
else
  # No matching thread found
  exit 1
fi
