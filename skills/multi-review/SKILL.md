---
name: multi-review
description: Run multi-LLM code review using all configured CLI review tools (plus GitHub reviews if PR exists)
argument-hint: Optional change description
---

# Multi-Review (Multi-LLM)

Run a comprehensive code review using multiple LLMs in parallel (Claude subagent + all installed CLI review tools), optionally requesting GitHub PR reviews, then consolidate findings with cross-tool agreement analysis.

## Input

Change description: $ARGUMENTS

## Process

### Step 1: Summarize the change

Before running reviews, write a concise change summary. Write summary from the end-user perspective. Key components:
- **Goal**: What is this change trying to achieve? What problem does it solve?
- **Requirements**: What are the key user-facing or system-level requirements?
- **Approach**: How were the requirements implemented? What key design decisions were made?
- **Scope**: Which areas of the codebase were touched (backend, frontend, integrations, config)?

If `$ARGUMENTS` contains a description, use that. Otherwise, use the conversation history and `git diff main...HEAD` to build this summary. Store it in a variable:

```bash
CHANGE_SUMMARY="Goal: <what and why>. Requirements: <key requirements>. Approach: <how it was implemented>. Scope: <areas changed>."
```

### Step 2: Optionally ensure PR exists for GitHub reviews

If `MULTI_REVIEW_PUSH=1` is set (or this was invoked from `/pr`), push and ensure a PR exists:

```bash
if [ "${MULTI_REVIEW_PUSH:-0}" = "1" ]; then
  PR_NUMBER=$(./.claude/scripts/ensure-pr.sh)
  echo "PR #$PR_NUMBER ready for reviews"
  ./.claude/scripts/request-github-reviews.sh "$PR_NUMBER"
fi
```

**Always push and request Cursor BugBot & Copilot** — even without `MULTI_REVIEW_PUSH`, push to GitHub so Cursor BugBot and Copilot can review the PR in parallel with local CLI tools:

```bash
PR_NUMBER=$(./.claude/scripts/ensure-pr.sh)
echo "PR #$PR_NUMBER ready for reviews"
./.claude/scripts/request-github-reviews.sh "$PR_NUMBER"
```

### Step 3: Run CLI reviews in parallel

Launch all reviews concurrently:
- **Claude**: Use the Task tool with `subagent_type: "feature-dev:code-reviewer"` and `run_in_background: true`. Pass the CHANGE_SUMMARY and instruct the agent to review the branch diff against main. Focus on: bugs, race conditions, transaction safety, logic errors, security issues, CLAUDE.md compliance. Exclude: style/formatting, pre-existing code, issues below high confidence.
- **External CLI tools**: Run all available review scripts in a single Bash command:

```bash
export REVIEW_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REVIEW_FAILED=0
./.claude/scripts/codex-review.sh --description "$CHANGE_SUMMARY" &
CODEX_PID=$!
./.claude/scripts/gemini-review.sh --description "$CHANGE_SUMMARY" &
GEMINI_PID=$!
wait $CODEX_PID   || REVIEW_FAILED=1
wait $GEMINI_PID  || REVIEW_FAILED=1
[ $REVIEW_FAILED -eq 0 ] || echo "WARNING: One or more reviews failed"
```

**Prerequisites**: Each CLI tool must be installed (see `.claude/DEVELOPER-TOOLS.md`). If a tool fails (not installed, credentials missing, timeout, or other error), check `.claude/logs/llm-errors.log` for details and report the failure cause to the user. The failed tool's review will be skipped but other reviews continue.

### Step 4: Save Claude subagent output

After the Claude subagent completes, read its output and save it to the reviews directory so the analytics pipeline can process it alongside CLI tool outputs. Use the Read tool to get the subagent's output_file, then write it:

```bash
# Write the Claude subagent output and model metadata to the reviews directory
cat <<'REVIEW_EOF' > ".claude/reviews/${REVIEW_TIMESTAMP}-claude.txt"
<paste the subagent's returned text here>
REVIEW_EOF
echo "claude-opus-4-6" > ".claude/reviews/${REVIEW_TIMESTAMP}-claude.model"
```

The output must follow the standard review format so the parser can extract findings:
```
### Code Review Results

Found N issues:

1. Description
   File: `path/to/file.rb:line`
   Confidence: 75-100
```

If the subagent returned no issues, write:
```
### Code Review Results

No issues found. Checked for bugs and CLAUDE.md compliance.
```

### Step 5: Harvest GitHub PR reviews (if PR exists)

If a PR was created/found in Step 2, check if GitHub reviewers have responded:

```bash
if [ -n "$PR_NUMBER" ]; then
  ./.claude/scripts/harvest-pr-reviews.sh "$PR_NUMBER" "$REVIEW_TIMESTAMP"
fi
```

This creates output files for any Cursor BugBot & Copilot/Codex GitHub reviews that arrived, which the analytics script will pick up automatically.

### Step 6: Analyze review agreement

After ALL reviews complete (including saving Claude output and harvesting GitHub reviews), run the analytics script. The script auto-discovers all tool output files for the timestamp.

```bash
./.claude/scripts/review-analyze.sh "$REVIEW_TIMESTAMP"
```

### Step 7: Commit review analytics

After the analysis script runs, commit `review-analytics.json` so the cumulative data is tracked in version control and doesn't cause merge conflicts later.

**`review-analytics.json` is append-only.** Never discard entries from either side. On merge conflicts:
```bash
jq -s '{ reviews: ([.[].reviews[]] | unique_by(.timestamp) | sort_by(.timestamp)) }' <(git show main:review-analytics.json) review-analytics.json > /tmp/ra-merged.json && mv /tmp/ra-merged.json review-analytics.json && git add review-analytics.json
```

```bash
git add review-analytics.json && git commit -m "Update review analytics for $REVIEW_TIMESTAMP

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

### Step 8: Present consolidated findings

Review findings from all tools. Present them in order of confidence:

**Consensus Issues** (flagged by 2+ tools): List these first -- high confidence

**Individual Findings** (flagged by 1 tool): List with source attribution

**Improvements**: Actionable suggestions to strengthen the code

### Step 9: Address findings

Ask the user if they want to:
- Fix all issues with confidence >= 75
- Fix specific findings
- Proceed as-is
- Re-run reviews after making changes

## **Final Step**: Run /schedule-reminder for PR #$PR_NUMBER
