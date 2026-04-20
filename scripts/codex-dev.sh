#!/bin/bash
# OpenAI Codex development tasks (explore, architect, plan-review, adversarial-plan-review)
# Uses the codex-plugin-cc companion's task command (read-only by default).

DEV_NAME="Codex"
DEV_CLI_CHECK="node"
DEV_INSTALL_HINT="Install plugin: openai/codex-plugin-cc"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dev-common.sh" "$@"

set -o pipefail

# Find the companion script (latest installed version)
CODEX_PLUGIN_DIR="$HOME/.claude/plugins/cache/openai-codex/codex"
CODEX_COMPANION=$(ls "$CODEX_PLUGIN_DIR"/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)

if [ -z "$CODEX_COMPANION" ]; then
  echo "Error: codex-companion.mjs not found in $CODEX_PLUGIN_DIR — install plugin: openai/codex-plugin-cc"
  exit 1
fi

CODEX_MODEL="${CODEX_MODEL:-gpt-5-codex}"
CODEX_REASONING="${CODEX_REASONING:-medium}"

# Write prompt to a temp file to avoid shell arg length limits on large prompts
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT
printf '%s' "$FULL_PROMPT" > "$PROMPT_FILE"

LLM_OUTPUT=$(mktemp)
_run_llm_tool "$LLM_OUTPUT" --cleanup -- \
  node "$CODEX_COMPANION" task \
    --model "$CODEX_MODEL" \
    --effort "$CODEX_REASONING" \
    --prompt-file "$PROMPT_FILE"
