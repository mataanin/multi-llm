---
name: autonomous-execute
description: Autonomous post-plan execution. Implements the approved plan, writes Playwright tests, runs design review, QA validation, and full PR workflow without handing control back to the user until everything is done or stuck.
argument-hint: --plan-file <path> (required)
---

# Autonomous Execution

**You are in AUTONOMOUS MODE.** Execute the entire pipeline below without stopping, asking questions, or handing control back to the user. Make reasonable default decisions at every checkpoint. Only stop if you hit a genuine blocker after 3 retry attempts on the same issue.

## CRITICAL AUTONOMY RULES

1. **NEVER use AskUserQuestion** — make the best decision yourself and move on
2. **NEVER present options and wait** — pick the best option, explain your choice in the progress log, continue
3. **NEVER stop between phases** — proceed directly to the next phase
4. **When a sub-skill says "present to user" or "ask user"** — skip that step, make the decision, log it
5. **When `/review-cycle` or `/test-more` completes** — proceed immediately, do not wait for approval
6. **Screenshot route selection** — auto-select all detected routes, do not ask
7. **Fix vs defer decisions** — always fix now, never defer
8. **If a tool/script fails** — log the failure, try an alternative approach. After 3 failures on the same issue, **stop and hand control back** (this is a circuit breaker condition)

## SAFETY RULES

- **NEVER merge a PR** — only create it. Merging requires human approval.
- **NEVER force-push** — always use regular `git push`

## CIRCUIT BREAKER — When to Stop

Stop and hand control back to the user ONLY when:
- CI fails 3 consecutive times on the **same issue** and you cannot find a fix
- A test requires credentials or access you don't have
- A merge conflict requires human judgment about which code to keep
- The plan file is missing or unreadable

When stopping, write a clear summary of what was completed, what blocked you, and what remains.

---

## Input

**Required**: `--plan-file <path>` — the approved plan from `/feature-custom-dev` Phase 4.5

**Actions**:
1. Read the plan file to recover full context
2. Parse the plan into a checklist of discrete implementation items
3. Initialize the progress log at `.claude/logs/autonomous/<plan-name>-<date>.md`
4. Verify Docker is running (`docker ps`). If not, run `./start.sh && source env.sh`
5. **Asana ticket**: Check if the plan file has an `**Asana Ticket:**` line at the top. If present, extract the task GID and ensure it is in the "In Progress" section:
   ```
   mcp__asana__get_task task_gid="<GID>"
   ```
   Check `memberships[].section.name` — if not already "In Progress", move it:
   ```
   mcp__asana__add_task_to_section task_gid="<GID>" section_gid="<in_progress_section_gid>"
   ```
   Log to the progress log: `Asana ticket <GID> confirmed In Progress`. Skip silently if no ticket in plan.

### Resume / Ralph Loop Support

This skill is designed to run inside a **Ralph Loop** for hands-free execution. Each iteration Claude sees its own previous work (progress log, git history, todos) and picks up where it left off.

**Invoke via Ralph Loop:**
```
/ralph-loop "Continue autonomous execution. Read the plan file at docs/plans/<name>.md and the progress log at .claude/logs/autonomous/ to determine which phases are complete. Resume from the first incomplete phase and execute through to PR creation. Output <promise>AUTONOMOUS EXECUTION COMPLETE</promise> only when the PR exists and CI is green." --completion-promise "AUTONOMOUS EXECUTION COMPLETE" --max-iterations 3
```

**Resume logic** (runs at the start of every iteration):
1. Find the latest progress log: `ls -t .claude/logs/autonomous/*.md | head -1`
2. Read it to identify the last completed phase
3. Skip all completed phases and resume from the first incomplete one
4. If no progress log exists, start from Phase 1

**Completion signal**: Output `<promise>AUTONOMOUS EXECUTION COMPLETE</promise>` at the end of Phase 9 so Ralph Loop stops automatically.

---

## Phase 1: Implementation

**Goal**: Complete every item in the approved plan

**Actions**:
1. Re-read the plan file (`docs/plans/<name>.md`)
2. Read all relevant files identified in the plan
3. Create a TodoWrite checklist from the plan's implementation items
4. Implement each item sequentially, updating todos as you go
5. Follow codebase conventions strictly (see CLAUDE.md)
6. **After every TodoWrite task you mark complete, run the relevant tests immediately — do not batch across tasks:**
   - If the task modified any backend file: `source env.sh && docker exec $PATIENT_BACKEND bundle exec rspec <spec_paths>`. Run rspec for the spec file corresponding to each modified production file (e.g., `app/services/foo.rb` → `spec/services/foo_spec.rb`). If a modified file has no corresponding spec, note it and continue.
   - If the task modified any frontend file: `source env.sh && docker exec $PATIENT_FRONTEND npm run lint`
   - If the task modified both backend and frontend files: run both.
   - Do not wait until the end of the phase. A task is "complete" only after its tests run clean.
7. Log progress to `.claude/logs/autonomous/<plan-name>-<date>.md` after each major item

