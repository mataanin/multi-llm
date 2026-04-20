#!/bin/bash
# GitHub Copilot CLI development tasks (explore, architect, plan-review, adversarial-plan-review)
# Uses copilot -p in non-interactive mode.

DEV_NAME="Copilot"
DEV_CLI_CHECK="copilot"
DEV_INSTALL_HINT="npm install -g @github/copilot OR brew install copilot-cli"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure nvm-installed copilot is in PATH before dev-common.sh runs --test check
if ! command -v copilot >/dev/null 2>&1; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
fi

source "$SCRIPT_DIR/dev-common.sh" "$@"

set -o pipefail

COPILOT_MODEL="${COPILOT_MODEL:-claude-sonnet-4.6}"

LLM_OUTPUT=$(mktemp)
_run_llm_tool "$LLM_OUTPUT" --cleanup -- \
  copilot -p "$FULL_PROMPT" --autopilot --yolo -s --no-ask-user --model "$COPILOT_MODEL"
