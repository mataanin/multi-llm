#!/bin/bash
# Shared logic for development task scripts (Codex, Gemini, Cursor).
# Source this file from each dev script after setting DEV_NAME,
# DEV_CLI_CHECK, and DEV_INSTALL_HINT.
#
# Supported modes: explore, architect, plan-review
#
# After sourcing, $FULL_PROMPT is set and ready to pass to the CLI.

set -e

# --- Error logging for 3rd-party LLM failures ---
SCRIPT_DIR_COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_COMMON/log-common.sh"
LLM_TOOL_NAME="$DEV_NAME"
LLM_CLI_CHECK="$DEV_CLI_CHECK"
LLM_INSTALL_HINT="$DEV_INSTALL_HINT"

# Parse arguments
MODE=""
TASK_DESC=""
PLAN_TEXT=""
TEST_FLAG=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --test)
      TEST_FLAG=true
      shift
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --task)
      TASK_DESC="$2"
      shift 2
      ;;
    --task=*)
      TASK_DESC="${1#*=}"
      shift
      ;;
    --plan)
      PLAN_TEXT="$2"
      shift 2
      ;;
    --plan=*)
      PLAN_TEXT="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: <script> --mode explore|architect|plan-review --task \"description\" | --plan \"plan text\""
      exit 1
      ;;
  esac
done

# Handle --test flag
if [ "$TEST_FLAG" = true ]; then
  if command -v "$DEV_CLI_CHECK" >/dev/null 2>&1; then
    echo "✓ $DEV_CLI_CHECK command found"
    exit 0
  else
    echo "✗ $DEV_CLI_CHECK command not found in PATH"
    echo "  Install with: $DEV_INSTALL_HINT"
    exit 1
  fi
fi

# Validate mode
if [ -z "$MODE" ]; then
  echo "Error: --mode is required (explore|architect|plan-review)"
  exit 1
fi

case "$MODE" in
  explore|architect)
    if [ -z "$TASK_DESC" ]; then
      echo "Error: --task is required for mode '$MODE'"
      exit 1
    fi
    ;;
  plan-review)
    if [ -z "$PLAN_TEXT" ]; then
      echo "Error: --plan is required for mode 'plan-review'"
      exit 1
    fi
    ;;
  *)
    echo "Error: Invalid mode '$MODE'. Must be explore, architect, or plan-review"
    exit 1
    ;;
esac

# Compute prompt file path
DEV_NAME_LOWER=$(echo "$DEV_NAME" | tr '[:upper:]' '[:lower:]')
DEV_PROMPT_FILE=".claude/prompts/${DEV_NAME_LOWER}-${MODE}-prompt.md"

if [ ! -f "$DEV_PROMPT_FILE" ]; then
  echo "Error: $DEV_PROMPT_FILE not found"
  exit 1
fi

# Build FULL_PROMPT
PROMPT_CONTENT=$(cat "$DEV_PROMPT_FILE")

LLM_MODE="$MODE mode"

echo "Running $DEV_NAME in $MODE mode..."
echo ""

case "$MODE" in
  explore|architect)
    FULL_PROMPT=$(printf "## Task\n\n%s\n\n---\n\n%s" "$TASK_DESC" "$PROMPT_CONTENT")
    ;;
  plan-review)
    FULL_PROMPT=$(printf "## Plan to Review\n\n%s\n\n---\n\n%s" "$PLAN_TEXT" "$PROMPT_CONTENT")
    ;;
esac
