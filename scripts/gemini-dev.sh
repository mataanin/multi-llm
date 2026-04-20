#!/bin/bash
# Google Gemini development tasks (explore, architect, plan-review)

DEV_NAME="Gemini"
DEV_CLI_CHECK="gemini"
DEV_INSTALL_HINT="npm i -g @google/gemini-cli"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dev-common.sh" "$@"

set -o pipefail

# Gemini CLI requires Node 20+; use nvm to switch if current version is too old
GEMINI_NODE_VERSION="${GEMINI_NODE_VERSION:-20}"
CURRENT_NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
if [ -z "$CURRENT_NODE_MAJOR" ] || [ "$CURRENT_NODE_MAJOR" -lt "$GEMINI_NODE_VERSION" ] 2>/dev/null; then
  if command -v nvm >/dev/null 2>&1 || [ -s "$NVM_DIR/nvm.sh" ]; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    . "$NVM_DIR/nvm.sh" 2>/dev/null
    nvm use "$GEMINI_NODE_VERSION" >/dev/null 2>&1
  fi
fi

# Model preference: use GEMINI_MODEL env var, or default to gemini-3.1-pro-preview
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
GEMINI_MODEL_ARGS=(--model "$GEMINI_MODEL")

LLM_OUTPUT=$(mktemp)
_run_llm_tool "$LLM_OUTPUT" --cleanup -- gemini --yolo "${GEMINI_MODEL_ARGS[@]}" -p "$FULL_PROMPT"
