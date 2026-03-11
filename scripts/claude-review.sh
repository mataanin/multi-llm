#!/bin/bash
# Claude Code code review using claude CLI in pipe mode

REVIEW_NAME="Claude"
REVIEW_CLI_CHECK="claude"
REVIEW_INSTALL_HINT="install Claude Code CLI (https://claude.ai/code)"
REVIEW_PROMPT_FILE=".claude/claude-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

# Model preference: use CLAUDE_REVIEW_MODEL env var, default to opus-4.6
CLAUDE_REVIEW_MODEL="${CLAUDE_REVIEW_MODEL:-opus-4.6}"
# Unset all Claude Code env vars to allow running as a subprocess
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
_run_llm_tool "$REVIEW_OUTPUT_FILE" -- claude -p "$FULL_PROMPT" --model "$CLAUDE_REVIEW_MODEL"
echo "$CLAUDE_REVIEW_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
