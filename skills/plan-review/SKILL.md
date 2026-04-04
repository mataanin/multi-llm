---
name: plan-review
description: Review an implementation plan using all configured external LLM tools
argument-hint: The implementation plan text to review
---

# Plan Review

Review the proposed implementation plan using multiple external LLMs to validate correctness, completeness, and feasibility against the actual codebase.

## Input

Plan to review: $ARGUMENTS

If no plan text is provided via arguments, ask the user to paste or describe their implementation plan.

**Plan file**: If the arguments include `--plan-file <path>`, read that file to get the current plan and note the path for updating later. If no `--plan-file` is provided, the plan will not be persisted to disk.

## Process

### Step 1: Run External Plan Reviews

Launch all external LLM plan review scripts in parallel via Bash (run in background). Use higher reasoning effort for plan review — this is a critical gate where deeper analysis pays off:

```bash
CODEX_REASONING=high .claude/scripts/codex-dev.sh --mode plan-review --plan "<plan text>" &
CODEX_PID=$!
CODEX_REASONING=high .claude/scripts/codex-dev.sh --mode adversarial-plan-review --plan "<plan text>" &
CODEX_ADV_PID=$!
.claude/scripts/gemini-dev.sh --mode plan-review --plan "<plan text>" &
GEMINI_PID=$!
.claude/scripts/cursor-dev.sh --mode plan-review --plan "<plan text>" &
CURSOR_PID=$!
wait $CODEX_PID $CODEX_ADV_PID $GEMINI_PID $CURSOR_PID
```

The adversarial Codex run assumes the plan will fail and targets hidden dependencies, missing guards, race conditions, and test gaps — a different lens from the regular plan review.

Replace `<plan text>` with the working plan for the implementation. Properly escape quotes in the plan text.

If a script fails (tool not installed, credentials missing, timeout), check `.claude/logs/llm-errors.log` for details, report the failure cause to the user, and continue with available tools.

### Step 2: Consolidate Results

Once all scripts return, consolidate findings across all reviewers:

1. **Correctness Issues** - Merge all inaccuracies found, deduplicate, note which reviewers flagged each
2. **Missing Pieces** - Combine all gaps identified, prioritize by severity
3. **Test Coverage Gaps** - Identify critical flows and edge cases that lack test plans (see Test Assessment below)
4. **Risk Assessment** - Consolidate risks, rank by frequency (issues flagged by multiple reviewers are higher priority)
5. **Convention Violations** - Merge all CLAUDE.md and pattern deviations
6. **Suggested Improvements** - Collect actionable improvements, deduplicate

### Step 3: Present Findings

Present a unified review to the user:

**Consensus Issues** (flagged by 2+ reviewers): List these first — high confidence

**Individual Findings** (flagged by 1 reviewer): List with source attribution

**Test Assessment** — Evaluate the plan's testing strategy with an adversarial mindset:
- Does the plan include RSpec unit and integration tests for all critical backend logic?
- Does the plan include Playwright test files (not just manual automation) for critical UI flows? (See `playwright-testing` skill for templates and patterns)
- Are edge cases covered: invalid inputs, boundary values, error states, unauthorized access, empty/nil states, concurrent submissions?
- Are adversarial scenarios addressed: what would break this feature? What gaps exist?
- Are post-implementation verifications planned: jobs, emails, database state?
- **Produce a list of specific test cases the plan should include** — both RSpec and Playwright — organized by:
  - Critical path tests (happy path flows that must work)
  - Edge case tests (boundary conditions, empty states, validation)
  - Adversarial tests (designed to break the functionality or expose gaps)

**Improvements**: Actionable suggestions to strengthen the plan

**Verdict**: Is the plan ready for implementation, or does it need revision?

### Step 4: Update Plan File

If a `--plan-file <path>` was provided:
1. Read the current plan file
2. Append a `## Plan Review Findings` section (or update it if one already exists) containing:
   - **Consensus issues** flagged by 2+ reviewers and how they were addressed
   - **Critical individual findings** that were incorporated
   - **Testing gaps identified** — specific test cases recommended
   - **Verdict** — whether the plan was approved as-is or revised
3. Write the updated plan back to the same file path

### Step 5: Iterate

Ask the user if they want to:
- Revise the plan and re-review
- Proceed with implementation as-is
- Address specific findings before proceeding

## **Final Step**: Run /schedule-reminder for PR #$PR_NUMBER
