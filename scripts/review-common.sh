#!/bin/bash
# Shared logic for code review scripts (Claude, Cursor, Codex, Gemini).
# Source this file from each review script after setting REVIEW_NAME,
# REVIEW_CLI_CHECK, REVIEW_INSTALL_HINT, and REVIEW_PROMPT_FILE.
#
# After sourcing, $FULL_PROMPT is set and ready to pass to the CLI.

set -e

# --- Error logging for 3rd-party LLM failures ---
SCRIPT_DIR_COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_COMMON/log-common.sh"
LLM_TOOL_NAME="$REVIEW_NAME"
LLM_MODE="review"
LLM_CLI_CHECK="$REVIEW_CLI_CHECK"
LLM_INSTALL_HINT="$REVIEW_INSTALL_HINT"

# Review output capture directory
REVIEW_OUTPUT_DIR=".claude/reviews"
mkdir -p "$REVIEW_OUTPUT_DIR"

# Use shared timestamp from parent process (for parallel runs), or generate one
REVIEW_TIMESTAMP="${REVIEW_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
REVIEW_OUTPUT_FILE="$REVIEW_OUTPUT_DIR/${REVIEW_TIMESTAMP}-$(echo "$REVIEW_NAME" | tr '[:upper:]' '[:lower:]').txt"
export REVIEW_TIMESTAMP REVIEW_OUTPUT_FILE

# Parse arguments
CHANGE_DESCRIPTION=""
COMMIT_ARG=""
TEST_FLAG=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --test)
      TEST_FLAG=true
      shift
      ;;
    --description)
      CHANGE_DESCRIPTION="$2"
      shift 2
      ;;
    --description=*)
      CHANGE_DESCRIPTION="${1#*=}"
      shift
      ;;
    *)
      COMMIT_ARG="$1"
      shift
      ;;
  esac
done

# Handle --test flag
if [ "$TEST_FLAG" = true ]; then
  if command -v "$REVIEW_CLI_CHECK" >/dev/null 2>&1; then
    echo "✓ $REVIEW_CLI_CHECK command found"
    exit 0
  else
    echo "✗ $REVIEW_CLI_CHECK command not found in PATH"
    echo "  Install with: $REVIEW_INSTALL_HINT"
    exit 1
  fi
fi

BRANCH=$(_get_current_branch)

if [ ! -f "$REVIEW_PROMPT_FILE" ]; then
  echo "Error: $REVIEW_PROMPT_FILE not found"
  exit 1
fi

# Build FULL_PROMPT based on commit/range/branch context
if [ -n "$COMMIT_ARG" ]; then
  if [[ "$COMMIT_ARG" == *".."* ]]; then
    START_COMMIT="${COMMIT_ARG%%..*}"
    END_COMMIT="${COMMIT_ARG##*..}"

    if ! git rev-parse --verify "$START_COMMIT" >/dev/null 2>&1; then
      echo "Error: Invalid start commit: $START_COMMIT"
      exit 1
    fi
    if ! git rev-parse --verify "$END_COMMIT" >/dev/null 2>&1; then
      echo "Error: Invalid end commit: $END_COMMIT"
      exit 1
    fi

    START_HASH=$(git rev-parse "$START_COMMIT")
    END_HASH=$(git rev-parse "$END_COMMIT")

    echo "Reviewing commit range: $START_HASH..$END_HASH"
    PROMPT_CONTENT=$(cat "$REVIEW_PROMPT_FILE")
    if [ -n "$CHANGE_DESCRIPTION" ]; then
      FULL_PROMPT=$(printf "Run for commits %s..%s\n\n## Change Description\n\n%s\n\n%s" "$START_HASH" "$END_HASH" "$CHANGE_DESCRIPTION" "$PROMPT_CONTENT")
    else
      FULL_PROMPT=$(printf "Run for commits %s..%s\n\n%s" "$START_HASH" "$END_HASH" "$PROMPT_CONTENT")
    fi
  else
    COMMIT_HASH="$COMMIT_ARG"
    if ! git rev-parse --verify "$COMMIT_HASH" >/dev/null 2>&1; then
      echo "Error: Invalid commit hash: $COMMIT_HASH"
      exit 1
    fi
    echo "Reviewing specified commit: $COMMIT_HASH"
    PROMPT_CONTENT=$(cat "$REVIEW_PROMPT_FILE")
    if [ -n "$CHANGE_DESCRIPTION" ]; then
      FULL_PROMPT=$(printf "Run for %s commit\n\n## Change Description\n\n%s\n\n%s" "$COMMIT_HASH" "$CHANGE_DESCRIPTION" "$PROMPT_CONTENT")
    else
      FULL_PROMPT=$(printf "Run for %s commit\n\n%s" "$COMMIT_HASH" "$PROMPT_CONTENT")
    fi
  fi
