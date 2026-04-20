#!/bin/bash
# Cursor Bugbot-style code review using Claude CLI agents

REVIEW_NAME="Cursor"
REVIEW_CLI_CHECK="agent"
REVIEW_INSTALL_HINT="install the Anthropic agent CLI"
REVIEW_PROMPT_FILE=".claude/cursor-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

# Model preference: use CURSOR_MODEL env var, default to composer-1.5
CURSOR_MODEL="${CURSOR_MODEL:-composer-2}"

# Capture JSON output to temp file for token extraction
JSON_TMPFILE=$(mktemp)
trap "rm -f '$JSON_TMPFILE'" EXIT

_run_llm_tool "$JSON_TMPFILE" --quiet -- agent --trust -p "$FULL_PROMPT" --model "$CURSOR_MODEL" --output-format json

# Extract text result for the review output file, replay to stdout
python3 -c "
import json, sys
d = json.load(open('$JSON_TMPFILE'))
print(d.get('result') or '')
" > "$REVIEW_OUTPUT_FILE"
cat "$REVIEW_OUTPUT_FILE"

# Extract token usage sidecar (only write if tokens are present)
TOKENS_JSON=$(python3 -c "
import json
d = json.load(open('$JSON_TMPFILE'))
u = d.get('usage') or {}
tokens = {}
for src, dst in [('inputTokens','input'), ('outputTokens','output'), ('cacheReadTokens','cache_read')]:
    if src in u and u[src] is not None:
        tokens[dst] = u[src]
print(json.dumps(tokens))
")
if [ "$TOKENS_JSON" != "{}" ] && [ -n "$TOKENS_JSON" ]; then
  echo "$TOKENS_JSON" > "${REVIEW_OUTPUT_FILE%.txt}.tokens"
fi

rm -f "$JSON_TMPFILE"
echo "$CURSOR_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
