#!/bin/bash
# Analyze review outputs from multiple LLM tools.
# Extracts findings via deterministic parsing (no LLM dependency),
# matches across tools by file path, and correlates with git actions.
#
# Usage:
#   review-analyze.sh <timestamp> [--reviewer <email>] [--review-type <type>]
#   review-analyze.sh 20250210-143022
#   review-analyze.sh 20250210-143022 --reviewer user@example.com --review-type plan
#
# Discovers tools dynamically from review output files: .claude/reviews/<timestamp>-<tool>.txt
# Appends results to review-analytics.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log-common.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REVIEW_DIR="$REPO_ROOT/.claude/reviews"
ANALYTICS_FILE="$REPO_ROOT/review-analytics.json"

# Parse arguments
TIMESTAMP=""
REVIEWER=""
REVIEW_TYPE="code"

while [[ $# -gt 0 ]]; do
  case $1 in
    --reviewer)
      [ $# -lt 2 ] && { echo "Error: --reviewer requires a value" >&2; exit 1; }
      REVIEWER="$2"
      shift 2
      ;;
    --reviewer=*)
      REVIEWER="${1#*=}"
      shift
      ;;
    --review-type)
      [ $# -lt 2 ] && { echo "Error: --review-type requires a value" >&2; exit 1; }
      REVIEW_TYPE="$2"
      shift 2
      ;;
    --review-type=*)
      REVIEW_TYPE="${1#*=}"
      shift
      ;;
    *)
      if [ -z "$TIMESTAMP" ]; then
        TIMESTAMP="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$TIMESTAMP" ]; then
  echo "Usage: review-analyze.sh <timestamp> [--reviewer <email>] [--review-type <type>]"
  exit 1
fi

# Detect reviewer identity
if [ -z "$REVIEWER" ]; then
  if [ -n "$GITHUB_ACTOR" ]; then
    REVIEWER="$GITHUB_ACTOR"
  else
    REVIEWER=$(git config user.email 2>/dev/null || echo "unknown")
  fi
fi

# Discover tools dynamically from review output files
TOOLS=()
for f in "$REVIEW_DIR/$TIMESTAMP"-*.txt; do
  [ -f "$f" ] || continue
  tool=$(basename "$f" .txt | sed "s/^${TIMESTAMP}-//")
  TOOLS+=("$tool")
done

