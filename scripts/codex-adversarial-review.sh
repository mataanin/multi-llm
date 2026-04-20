#!/bin/bash
# OpenAI Codex adversarial code review via the codex-plugin-cc companion script.
# Uses the plugin's built-in adversarial prompt (challenges design choices and assumptions).
# Converts the companion's rendered text output to the format expected by review-analyze.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log-common.sh"

LLM_TOOL_NAME="Codex-Adversarial"
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
REVIEW_OUTPUT_FILE="$REVIEW_OUTPUT_DIR/${REVIEW_TIMESTAMP}-codex-adversarial.txt"
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
echo "Running Codex adversarial review..."
echo "Branch: $BRANCH"
echo ""

# Run adversarial review via plugin companion
RAW_OUTPUT=$(mktemp)
set +e
CODEX_ADV_ARGS=(adversarial-review --wait --base main)
[ -n "$CHANGE_DESCRIPTION" ] && CODEX_ADV_ARGS+=(--description "$CHANGE_DESCRIPTION")
_timeout_cmd "$REVIEW_TIMEOUT" env CODEX_MODEL="$CODEX_MODEL" CODEX_REASONING="$CODEX_REASONING" \
  node "$CODEX_COMPANION" "${CODEX_ADV_ARGS[@]}" > "$RAW_OUTPUT" 2>&1
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ]; then
  cat "$RAW_OUTPUT" > "$REVIEW_OUTPUT_FILE"
  _log_llm_error "$EXIT_CODE" "$(cat "$RAW_OUTPUT")"
  rm -f "$RAW_OUTPUT"
  exit $EXIT_CODE
fi

# Convert companion's rendered text format to the format expected by review-analyze.sh.
#
# Companion renders adversarial-review output as:
#   # Codex Adversarial Review
#   Target: <label>
#   Verdict: approve|needs-attention
#   <summary>
#   Findings:
#   - [severity] Title (file.rb:10)
#     Body text
#     Recommendation: fix it
#
# review-analyze.sh expects:
#   ### Code Review Results
#   Found N issues:
#   1. Title
#      Body text
#      Recommendation: fix it
#      File: `file.rb:10`
#      Confidence: <int>
#
# Severity → confidence: critical=95, high=85, medium=70, low=55

python3 - "$RAW_OUTPUT" "$REVIEW_OUTPUT_FILE" << 'PYEOF'
import sys, re

src, dst = sys.argv[1], sys.argv[2]
raw = open(src).read()

# Parse findings from rendered companion output
# Pattern: "- [severity] Title (file:line)" with indented continuation lines
finding_pattern = re.compile(
    r'^- \[(\w+)\] (.+?) \(([^)]+)\)\s*\n((?:[ \t]+.+\n?)*)',
    re.MULTILINE
)

SEVERITY_CONFIDENCE = {"critical": 95, "high": 85, "medium": 70, "low": 55}

findings = []
for m in finding_pattern.finditer(raw):
    severity = m.group(1).strip().lower()
    title = m.group(2).strip()
    file_loc = m.group(3).strip()
    body_raw = m.group(4)

    # Clean indented body lines
    body_lines = [line.strip() for line in body_raw.strip().splitlines() if line.strip()]

    recommendation = ""
    body_parts = []
    for line in body_lines:
        if line.startswith("Recommendation:"):
            recommendation = line
        else:
            body_parts.append(line)

    body = " ".join(body_parts)
    confidence = SEVERITY_CONFIDENCE.get(severity, 70)
    findings.append((title, body, recommendation, file_loc, confidence))

lines = ["### Code Review Results", ""]
if not findings:
    # No structured findings — check for "No material findings" or pass through summary
    if "No material findings" in raw or re.search(r'\bverdict\s*:\s*approve\b', raw, re.IGNORECASE):
        lines.append("No issues found.")
    else:
        # Pass through raw content with minimal header
        lines.append("Found 0 issues.")
        lines.append("")
        lines.append(raw)
else:
    lines.append(f"Found {len(findings)} issues:")
    lines.append("")
    for i, (title, body, recommendation, file_loc, confidence) in enumerate(findings, 1):
        lines.append(f"{i}. {title}")
        if body:
            lines.append(f"   {body}")
        if recommendation:
            lines.append(f"   {recommendation}")
        lines.append(f"   File: `{file_loc}`")
        lines.append(f"   Confidence: {confidence}")
        lines.append("")

open(dst, 'w').write("\n".join(lines))
PYEOF

rm -f "$RAW_OUTPUT"

echo "$CODEX_MODEL" > "${REVIEW_OUTPUT_FILE%.txt}.model"
echo "adversarial" > "${REVIEW_OUTPUT_FILE%.txt}.reasoning"
