#!/bin/bash
# OpenAI Codex code review using codex exec CLI

REVIEW_NAME="Codex"
REVIEW_CLI_CHECK="codex"
REVIEW_INSTALL_HINT="npm i -g @openai/codex"
REVIEW_PROMPT_FILE=".claude/codex-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

# Model preference: use CODEX_MODEL env var, or default to gpt-5-codex.
CODEX_MODEL="${CODEX_MODEL:-gpt-5-codex}"
CODEX_REASONING="${CODEX_REASONING:-medium}"

_run_llm_tool "$REVIEW_OUTPUT_FILE" -- codex exec --model "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_REASONING" --sandbox read-only "$FULL_PROMPT"
# Write sidecar files after successful run (avoids ghost entries for failed tools)
echo "$CODEX_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
echo "$CODEX_REASONING" > "${REVIEW_OUTPUT_FILE%.txt}.reasoning"
