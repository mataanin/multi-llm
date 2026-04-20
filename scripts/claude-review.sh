#!/bin/bash
# Claude Code code review using claude CLI in pipe mode

REVIEW_NAME="Claude"
REVIEW_CLI_CHECK="claude"
REVIEW_INSTALL_HINT="install Claude Code CLI (https://claude.ai/code)"
REVIEW_PROMPT_FILE=".claude/claude-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

# Model preference: use CLAUDE_REVIEW_MODEL env var, default to opus-4.6
CLAUDE_REVIEW_MODEL="${CLAUDE_REVIEW_MODEL:-opus-4.6}"
# Unset all Claude Code env vars to allow running as a subprocess
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT

# Capture JSON output to temp file for token extraction
JSON_TMPFILE=$(mktemp)
trap "rm -f '$JSON_TMPFILE'" EXIT

_run_llm_tool "$JSON_TMPFILE" --quiet -- claude -p "$FULL_PROMPT" --model "$CLAUDE_REVIEW_MODEL" --output-format json

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
for src, dst in [('input_tokens','input'), ('output_tokens','output'),
                  ('cache_read_input_tokens','cache_read'), ('cache_creation_input_tokens','cache_creation')]:
    if src in u and u[src] is not None:
        tokens[dst] = u[src]
print(json.dumps(tokens))
")
if [ "$TOKENS_JSON" != "{}" ] && [ -n "$TOKENS_JSON" ]; then
  echo "$TOKENS_JSON" > "${REVIEW_OUTPUT_FILE%.txt}.tokens"
fi

rm -f "$JSON_TMPFILE"
echo "$CLAUDE_REVIEW_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
