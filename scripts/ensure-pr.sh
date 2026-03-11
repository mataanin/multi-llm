#!/bin/bash
# Ensure a PR exists for the current branch. Creates one if needed.
# Outputs the PR number.
#
# Usage: ensure-pr.sh

set -e

BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ]; then
  echo "ERROR: Must be on a feature branch (not main or detached HEAD)" >&2
  exit 1
fi

# Push latest changes (suppress stdout — it would contaminate captured PR number)
if ! git push -u origin "$BRANCH" >/dev/null 2>&1; then
  echo "WARNING: git push failed (continuing — PR may be based on stale commits)" >&2
fi

# Check if PR already exists
PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || true)
if [ -n "$PR_NUMBER" ]; then
  echo "$PR_NUMBER"
  exit 0
fi

# Create a minimal PR, then read back the number
TITLE=$(git log -1 --format=%s)
if ! gh pr create --title "$TITLE" --body "WIP - automated PR for review" >/dev/null 2>/dev/null; then
  echo "ERROR: Failed to create PR" >&2
  exit 1
fi

PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null)
if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: PR created but could not read PR number" >&2
  exit 1
fi

echo "$PR_NUMBER"