if [ ${#TOOLS[@]} -eq 0 ]; then
  echo "No review output files found for timestamp $TIMESTAMP in $REVIEW_DIR"
  exit 0
fi

# Initialize analytics file if missing
if [ ! -f "$ANALYTICS_FILE" ]; then
  echo '{"reviews":[]}' > "$ANALYTICS_FILE"
fi

# ── Step 1: Extract findings from each tool ──────────────────────────

# Deterministic Python parser — no LLM dependency.
# Finds the LAST "Code Review Results" section in the file (skips prompt echoes),
# parses numbered findings, extracts file paths, line ranges, and confidence scores.
extract_findings() {
  local tool="$1"
  local file="$REVIEW_DIR/${TIMESTAMP}-${tool}.txt"

  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    echo "SKIPPED"
    return
  fi

  # Detect CLI errors (not a valid review output)
  if grep -q "Error:.*cannot be launched\|SyntaxError:\|Could not find 'bundler'\|exhausted your capacity\|does not exist or you do not have access\|Error when talking to Gemini API\|status 429\|TerminalQuotaError\|An unexpected critical error\|stream error:.*stream disconnected\|Error: Command timed out\|RetryableQuotaError\|PERMISSION_DENIED\|No capacity available" "$file" 2>/dev/null; then
    # Check if there's still a valid results section after the error
    if ! grep -q "^Found [0-9]\+ issue" "$file" 2>/dev/null && \
       ! grep -q "^No issues found" "$file" 2>/dev/null; then
      echo "FAILED"
      return
    fi
  fi

  REVIEW_FILE="$file" python3 << 'PYEOF'
import json, re, sys, os

file_path = os.environ['REVIEW_FILE']
with open(file_path, 'r') as f:
    content = f.read()

# Find the LAST "Code Review Results" section (skip prompt template echoes)
# Look for the last occurrence of the results header
sections = list(re.finditer(
    r'#{2,3}\s*Code Review Results',
    content
))

if not sections:
    # No results section found — try to find "Found N issue" anywhere
    found_match = re.search(r'Found\s+(\d+)\s+issue', content)
    if not found_match:
        print('[]')
        sys.exit(0)
    # Use content from that point
    results_text = content[found_match.start():]
else:
    # Use the LAST results section
    results_text = content[sections[-1].start():]

# Check for "No issues found"
if re.search(r'No issues found', results_text, re.IGNORECASE):
    # But verify there isn't a "Found N issues" AFTER "No issues found"
    no_issues_pos = re.search(r'No issues found', results_text, re.IGNORECASE).start()
    found_after = re.search(r'Found\s+(\d+)\s+issue', results_text[no_issues_pos:])
    if not found_after:
        print('[]')
        sys.exit(0)
    # There are findings after the "no issues" — continue with those
    results_text = results_text[no_issues_pos + found_after.start():]

# Extract "Found N issues:" count
found_match = re.search(r'Found\s+(\d+)\s+issue', results_text)
if not found_match:
    print('[]')
    sys.exit(0)

expected_count = int(found_match.group(1))
if expected_count == 0:
    print('[]')
    sys.exit(0)

# Split into individual findings by top-level numbered list pattern.
# Handles two formats:
#   "### 1. Description" (Cursor uses markdown headers)
#   "1. Description" (Codex/Gemini use plain numbered lists)
# Avoids splitting on indented sub-items (e.g., "   1. sub-point")
findings_text = results_text[found_match.end():]

# Split on top-level numbered items: either "### N." headers or
# unindented "N." at start of line (not preceded by whitespace/indentation)
items = re.split(r'\n(?=#{2,3}\s+\d+\.\s|\d+\.\s)', findings_text)
# Filter to items that actually start with a number (or ### header)
items = [item.strip() for item in items
         if re.match(r'(?:#{2,3}\s+)?\d+\.', item.strip())]

# Limit to expected count to avoid sub-item splitting
items = items[:expected_count]

findings = []
for item in items:
    # Remove the leading "### N." or "N." prefix
    desc_text = re.sub(r'^(?:#{2,3}\s+)?\d+\.\s*', '', item).strip()

    # Extract description (first line or first sentence)
    desc_lines = desc_text.split('\n')
    description = desc_lines[0].strip()
    # Clean markdown formatting
    description = re.sub(r'\*\*', '', description)
    description = re.sub(r'`([^`]*)`', r'\1', description)
    # Truncate overly long descriptions
    if len(description) > 200:
        description = description[:197] + '...'

    # Extract file path(s) — handles multiple formats:
    #   "File: `path:line`"  (Codex/Gemini)
    #   "**File:** `path:line`"  (Cursor bold)
    #   "Files: `path:line`, `path2`"  (Codex multi-file)
    # Try backtick-wrapped path first (most reliable), then fall back to bare path
    # Cursor uses "**File:** `path`" (colon inside bold); Codex/Gemini use "File: `path`"
    file_match = (
        re.search(r'\*\*Files?:\*\*\s*`([^`]+)`', desc_text) or
        re.search(r'(?:Files?|File):\s*`([^`]+)`', desc_text) or
        re.search(r'\*\*Files?:\*\*\s*(\S+)', desc_text) or
        re.search(r'(?:Files?|File):\s*(\S+)', desc_text)
    )
    file_path_found = None
    line_range = None
    if file_match:
        raw_path = file_match.group(1).strip('`').strip()
        # Split path and line range (e.g., "file.rb:42" or "file.rb:L90-L93")
        line_match = re.search(r':(?:L)?(\d+(?:-(?:L)?\d+)?)$', raw_path)
        if line_match:
            line_range = line_match.group(1)
            file_path_found = raw_path[:line_match.start()]
        else:
            file_path_found = raw_path

    # Extract confidence score
    confidence = None
    conf_match = re.search(r'[Cc]onfidence:\s*(\d+)', desc_text)
    if conf_match:
        confidence = int(conf_match.group(1))

    # Infer category from keywords
    category = 'bug'  # default
    lower_text = desc_text.lower()
    if any(w in lower_text for w in ['race condition', 'transaction', 'deadlock', 'concurrent']):
        category = 'bug'
    elif any(w in lower_text for w in ['security', 'xss', 'injection', 'auth', 'csrf']):
        category = 'security'
    elif any(w in lower_text for w in ['performance', 'n+1', 'slow', 'memory']):
        category = 'performance'
    elif any(w in lower_text for w in ['claude.md', 'compliance', 'convention', 'guideline']):
        category = 'compliance'
    elif any(w in lower_text for w in ['style', 'naming', 'formatting', 'lint']):
        category = 'style'
    elif any(w in lower_text for w in ['integration', 'webhook', 'api', 'sync']):
        category = 'integration'

    findings.append({
        'description': description,
        'file': file_path_found,
        'line': line_range,
        'category': category,
        'confidence': confidence,
    })

print(json.dumps(findings, ensure_ascii=False))
PYEOF
}

echo "Extracting findings from review outputs..."
echo "  Tools discovered: ${TOOLS[*]}"

# Track which tools actually ran (vs. missing/empty output)
# Build initial status JSON in one jq call
TOOLS_STATUS=$(printf '%s\n' "${TOOLS[@]}" | jq -Rs 'split("\n")[:-1] | reduce .[] as $t ({}; .[$t] = "skipped")')
TOOLS_RAN=0

# Store findings in a temporary directory (avoids bash 4+ associative arrays for macOS compat)
FINDINGS_DIR=$(mktemp -d)
trap "rm -rf '$FINDINGS_DIR'" EXIT INT TERM

# Initialize all tools with empty findings
for tool in "${TOOLS[@]}"; do
  echo '[]' > "$FINDINGS_DIR/$tool.json"
done

for tool in "${TOOLS[@]}"; do
  label="$(echo "$tool" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  raw=$(extract_findings "$tool")
  if [ "$raw" = "SKIPPED" ]; then
    echo "  $label: SKIPPED (no output file)"
  elif [ "$raw" = "FAILED" ]; then
    echo "  $label: FAILED (CLI error in output)"
    TOOLS_STATUS=$(echo "$TOOLS_STATUS" | jq --arg t "$tool" '.[$t] = "failed"')
  else
    if echo "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
      echo "$raw" > "$FINDINGS_DIR/$tool.json"
    fi
    TOOLS_STATUS=$(echo "$TOOLS_STATUS" | jq --arg t "$tool" '.[$t] = "ran"')
    TOOLS_RAN=$((TOOLS_RAN + 1))
  fi
done

# Display counts for tools that ran
for tool in "${TOOLS[@]}"; do
  status=$(echo "$TOOLS_STATUS" | jq -r --arg t "$tool" '.[$t]')
  if [ "$status" = "ran" ]; then
    label="$(echo "$tool" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    count=$(jq 'length' "$FINDINGS_DIR/$tool.json")
    echo "  $label: $count findings"
  fi
done

if [ "$TOOLS_RAN" -eq 0 ]; then
  echo ""
  echo "WARNING: No review tools produced output. Skipping analysis."
  exit 0
fi

# ── Step 2: Match findings across tools ──────────────────────────────

# Deterministic file-path matching — no LLM dependency.
# Findings referencing the same file from different tools are grouped as matches.

match_findings() {
  # Build all_findings JSON from tool files
  local all_findings='{}'
  for tool in "${TOOLS[@]}"; do
    local tool_findings
    tool_findings=$(cat "$FINDINGS_DIR/$tool.json")
    all_findings=$(echo "$all_findings" | jq --arg t "$tool" --argjson f "$tool_findings" '.[$t] = $f')
  done

  # Build empty match structure in one jq call
  local EMPTY_MATCH
  EMPTY_MATCH=$(printf '%s\n' "${TOOLS[@]}" | jq -Rs 'split("\n")[:-1] | reduce .[] as $t ({}; .[$t] = []) | {matched: [], unique: .}')

  # If total findings across all tools is 0, skip matching
  local total
  total=$(echo "$all_findings" | jq '[.[] | length] | add')
  if [ "$total" -eq 0 ] 2>/dev/null; then
    echo "$EMPTY_MATCH"
    return
  fi

  # Write findings to a temp file to avoid ARG_MAX limits with env vars
  local match_data_file="$FINDINGS_DIR/all_findings.json"
  echo "$all_findings" > "$match_data_file"

  # Use Python for deterministic file-path-based matching
  REVIEW_MATCH_FILE="$match_data_file" python3 << 'PYEOF'
import json, sys, os

with open(os.environ['REVIEW_MATCH_FILE'], 'r') as f:
    data = json.load(f)
tools = sorted(data.keys())

# Build a flat list of (tool, index, finding) with normalized file paths
all_items = []
for tool in tools:
    for idx, finding in enumerate(data.get(tool, [])):
        file_path = finding.get('file')
        norm = file_path
        all_items.append({
            'tool': tool,
            'idx': idx,
            'file': norm,
            'finding': finding,
        })

# Group by file path (findings about the same file from different tools)
file_groups = {}
for item in all_items:
    if item['file']:
        key = item['file']
        file_groups.setdefault(key, []).append(item)

matched = []
matched_set = set()  # (tool, idx) pairs that are matched

for file_path, items in file_groups.items():
    # Only count as match if 2+ DIFFERENT tools reference the same file
    tool_set = set(item['tool'] for item in items)
    if len(tool_set) < 2:
        continue

    # Build match group
    group_tools = sorted(tool_set)
    indices = {}
    for item in items:
        indices.setdefault(item['tool'], []).append(item['idx'])
        matched_set.add((item['tool'], item['idx']))

    # Use shortest description as unified description
    descriptions = [item['finding'].get('description', '') for item in items]
    unified = min(descriptions, key=len) if descriptions else ''

    matched.append({
        'description': unified,
        'file': file_path,
        'tools': group_tools,
        'indices': {t: idxs[0] if len(idxs) == 1 else idxs for t, idxs in indices.items()},
    })

# Collect unique findings (not matched with any other tool)
unique = {}
for tool in tools:
    unique[tool] = []
    for idx in range(len(data.get(tool, []))):
        if (tool, idx) not in matched_set:
            unique[tool].append(idx)

result = {'matched': matched, 'unique': unique}
print(json.dumps(result, ensure_ascii=False))
PYEOF
}

echo "Matching findings across tools..."
MATCH_RESULT=$(match_findings)

# Validate match result structure
if ! echo "$MATCH_RESULT" | jq -e '.matched and .unique' >/dev/null 2>&1; then
  MATCH_RESULT=$(printf '%s\n' "${TOOLS[@]}" | jq -Rs 'split("\n")[:-1] | reduce .[] as $t ({}; .[$t] = []) | {matched: [], unique: .}')
fi

MATCHED_COUNT=$(echo "$MATCH_RESULT" | jq '.matched | length')
echo "  Matched (2+ tools agree): $MATCHED_COUNT"
for tool in "${TOOLS[@]}"; do
  unique_count=$(echo "$MATCH_RESULT" | jq --arg t "$tool" '.unique[$t] // [] | length')
  echo "  Unique to $tool: $unique_count"
done

# ── Step 3: Correlate with git actions ───────────────────────────────

correlate_actions() {
  # Convert timestamp to git date format
  local review_date
  review_date=$(echo "$TIMESTAMP" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3T\4:\5:\6/')

  local files_changed_after
  files_changed_after=$(git log --after="$review_date" --name-only --pretty=format: 2>/dev/null | sort -u | grep -v '^$' || true)

  if [ -z "$files_changed_after" ]; then
    echo '[]'
    return
  fi

  # Build flat list of all findings with their tool attribution dynamically
  local all_findings_with_tools='[]'
  for tool in "${TOOLS[@]}"; do
    local tool_findings
    tool_findings=$(cat "$FINDINGS_DIR/$tool.json")
    all_findings_with_tools=$(echo "$all_findings_with_tools" | jq --arg t "$tool" --argjson f "$tool_findings" \
      '. + ($f | to_entries | map({tool: $t, idx: .key, finding: .value}))')
  done

  local total_findings
  total_findings=$(echo "$all_findings_with_tools" | jq 'length')
  if [ "$total_findings" -eq 0 ] 2>/dev/null; then
    echo '[]'
    return
  fi

  # Use jq to check all changed files at once instead of looping in bash
  local files_json
  files_json=$(echo "$files_changed_after" | jq -R -s 'split("\n") | map(select(. != ""))')

  echo "$all_findings_with_tools" | jq --argjson files "$files_json" \
    '[.[] | select(.finding.file != null) as $f |
      select($files | any(. as $path | ($path | endswith($f.finding.file)) or ($f.finding.file | endswith($path))))]'
}

echo "Correlating with post-review commits..."
ACTED_UPON=$(correlate_actions)

# Validate
if ! echo "$ACTED_UPON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  ACTED_UPON='[]'
fi

ACTED_COUNT=$(echo "$ACTED_UPON" | jq 'length')
echo "  Findings with subsequent file changes: $ACTED_COUNT"

# ── Step 4: Store results ────────────────────────────────────────────

BRANCH=$(git branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
  BRANCH=$(git describe --tags --exact-match HEAD 2>/dev/null || git rev-parse --short HEAD)
fi

# Build findings JSON and tools_models map dynamically
FINDINGS_JSON='{}'
TOOLS_MODELS='{}'
TOOLS_REASONING='{}'
for tool in "${TOOLS[@]}"; do
  tool_findings=$(cat "$FINDINGS_DIR/$tool.json")
  FINDINGS_JSON=$(echo "$FINDINGS_JSON" | jq --arg t "$tool" --argjson f "$tool_findings" '.[$t] = $f')
  # Read model sidecar file if present
  model_file="$REVIEW_DIR/${TIMESTAMP}-${tool}.model"
  if [ -f "$model_file" ]; then
    model_name=$(cat "$model_file" | tr -d '[:space:]')
    TOOLS_MODELS=$(echo "$TOOLS_MODELS" | jq --arg t "$tool" --arg m "$model_name" '.[$t] = $m')
  fi
  # Read reasoning sidecar file if present
  reasoning_file="$REVIEW_DIR/${TIMESTAMP}-${tool}.reasoning"
  if [ -f "$reasoning_file" ]; then
    reasoning_level=$(cat "$reasoning_file" | tr -d '[:space:]')
    TOOLS_REASONING=$(echo "$TOOLS_REASONING" | jq --arg t "$tool" --arg r "$reasoning_level" '.[$t] = $r')
  fi
done

REVIEW_ENTRY=$(jq -n \
  --arg ts "$TIMESTAMP" \
  --arg branch "$BRANCH" \
  --arg reviewer "$REVIEWER" \
  --arg review_type "$REVIEW_TYPE" \
  --argjson findings "$FINDINGS_JSON" \
  --argjson matching "$MATCH_RESULT" \
  --argjson acted "$ACTED_UPON" \
  --argjson tools_status "$TOOLS_STATUS" \
  --argjson tools_models "$TOOLS_MODELS" \
  --argjson tools_reasoning "$TOOLS_REASONING" \
  '{
    timestamp: $ts,
    branch: $branch,
    reviewer: $reviewer,
    review_type: $review_type,
    tools_status: $tools_status,
    tools_models: $tools_models,
    tools_reasoning: $tools_reasoning,
    findings: $findings,
    matching: $matching,
    acted_upon: $acted
  }')

# Append to analytics file (with error recovery)
if jq --argjson entry "$REVIEW_ENTRY" '.reviews += [$entry]' "$ANALYTICS_FILE" > "${ANALYTICS_FILE}.tmp"; then
  mv "${ANALYTICS_FILE}.tmp" "$ANALYTICS_FILE"
else
  echo "ERROR: Failed to update analytics file" >&2
  rm -f "${ANALYTICS_FILE}.tmp"
  exit 1
fi

echo ""
echo "Analysis saved to $ANALYTICS_FILE"
echo "IMPORTANT: Commit review-analytics.json to preserve cumulative data."
echo "Run '/review-stats' to see cumulative trends."
