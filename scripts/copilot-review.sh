#!/bin/bash
# GitHub Copilot CLI code review using copilot -p in non-interactive mode.
# Normalizes output to the format expected by review-analyze.sh.

REVIEW_NAME="Copilot"
REVIEW_CLI_CHECK="copilot"
REVIEW_INSTALL_HINT="npm install -g @github/copilot OR brew install copilot-cli"
REVIEW_PROMPT_FILE=".claude/copilot-code-review-prompt.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure nvm-installed copilot is in PATH before review-common.sh runs --test check
if ! command -v copilot >/dev/null 2>&1; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
fi

source "$SCRIPT_DIR/review-common.sh" "$@"

set -o pipefail

COPILOT_MODEL="${COPILOT_MODEL:-claude-sonnet-4.6}"

RAW_OUTPUT=$(mktemp)
trap "rm -f '$RAW_OUTPUT'" EXIT

_run_llm_tool "$RAW_OUTPUT" --quiet -- \
  copilot -p "$FULL_PROMPT" --autopilot --yolo -s --no-ask-user --model "$COPILOT_MODEL"

# Normalize to ### Code Review Results format (required by review-analyze.sh).
#
# copilot -s emits plain text; review-analyze.sh expects:
#   ### Code Review Results
#   Found N issues:
#   1. ...
#
# If the output already has the header (e.g. the prompt produced it), pass through.
# Otherwise count numbered findings and inject the standard header.

python3 - "$RAW_OUTPUT" "$REVIEW_OUTPUT_FILE" << 'PYEOF'
import sys, re

src, dst = sys.argv[1], sys.argv[2]
content = open(src).read().strip()

if re.search(r'###\s+Code Review Results', content):
    open(dst, 'w').write(content)
    sys.exit(0)

numbered = re.findall(r'(?m)^\d+\.\s', content)
n = len(numbered)

with open(dst, 'w') as f:
    if n > 0:
        f.write(f'### Code Review Results\n\nFound {n} issues:\n\n{content}\n')
    elif re.search(r'no issues|nothing to report|lgtm|looks good', content, re.IGNORECASE):
        f.write(f'### Code Review Results\n\nNo issues found.\n\n{content}\n')
    else:
        f.write(f'### Code Review Results\n\nFound 0 issues.\n\n{content}\n')
PYEOF

cat "$REVIEW_OUTPUT_FILE"
echo "$COPILOT_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
echo "standard" > "${REVIEW_OUTPUT_FILE%.txt}.reasoning"