**GATE**: Do NOT proceed to Phase 2 until ALL plan items are implemented and their unit/integration tests pass. If a plan item is blocked, log it and continue with the next item, then return to blocked items.

---

## Phase 2: Mandatory Playwright Tests (Frontend Features)

**Skip this phase if the feature has NO frontend changes** (check `git diff main...HEAD --name-only | grep patient-portal/frontend/src/`), **OR if the plan's `## QA Plan → Playwright E2E Tests` section is marked "N/A"**. Read the plan file to check before proceeding.

**Goal**: Write and execute comprehensive Playwright E2E tests for all frontend flows introduced or modified.

**Use the `playwright-testing` skill patterns** (helpers, fixtures, config) for all test files.

### Step 1: Identify All Frontend Flows

Analyze the plan and the code changes to identify:
- Every new UI screen or component
- Every modified user flow
- Form submissions, navigation flows, modal interactions
- Admin and patient-facing flows separately

### Step 2: Write Key Flow Tests

For each identified flow, write a Playwright test file in `patient-portal/e2e/tests/smoke/`:

**Each test file MUST include:**
- Happy path with full database verification
- Form validation error handling (submit without required fields)
- Navigation edge cases (back button, direct URL access, refresh mid-flow)

### Step 3: Write Edge Case & Adversarial Tests

For each flow, add adversarial scenarios:
- Duplicate submissions (double-click protection)
- Navigate directly to later steps (skip prerequisites)
- Refresh page mid-flow (state persistence)
- Session expiry during multi-step flow
- Invalid data that passes frontend validation but fails backend
- Empty states (no data, no records)
- Boundary values (max-length strings, special characters)

### Step 4: Execute All Tests

**CRITICAL: Restart frontend container first** to clear webpack cache:
```bash
source env.sh
docker restart $PATIENT_FRONTEND
sleep 10
docker logs $PATIENT_FRONTEND --tail 5
# Verify "webpack compiled" appears
```

Then run tests:
```bash
cd patient-portal/e2e && npx playwright test tests/smoke/
```

Fix any failures. Re-run until all pass. Max 3 fix-rerun cycles per test file.

### Step 5: Log Coverage

Append to `.claude/logs/autonomous/<plan-name>-<date>.md`:
```
## Playwright Tests
- Files created: [list]
- Key flows covered: [list]
- Edge cases covered: [list]
- All passing: yes/no
```

---

## Phase 3: Review Cycle (Local + GitHub Reviews)

**MANDATORY — DO NOT SKIP. You MUST execute `/review-cycle` using the Skill tool.** This is the single review entry point: it pushes to GitHub, creates/finds the PR, runs all local LLM reviews (Claude + Codex + Gemini + Cursor), waits for and harvests GitHub bot reviews (Cursor BugBot, Copilot), then iterates fix-verify cycles until findings converge. Do NOT manually replicate what `/review-cycle` does — invoke it via the Skill tool so it drives each step.

**GATE CHECK**: Before moving to Phase 4, confirm: "I executed `/review-cycle` via the Skill tool and both tracks converged." If you cannot confirm this, go back and run it now.

---

## Phase 4: Mandatory Design Review (UI Changes)

**Skip this phase if the feature has NO frontend changes, OR if the plan's `## QA Plan → Design Review` section is marked "N/A — backend only"**. Read the plan file to check before proceeding.

**Goal**: Run `/web-design-reviewer` on every new or modified UI screen.

### Step 1: Ensure Frontend Is Running

```bash
source env.sh
docker restart $PATIENT_FRONTEND
sleep 10
docker logs $PATIENT_FRONTEND --tail 5
# Verify webpack compiled
```

### Step 2: Identify Affected Routes

```bash
git diff main...HEAD --name-only | grep -E 'patient-portal/frontend/src/'
```

Map changed files to routes using `Paths.ts`, `AppRoutes.tsx`, `DialogRoutes.tsx`.

### Step 3: Run Web Design Review

**Execute `/web-design-reviewer` using the Skill tool** for each affected route. Provide the URL:
- Patient routes: `$FRONTEND_URL/<route>`
- Admin routes: `$FRONTEND_URL/provider/<route>`

The skill will:
1. Navigate and screenshot each viewport (mobile 375px, tablet 768px, desktop 1280px)
2. Identify layout, responsive, accessibility, and visual consistency issues
3. Fix issues at the source code level
4. Re-verify after fixes

### Step 4: Responsive Spot-Checks

For every new component, verify at all 3 breakpoints (375px, 768px, 1280px). Use the design reviewer's viewport testing — do not skip any viewport.

### Step 5: Log Results

Append to `.claude/logs/autonomous/<plan-name>-<date>.md`:
```
## Design Review
- Routes reviewed: [list]
- Issues found: [count]
- Issues fixed: [count]
- Remaining issues: [list or "none"]
```

---

## Phase 5: Mandatory QA Validation

**Skip this phase if the plan's `## QA Plan → QA Validation` section is marked "N/A — backend only"**. Read the plan file to check before proceeding.

