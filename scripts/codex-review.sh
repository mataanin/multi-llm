#!/bin/bash
# OpenAI Codex code review via the codex-plugin-cc companion script.
# Uses Codex's native built-in reviewer via the plugin companion.
# Normalizes output to the format expected by review-analyze.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log-common.sh"

LLM_TOOL_NAME="Codex"
LLM_CLI_CHECK="node"
LLM_INSTALL_HINT="Install plugin: openai/codex-plugin-cc"
LLM_MODE="review"

# Parse arguments (mirror review-common.sh interface for consistency with parallel runners)
TEST_FLAG=false
CHANGE_DESCRIPTION=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --test)
      TEST_FLAG=true
      shift
      ;;
    --description)
      CHANGE_DESCRIPTION="$2"
      shift 2
      ;;
    --description=*)
      CHANGE_DESCRIPTION="${1#*=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$TEST_FLAG" = true ]; then
  if command -v node >/dev/null 2>&1; then
    echo "✓ node command found"
    exit 0
  else
    echo "✗ node command not found"
    exit 1
  fi
fi

# Setup output file (matches review-common.sh naming convention so review-analyze.sh auto-discovers it)
REVIEW_OUTPUT_DIR="docs/reviews"
mkdir -p "$REVIEW_OUTPUT_DIR"
REVIEW_TIMESTAMP="${REVIEW_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
REVIEW_OUTPUT_FILE="$REVIEW_OUTPUT_DIR/${REVIEW_TIMESTAMP}-codex.txt"
export REVIEW_TIMESTAMP REVIEW_OUTPUT_FILE

# Find the companion script (latest installed version)
CODEX_PLUGIN_DIR="$HOME/.claude/plugins/cache/openai-codex/codex"
CODEX_COMPANION=$(ls "$CODEX_PLUGIN_DIR"/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)

if [ -z "$CODEX_COMPANION" ]; then
  _log_llm_error 1 "codex-companion.mjs not found in $CODEX_PLUGIN_DIR — install plugin: openai/codex-plugin-cc"
  exit 1
fi

CODEX_MODEL="${CODEX_MODEL:-gpt-5-codex}"
CODEX_REASONING="${CODEX_REASONING:-medium}"

BRANCH=$(_get_current_branch)
echo "Running Codex code review..."
echo "Branch: $BRANCH"
echo ""

# Run native review via plugin companion
RAW_OUTPUT=$(mktemp)
set +e
CODEX_REVIEW_ARGS=(review --wait --base main)
[ -n "$CHANGE_DESCRIPTION" ] && CODEX_REVIEW_ARGS+=(--description "$CHANGE_DESCRIPTION")
_timeout_cmd "$REVIEW_TIMEOUT" env CODEX_MODEL="$CODEX_MODEL" CODEX_REASONING="$CODEX_REASONING" \
  node "$CODEX_COMPANION" "${CODEX_REVIEW_ARGS[@]}" > "$RAW_OUTPUT" 2>&1
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ]; then
  cat "$RAW_OUTPUT" > "$REVIEW_OUTPUT_FILE"
  _log_llm_error "$EXIT_CODE" "$(cat "$RAW_OUTPUT")"
  rm -f "$RAW_OUTPUT"
  exit $EXIT_CODE
fi

# Normalize companion output to the format expected by review-analyze.sh.
#
# Companion wraps native Codex review output in:
#   # Codex Review
#   Target: <label>
#   <native Codex review text>
#
# We strip the companion header, then:
#   - If the content already has "### Code Review Results" → pass through as-is
#   - Otherwise → count numbered findings and add the standard header
#
# The native Codex reviewer format may vary by model version.

python3 - "$RAW_OUTPUT" "$REVIEW_OUTPUT_FILE" << 'PYEOF'
import sys, re

src, dst = sys.argv[1], sys.argv[2]
raw = open(src).read()

# Strip companion header: "# Codex Review\n\nTarget: ...\n\n" (or similar)
content = re.sub(r'^#\s+Codex Review\s*\n+(?:Target:.*\n+)?', '', raw, count=1).strip()

# If content already has our expected format, use as-is
if re.search(r'###\s+Code Review Results', content):
    open(dst, 'w').write(content)
    sys.exit(0)

# Count top-level numbered findings (e.g. "1. Description" at start of line)
numbered = re.findall(r'(?m)^\d+\.\s', content)
n = len(numbered)

with open(dst, 'w') as f:
    if n > 0:
        f.write(f'### Code Review Results\n\nFound {n} issues:\n\n{content}\n')
    elif re.search(r'no issues|nothing to report|lgtm|looks good', content, re.IGNORECASE):
        f.write(f'### Code Review Results\n\nNo issues found.\n\n{content}\n')
    else:
        # Pass through with header — review-analyze.sh will extract what it can
        f.write(f'### Code Review Results\n\nFound 0 issues.\n\n{content}\n')
PYEOF

rm -f "$RAW_OUTPUT"

echo "$CODEX_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
echo "$CODEX_REASONING" > "${REVIEW_OUTPUT_FILE%.txt}.reasoning"
