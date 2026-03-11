#!/bin/bash
# OpenAI Codex development tasks (explore, architect, plan-review)

DEV_NAME="Codex"
DEV_CLI_CHECK="codex"
DEV_INSTALL_HINT="npm i -g @openai/codex"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dev-common.sh" "$@"

set -o pipefail
CODEX_MODEL="${CODEX_MODEL:-gpt-5-codex}"
CODEX_REASONING="${CODEX_REASONING:-medium}"
LLM_OUTPUT=$(mktemp)
_run_llm_tool "$LLM_OUTPUT" --cleanup -- codex exec --model "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_REASONING" --sandbox read-only "$FULL_PROMPT"
