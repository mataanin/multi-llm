#!/bin/bash
# Google Gemini code review using gemini CLI in non-interactive mode

REVIEW_NAME="Gemini"
REVIEW_CLI_CHECK="gemini"
REVIEW_INSTALL_HINT="npm i -g @google/gemini-cli"
REVIEW_PROMPT_FILE=".claude/gemini-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

# Gemini CLI requires Node 20+; use nvm to switch if current version is too old
GEMINI_NODE_VERSION="${GEMINI_NODE_VERSION:-20}"

# Model preference: use GEMINI_MODEL env var, or let CLI pick its default
if [ -n "${GEMINI_MODEL:-}" ]; then
  GEMINI_MODEL_ARGS=(--model "$GEMINI_MODEL")
else
  GEMINI_MODEL_ARGS=()
fi

# Ensure Node >= required version (nvm use modifies PATH in current shell)
CURRENT_NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
if [ -z "$CURRENT_NODE_MAJOR" ] || [ "$CURRENT_NODE_MAJOR" -lt "$GEMINI_NODE_VERSION" ] 2>/dev/null; then
  if command -v nvm >/dev/null 2>&1 || [ -s "$NVM_DIR/nvm.sh" ]; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    . "$NVM_DIR/nvm.sh" 2>/dev/null
    nvm use "$GEMINI_NODE_VERSION" >/dev/null 2>&1
  fi
fi

_run_llm_tool "$REVIEW_OUTPUT_FILE" -- gemini --yolo -p "$FULL_PROMPT" "${GEMINI_MODEL_ARGS[@]}"
# Write model sidecar after successful run
echo "${GEMINI_MODEL:-gemini-default}" > "${REVIEW_OUTPUT_FILE%.txt}.model"