else
  echo "Running $REVIEW_NAME code review..."
  echo "Branch: $BRANCH"
  echo ""

  PROMPT_CONTENT=$(cat "$REVIEW_PROMPT_FILE")

  if [ "$BRANCH" = "main" ]; then
    COMMIT_HASH=$(git rev-parse HEAD)
    echo "On main branch, reviewing commit: $COMMIT_HASH"
    if [ -n "$CHANGE_DESCRIPTION" ]; then
      FULL_PROMPT=$(printf "Run for %s commit\n\n## Change Description\n\n%s\n\n%s" "$COMMIT_HASH" "$CHANGE_DESCRIPTION" "$PROMPT_CONTENT")
    else
      FULL_PROMPT=$(printf "Run for %s commit\n\n%s" "$COMMIT_HASH" "$PROMPT_CONTENT")
    fi
  else
    echo "Reviewing changes in branch: $BRANCH"
    if [ -n "$CHANGE_DESCRIPTION" ]; then
      FULL_PROMPT=$(printf "run on %s\n\n## Change Description\n\n%s\n\n%s" "$BRANCH" "$CHANGE_DESCRIPTION" "$PROMPT_CONTENT")
    else
      FULL_PROMPT=$(printf "run on %s\n\n%s" "$BRANCH" "$PROMPT_CONTENT")
    fi

    # Include uncommitted changes (staged + unstaged) so reviewers see the full picture
    UNCOMMITTED_DIFF=$(git diff --cached --stat 2>/dev/null; git diff --stat 2>/dev/null)
    if [ -n "$UNCOMMITTED_DIFF" ]; then
      # Also check for untracked files that are new (not in git yet)
      UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null)

      # Generate the actual diff content (staged + unstaged + new files)
      UNCOMMITTED_FULL_DIFF=$(git diff --cached 2>/dev/null; git diff 2>/dev/null)

      # Add untracked file contents (these are entirely new files)
      if [ -n "$UNTRACKED_FILES" ]; then
        while IFS= read -r ufile; do
          if [ -f "$ufile" ] && file --brief "$ufile" | grep -q "text"; then
            UNCOMMITTED_FULL_DIFF=$(printf "%s\n\n--- /dev/null\n+++ b/%s\n%s" \
              "$UNCOMMITTED_FULL_DIFF" "$ufile" \
              "$(awk '{print "+" $0}' "$ufile" | head -200)")
          fi
        done <<< "$UNTRACKED_FILES"
      fi

      # Truncate if very large (keep first 50K chars to avoid prompt limits)
      if [ ${#UNCOMMITTED_FULL_DIFF} -gt 50000 ]; then
        UNCOMMITTED_FULL_DIFF="${UNCOMMITTED_FULL_DIFF:0:50000}

... (truncated, diff too large — use git diff to see full changes)"
      fi

      UNCOMMITTED_SECTION=$(printf "\n\n## IMPORTANT: Uncommitted Working Tree Changes\n\nThe branch has uncommitted changes that are NOT visible via \`git diff main..%s\`. These changes are part of the work being reviewed. You MUST review both the committed branch diff AND the uncommitted diff below.\n\nUncommitted files:\n\`\`\`\n%s\n\`\`\`\n\nFull uncommitted diff:\n\`\`\`diff\n%s\n\`\`\`" "$BRANCH" "$UNCOMMITTED_DIFF" "$UNCOMMITTED_FULL_DIFF")

      FULL_PROMPT="${FULL_PROMPT}${UNCOMMITTED_SECTION}"
      echo "Including uncommitted changes in review scope"
    fi
  fi
fi
