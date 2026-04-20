#!/bin/bash
# Shared utilities for 3rd-party LLM scripts.
# Source this from dev-common.sh and review-common.sh.
#
# Provides: _timeout_cmd, _run_llm_tool, _log_llm_error, _get_current_branch, REVIEW_TIMEOUT
# Expects callers to set: LLM_TOOL_NAME, LLM_MODE, LLM_CLI_CHECK, LLM_INSTALL_HINT

# Portable timeout wrapper (macOS lacks GNU timeout).
# Wraps the command in a bash subshell so shell functions (like nvm) work.
_timeout_cmd() {
  local duration="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$duration" bash -c '"$@"' _ "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$duration" bash -c '"$@"' _ "$@"
  else
    # No timeout available — run directly
    "$@"
  fi
}
REVIEW_TIMEOUT="${REVIEW_TIMEOUT:-600}"

# Run an LLM CLI command with timeout and error handling.
# Usage: _run_llm_tool <output_file> [--cleanup] [--quiet] -- <command...>
#   --cleanup: remove output_file on exit (for dev scripts using mktemp)
#   --quiet:   write to file only (no tee to stdout), for JSON capture
# Returns the command's exit code.
_run_llm_tool() {
  local output_file="$1"
  shift
  local cleanup=false
  local quiet=false
  while true; do
    case "$1" in
      --cleanup) cleanup=true; shift ;;
      --quiet)   quiet=true;   shift ;;
      *)         break ;;
    esac
  done
  [ "$1" = "--" ] && shift

  set +e
  if $quiet; then
    # Redirect only stdout to file; keep stderr separate so it doesn't
    # corrupt JSON output that callers parse with json.load/jq.
    _timeout_cmd "$REVIEW_TIMEOUT" "$@" > "$output_file" 2>>"$LLM_LOG_FILE"
    local exit_code=$?
  else
    _timeout_cmd "$REVIEW_TIMEOUT" "$@" 2>&1 | tee "$output_file"
    local exit_code=${PIPESTATUS[0]}
  fi
  set -e

  if [ "$exit_code" -eq 124 ]; then
    echo "Error: Command timed out after ${REVIEW_TIMEOUT}s" >> "$output_file"
    _log_llm_error "$exit_code" "Command timed out after ${REVIEW_TIMEOUT}s"
    $cleanup && rm -f "$output_file"
    exit "$exit_code"
  elif [ "$exit_code" -ne 0 ]; then
    _log_llm_error "$exit_code" "$(cat "$output_file")"
    $cleanup && rm -f "$output_file"
    exit "$exit_code"
  fi
  $cleanup && rm -f "$output_file"
  return 0
}

# Get current branch name with detached HEAD fallback.
_get_current_branch() {
  local branch
  branch=$(git branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git describe --tags --exact-match HEAD 2>/dev/null || git rev-parse --short HEAD)
  fi
  echo "$branch"
}

LLM_LOG_DIR=".claude/logs"
mkdir -p "$LLM_LOG_DIR"
LLM_LOG_FILE="$LLM_LOG_DIR/llm-errors.log"

# Log a 3rd-party LLM failure.
# Usage: _log_llm_error <exit_code> <error_output>
_log_llm_error() {
  local exit_code=$1
  local error_output="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo "[$timestamp] FAILURE: $LLM_TOOL_NAME ($LLM_MODE)"
    echo "  Exit code: $exit_code"
    echo "  CLI command: $LLM_CLI_CHECK"
    if echo "$error_output" | grep -qi "auth\|credential\|token\|api.key\|unauthorized\|forbidden\|permission"; then
      echo "  Likely cause: CREDENTIALS / AUTH"
    elif echo "$error_output" | grep -qi "timeout\|timed.out\|deadline\|ETIMEDOUT"; then
      echo "  Likely cause: TIMEOUT"
    elif ! command -v "$LLM_CLI_CHECK" >/dev/null 2>&1; then
      echo "  Likely cause: CLI NOT INSTALLED ($LLM_INSTALL_HINT)"
    else
      echo "  Likely cause: UNKNOWN"
    fi
    echo "  Error output (last 20 lines):"
    echo "$error_output" | tail -20 | sed 's/^/    /'
    echo "---"
  } >> "$LLM_LOG_FILE"
}
