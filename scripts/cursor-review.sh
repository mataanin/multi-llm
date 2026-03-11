#!/bin/bash
# Cursor Bugbot-style code review using Claude CLI agents

REVIEW_NAME="Cursor"
REVIEW_CLI_CHECK="agent"
REVIEW_INSTALL_HINT="install the Anthropic agent CLI"
REVIEW_PROMPT_FILE=".claude/cursor-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

# Model preference: use CURSOR_MODEL env var, default to composer-1.5
CURSOR_MODEL="${CURSOR_MODEL:-composer-1.5}"
_run_llm_tool "$REVIEW_OUTPUT_FILE" -- agent --trust -p "$FULL_PROMPT" --model "$CURSOR_MODEL"
echo "$CURSOR_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