**Goal**: Run `/gstack-qa` for comprehensive application-level QA beyond unit and E2E tests.

### Step 1: Run QA

**Execute `/gstack-qa` using the Skill tool** with the Standard tier. Provide the frontend URL:
- Target: `$FRONTEND_URL`
- Focus on flows affected by this feature

The QA skill will:
1. Systematically test the application
2. Identify bugs
3. Fix bugs in source code, committing each fix atomically
4. Re-verify after each fix

### Step 2: Address Findings

- All critical and high severity bugs: fix immediately
- Medium severity bugs: fix immediately
- Low/cosmetic: fix if quick (< 5 min), otherwise log for later

### Step 3: Log Results

Append to `.claude/logs/autonomous/<plan-name>-<date>.md`:
```
## QA Validation
- Health score: before [X] → after [Y]
- Bugs found: [count]
- Bugs fixed: [count]
- Deferred: [list or "none"]
```

---

## Phase 6: Final Verification Gate

**Goal**: Verify ALL plan items are complete and all mandatory checks pass before entering PR workflow.

### Checklist (ALL must pass):

```bash
# 1. All RSpec tests pass
source env.sh && docker exec $PATIENT_BACKEND bundle exec rspec

# 2. Frontend lint passes
source env.sh && docker exec $PATIENT_FRONTEND npm run lint

# 3. Frontend builds
source env.sh && docker exec $PATIENT_FRONTEND npm run build

# 4. Playwright E2E tests pass (if frontend changes)
cd patient-portal/e2e && npx playwright test tests/smoke/
```

### Plan Completion Audit

1. Re-read the plan file
2. Verify every implementation item is done (check todos)
3. Verify Playwright tests exist for all frontend flows
4. Verify design review was run for all UI routes
5. Verify QA was run and findings addressed

**If any item is incomplete**: go back and complete it now. Do NOT proceed to `/pr`.

### Log Final Status

Append to `.claude/logs/autonomous/<plan-name>-<date>.md`:
```
## Verification Gate
- All plan items complete: yes/no
- RSpec: pass/fail
- Lint: pass/fail
- Build: pass/fail
- Playwright E2E: pass/fail (or N/A)
- Design review: complete/N/A
- QA validation: complete
- Review cycle: converged (local cycle N, github cycle N)
- READY FOR PR: yes/no
```

---

## Phase 7: PR Workflow

**Goal**: Run the full `/pr` skill workflow.

### Pre-PR Reinforcement

Before executing `/pr`, set context for the PR skill:

**The following checks have ALREADY been completed in autonomous execution. Do NOT re-run them during `/pr`:**
- Playwright E2E tests: already written and passing (Phase 2)
- `/review-cycle`: already run and converged (Phase 3) — **skip `/pr` Phase 3 (Review Cycle)**
- `/web-design-reviewer`: already run on all routes (Phase 4)
- `/gstack-qa`: already run with findings fixed (Phase 5)
- `/test-more`: will be run by `/pr` Phase 4 as a final adversarial check

**Execute `/pr` using the Skill tool.**

During `/pr` execution:
- Phase 1 (Health Check): let it run — quick verification
- Phase 2 (Code Quality): let it run — final lint/test/build check
- Phase 2.5 (Push & Reviews): let it run — pushes to GitHub (PR already exists from Phase 3)
- Phase 3 (Review Cycle): **SKIP** — already completed in Phase 3 above
- Phase 4 (Integration Testing): `/test-more` should reference the plan file. Playwright tests already exist. Run existing tests, don't rewrite them.
- Phase 4.5 (Screenshots): auto-select ALL detected routes (do not ask)
- Phase 5 (PR Creation): let it run
- Phase 6 (CI Fixes): fix up to 3 times, then stop
- Retrospective: skip (we are in autonomous mode)

---

## Phase 8: CI Verification

**Goal**: Ensure CI is green on the PR.

### Actions:

1. Check CI status:
   ```bash
   gh run list --limit 5
   ```
2. If any failures, view logs and fix:
   ```bash
   gh run view <run-id> --log-failed
   ```
3. After fixing, push and re-check. Max 3 fix cycles.
4. If CI passes: proceed to completion.
5. If CI fails 3 times on the same issue: stop and report to user.

---

## Phase 9: Completion

**Goal**: Report final status to the user.

### Actions:

1. Write final summary to `.claude/logs/autonomous/<plan-name>-<date>.md`
2. Output to the user:

```
AUTONOMOUS EXECUTION COMPLETE

Plan: <plan file path>
PR: <PR URL>
CI: <green/red>

Implementation:
- [x] All plan items completed
- [x] Playwright E2E tests written and passing
- [x] Design review completed on all UI routes
- [x] QA validation completed
- [x] Review cycle converged
- [x] CI passing

Decisions made autonomously:
- <list of key decisions from the log>

Items that may need your attention:
- <any deferred items or concerns>
```

3. Present the PR URL for final human review.
4. Output the completion signal for Ralph Loop:

```
<promise>AUTONOMOUS EXECUTION COMPLETE</promise>
```
