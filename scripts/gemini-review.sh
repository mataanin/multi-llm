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

# Model preference: use GEMINI_MODEL env var, or default to gemini-3.1-pro-preview
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
GEMINI_MODEL_ARGS=(--model "$GEMINI_MODEL")

# Ensure Node >= required version (nvm use modifies PATH in current shell)
CURRENT_NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
if [ -z "$CURRENT_NODE_MAJOR" ] || [ "$CURRENT_NODE_MAJOR" -lt "$GEMINI_NODE_VERSION" ] 2>/dev/null; then
  if command -v nvm >/dev/null 2>&1 || [ -s "$NVM_DIR/nvm.sh" ]; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    . "$NVM_DIR/nvm.sh" 2>/dev/null
    nvm use "$GEMINI_NODE_VERSION" >/dev/null 2>&1
  fi
fi

# Try JSON output for token extraction; fall back to text if format is unexpected
JSON_TMPFILE=$(mktemp)
trap "rm -f '$JSON_TMPFILE'" EXIT

_run_llm_tool "$JSON_TMPFILE" --quiet -- gemini --yolo -o json -p "$FULL_PROMPT" "${GEMINI_MODEL_ARGS[@]}"

# Parse JSON output: extract text and tokens; fall back to raw text if not valid JSON
REVIEW_OUTPUT_FILE="$REVIEW_OUTPUT_FILE" JSON_TMPFILE="$JSON_TMPFILE" python3 << 'PYEOF'
import json, sys, os, shutil

tmpfile = os.environ['JSON_TMPFILE']
outfile = os.environ['REVIEW_OUTPUT_FILE']
tokens_file = outfile.replace('.txt', '.tokens') if outfile.endswith('.txt') else outfile + '.tokens'

try:
    with open(tmpfile) as f:
        content = f.read()
    d = json.loads(content)

    # Extract text result — Gemini CLI uses 'response' field
    text = d.get('response') or d.get('result') or d.get('text') or content
    if isinstance(text, dict):
        text = json.dumps(text)
    with open(outfile, 'w') as f:
        f.write(str(text))

    # Extract tokens — Gemini CLI nests tokens under stats.models.<model>.tokens
    # Aggregate across all models used in the session
    tokens = {}
    stats_models = (d.get('stats') or {}).get('models') or {}
    for model_name, model_data in stats_models.items():
        model_tokens = (model_data or {}).get('tokens') or {}
        # 'input' and 'prompt' are the same value — prefer 'input', fall back to 'prompt'
        input_val = model_tokens.get('input') or model_tokens.get('prompt') or 0
        if input_val > 0:
            tokens['input'] = tokens.get('input', 0) + input_val
        for src, dst in [('candidates','output'), ('cached','cache_read'),
                          ('thoughts','thoughts'), ('total','total')]:
            val = model_tokens.get(src)
            if val is not None and val > 0:
                tokens[dst] = tokens.get(dst, 0) + val

    # Fall back to top-level usage/usageMetadata (older Gemini CLI versions)
    if not tokens:
        usage = d.get('usage') or d.get('usageMetadata') or {}
        for src, dst in [('promptTokenCount','input'), ('candidatesTokenCount','output'),
                          ('cachedContentTokenCount','cache_read'),
                          ('inputTokens','input'), ('outputTokens','output')]:
            if src in usage and usage[src] is not None:
                tokens.setdefault(dst, usage[src])

    if tokens:
        with open(tokens_file, 'w') as f:
            json.dump(tokens, f)

except (json.JSONDecodeError, KeyError, TypeError):
    # Not valid JSON — use raw content as-is (text mode fallback)
    shutil.copy(tmpfile, outfile)
PYEOF

cat "$REVIEW_OUTPUT_FILE"
rm -f "$JSON_TMPFILE"
# Write model sidecar after successful run
echo "${GEMINI_MODEL:-gemini-default}" > "${REVIEW_OUTPUT_FILE%.txt}.model"
