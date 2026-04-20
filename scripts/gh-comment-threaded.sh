#!/bin/bash
# GitHub PR Comment Threading Helper
# Usage: gh-comment-threaded.sh <pr_number> <comment_body> [reply_to_comment_id]
#
# If reply_to_comment_id is provided, posts as a threaded reply.
# Otherwise, posts as a new top-level comment.

set -e

PR_NUMBER="$1"
COMMENT_BODY="$2"
REPLY_TO_ID="${3:-}"

if [ -z "$PR_NUMBER" ] || [ -z "$COMMENT_BODY" ]; then
  echo "Usage: gh-comment-threaded.sh <pr_number> <comment_body> [reply_to_comment_id]"
  exit 1
fi

# Get repo information
REPO_INFO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
REPO=$(echo "$REPO_INFO" | cut -d'/' -f2)

if [ -n "$REPLY_TO_ID" ]; then
  # Post as threaded reply to existing comment
  echo "Posting threaded reply to comment ID $REPLY_TO_ID on PR #$PR_NUMBER..."

  # Use GitHub API to post threaded reply
  gh api \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$REPLY_TO_ID/replies" \
    -f body="$COMMENT_BODY"

  echo "✅ Threaded reply posted successfully"
else
  # Post as new top-level comment
  echo "Posting new comment on PR #$PR_NUMBER..."
  gh pr comment "$PR_NUMBER" --body "$COMMENT_BODY"
  echo "✅ Comment posted successfully"
fi
