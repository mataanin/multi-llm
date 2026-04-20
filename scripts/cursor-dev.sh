#!/bin/bash
# Cursor Agent development tasks (explore, architect, plan-review)

DEV_NAME="Cursor"
DEV_CLI_CHECK="agent"
DEV_INSTALL_HINT="install the Anthropic agent CLI"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dev-common.sh" "$@"

set -o pipefail

# Model preference: use CURSOR_MODEL env var, default to composer-1.5
CURSOR_MODEL="${CURSOR_MODEL:-composer-1.5}"
LLM_OUTPUT=$(mktemp)
_run_llm_tool "$LLM_OUTPUT" --cleanup -- agent --trust -p "$FULL_PROMPT" --model "$CURSOR_MODEL"
