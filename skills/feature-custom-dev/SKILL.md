---
name: feature-custom-dev
description: Guided feature development with codebase understanding and architecture focus
argument-hint: Optional feature description
---

# Feature Development

You are helping a developer implement a new feature. Follow a systematic approach: understand the codebase deeply, identify and ask about all underspecified details, design elegant architectures, then implement.

## Core Principles

- **Ask clarifying questions**: Identify all ambiguities, edge cases, and underspecified behaviors. Ask specific, concrete questions rather than making assumptions. Wait for user answers before proceeding with implementation. Ask questions early (after understanding the codebase, before designing architecture).
- **Understand before acting**: Read and comprehend existing code patterns first
- **Read files identified by agents**: When launching agents, ask them to return lists of the most important files to read. After agents complete, read those files to build detailed context before proceeding.
- **Multi-model exploration**: Use Claude agents alongside external LLMs for broader perspective during exploration and architecture phases
- **Simple and elegant**: Prioritize readable, maintainable, architecturally sound code
- **Use TodoWrite**: Track all progress throughout
- **Auto-start Docker**: If Docker containers are not running when you need them (for tests, linting, builds, or any verification), start them yourself using `./start.sh` and `source env.sh`. Never ask the user to start Docker — just do it. Check `docker ps` to verify containers are up before running commands that depend on them.

---

## Phase 0: Fresh Branch from Main

**Goal**: Ensure we're starting from the latest `main` on a clean feature branch.

**Actions**:
1. **Always fetch and rebase first** — this runs unconditionally before anything else:
   ```bash
   git fetch origin main
   git rebase origin/main
   ```
   If there are uncommitted changes, commit or stash them first. If the rebase fails due to conflicts, stop and inform the user.
2. Check if we're already on a clean feature branch:
   ```bash
   CURRENT=$(git branch --show-current)
   # If on main, detached HEAD, or a branch from a previous feature — create a new branch
   ```
3. If needed, create a new feature branch from `origin/main`:
   - Derive a branch name from the feature description using the `patients/` prefix (e.g., `patients/add-health-dashboard`)
   - ```bash
     git checkout -b patients/<feature-slug> origin/main
     ```
   - If `git checkout` fails because `main` is checked out in another worktree, use:
     ```bash
     git checkout --detach origin/main && git checkout -b patients/<feature-slug>
     ```

**Skip this entire phase** (including the fetch+rebase) only if the user explicitly says to continue on the current branch without updating.

### Asana Ticket Tracking

After the branch is ready, check if `--asana-ticket <GID>` was passed in `$ARGUMENTS`:

- If provided: store the GID as `ASANA_TICKET_GID`. Fetch the task to get its name and URL:
  ```
  mcp__asana__get_task task_gid="<GID>"
  ```
  Move it to "In Progress" (look up the section by fuzzy name match within the task's project):
  ```
  mcp__asana__add_task_to_section task_gid="<GID>" section_gid="<in_progress_section_gid>"
  ```
  Confirm: "Moved **[task name]** → In Progress."
- If not provided: set `ASANA_TICKET_GID=""` and continue — Asana tracking is optional.

---

## Phase 1: Discovery

**Goal**: Understand what needs to be built

Initial request: $ARGUMENTS

**Actions**:
1. Create todo list with all phases
2. If feature unclear, ask user for:
   - What problem are they solving?
   - What should the feature do?
   - Any constraints or requirements?
3. Summarize understanding and confirm with user

---

## Phase 2: Codebase Exploration

**Goal**: Understand relevant existing code and patterns at both high and low levels, using multiple AI models for broader coverage

**Actions**:

### Claude Agents (launch in parallel, use extended thinking)
1. Launch 2 code-explorer agents in parallel with extended thinking enabled. Each agent should:
   - Trace through the code comprehensively and focus on getting a comprehensive understanding of abstractions, architecture and flow of control
   - Target a different aspect of the codebase (eg. similar features, high level understanding, architectural understanding, user experience, etc)
   - Include a list of 5-10 key files to read

   **Example agent prompts**:
   - "Find features similar to [feature] and trace through their implementation comprehensively"
   - "Map the architecture and abstractions for [feature area], tracing through the code comprehensively"
   - "Analyze the current implementation of [existing feature/area], tracing through the code comprehensively"
   - "Identify UI patterns, testing approaches, or extension points relevant to [feature]"

### External LLMs (launch in parallel with Claude agents)
2. Run all 3 external explore scripts in parallel via Bash (run in background). Use higher reasoning effort for exploration — deeper analysis of the codebase produces better plans:
   ```bash
   CODEX_REASONING=high .claude/scripts/codex-dev.sh --mode explore --task "<feature description>"
   ```
   ```bash
   .claude/scripts/gemini-dev.sh --mode explore --task "<feature description>"
   ```
   ```bash
   .claude/scripts/cursor-dev.sh --mode explore --task "<feature description>"
   ```

   Replace `<feature description>` with the actual task/feature being explored. If a script fails (tool not installed, credentials missing, timeout), check `.claude/logs/llm-errors.log` for details, report the failure cause to the user, and continue — external LLMs are supplementary.

### Consolidation
3. Once all agents and scripts return, read all files identified by agents to build deep understanding
4. Present comprehensive summary combining findings from all sources (Claude agents + external LLMs)

---

## Phase 3: Clarifying Questions

**Goal**: Fill in gaps and resolve all ambiguities before designing

**CRITICAL**: This is one of the most important phases. DO NOT SKIP.

**Actions**:
1. Review the codebase findings and original feature request
2. Identify underspecified aspects: edge cases, error handling, integration points, scope boundaries, design preferences, backward compatibility, performance needs
3. **Present all questions to the user in a clear, organized list**
4. **Wait for answers before proceeding to architecture design**

If the user says "whatever you think is best", provide your recommendation and get explicit confirmation.

---

## Phase 4: Architecture Design

**Goal**: Design multiple implementation approaches with different trade-offs, using multiple AI models

**Actions**:

### Claude Agents (launch in parallel, use extended thinking)
1. Launch 2 code-architect agents in parallel with extended thinking enabled. Different focuses: minimal changes (smallest change, maximum reuse), clean architecture (maintainability, elegant abstractions), or pragmatic balance (speed + quality)

### External LLMs (launch in parallel with Claude agents)
2. Run all 3 external architect scripts in parallel via Bash (run in background). Use higher reasoning effort for architecture — this shapes the entire implementation:
   ```bash
   CODEX_REASONING=high .claude/scripts/codex-dev.sh --mode architect --task "<feature description with context from exploration phase>"
   ```
   ```bash
   .claude/scripts/gemini-dev.sh --mode architect --task "<feature description with context from exploration phase>"
   ```
   ```bash
   .claude/scripts/cursor-dev.sh --mode architect --task "<feature description with context from exploration phase>"
   ```

   If a script fails (tool not installed, credentials missing, timeout), check `.claude/logs/llm-errors.log` for details, report the failure cause to the user, and continue.

### Consolidation
3. Review all approaches from Claude agents and external LLMs. Form your opinion on which fits best for this specific task (consider: small fix vs large feature, urgency, complexity, team context)
4. Present to user: brief summary of each approach, trade-offs comparison, **your recommendation with reasoning**, concrete implementation differences
5. **Ask user which approach they prefer**
6. When the architecture is approved, split work into subagent tasks where possible
7. **Save the approved plan to disk**:
   - Derive a kebab-case filename from the feature description (e.g., "LLM OCR Enhancement" → `llm-ocr-enhancement.md`)
   - Write the final approved architecture to `docs/plans/<name>.md` using the Write tool
   - The plan file should contain: Context, Key Files (to create, to modify, reference), Architecture, Implementation Details, a **QA Plan section**, and a **Production Validation section** (see below)
   - If `ASANA_TICKET_GID` is set, add an **Asana Ticket** line at the very top of the plan (before any other content):
     ```markdown
     **Asana Ticket:** [<task name>](https://app.asana.com/0/<project_gid>/<task_gid>) (`<task_gid>`)
     ```
   - Include /feature-custom-dev and /pr workflow steps into the plan directly. Adopt review cycles for the feature size.
   - **QA Plan section** — scope each item to the feature. Omit items not applicable (e.g. no design review for backend-only changes):
     ```markdown
     ## QA Plan
     ### RSpec Tests
     - [ ] Unit tests for new models/services/jobs (list specific classes)
     - [ ] Integration tests for new controller actions (list endpoints)
     - [ ] Edge cases: invalid inputs, nil/empty states, boundary values
     - [ ] Authorization: unauthorized access returns correct error
     - [ ] Background jobs: enqueued correctly, execute with correct args
     ### Playwright E2E Tests
     - [ ] Happy path flows (list specific user journeys)
     - [ ] Form validation and error states
     - [ ] Navigation edge cases (back, direct URL, refresh mid-flow)
     ### Design Review
     - [ ] Routes to review: (list affected routes, or "N/A — backend only")
     ### QA Validation
     - [ ] /gstack-qa on affected flows (or "N/A — backend only")
     ### Review Cycle
     - [ ] /review-cycle — mandatory for all features
     ```
   - **Production Validation section** — concrete, queryable signals that confirm the feature is working correctly after deploy. These should be runnable against the production database or observable in logs/dashboards without any code changes. Scope to this feature — every item must be specific and verifiable:
     ```markdown
     ## Production Validation
     ### Database Signals
     - SQL or Rails runner query to verify expected records exist (e.g. `SELECT count(*) FROM ...`)
     - Query to confirm no unexpected nulls, wrong states, or missing associations
     ### Background Jobs
     - Job class and expected queue: confirm enqueued after trigger (check GoodJob dashboard or query `good_jobs` table)
     - Expected completion: query for finished jobs within N minutes of trigger
     ### API / Endpoint Checks
     - Endpoint + expected response shape (e.g. `GET /api/v1/patients/:id/rollups` returns `{ rollups: [...] }`)
     - Any webhook or callback that should fire and what to look for in logs
     ### Feature Flags / Config
     - Any env var, feature flag, or seed data that must be present in production
     ### Error Signals (absence = healthy)
     - Sentry query or log pattern to confirm no new errors introduced (e.g. `is:unresolved <ClassName>`)
     ### Rollback Trigger
     - Condition under which to roll back: what broken looks like (e.g. error rate > X%, specific exception spiking)
     ```
   - Note the plan file path — you will pass it to subsequent phases
   - Tell the user: "Plan saved to `docs/plans/<name>.md`"

---

## Phase 4.5: Iterative Plan Review & Revision

**Goal**: Validate the architecture plan through iterative review passes until findings converge

**MANDATORY — DO NOT SKIP THIS PHASE. You MUST execute the iterative plan review loop before proceeding to implementation.**

### Completeness Principle

Before running the review loop, evaluate the plan for completeness:

**Ask these questions about the plan:**
- Is the plan doing the **full feature implementation with all edge cases covered**, or is it taking shortcuts? AI-assisted coding makes completeness cheap — 100% test coverage, full edge case handling, and complete error paths cost only marginally more than partial implementations.
- Does the plan defer work that could reasonably be done now? Flag any "we can add this later" items where the complete version is only modestly more effort.
- Does the plan cover all edge cases: invalid inputs, boundary values, error states, empty/nil states, concurrent access, unauthorized access?
- Are tests comprehensive — not just happy path, but adversarial scenarios designed to break the feature?

**Anti-patterns to flag in the plan:**
- Proposing a simpler approach that covers 90% when the complete approach is only modestly more work
- Skipping edge case handling
- Deferring test coverage to a follow-up PR
- Missing error paths or validation

**Present completeness findings to user before starting the review loop.**

### Review Loop (3–5 passes)

Initialize a `## Review Pass History` section at the bottom of the plan file (`docs/plans/<name>.md`). This is an append-only ledger that tracks every pass.

**For each pass (1 through 5):**

1. **Run `/plan-review`** via the Skill tool — pass the plan file path: `/plan-review --plan-file docs/plans/<name>.md`.
2. **Classify each finding** as:
   - **[NEW]** — not raised in any prior pass
   - **[DUPLICATE]** — same issue (or substantially similar) as a prior pass finding
3. **Append pass results** to the `## Review Pass History` section in the plan file:
   ```markdown
   ### Pass {N}
   - **New findings**: {count}
   - **Duplicate findings**: {count}
   - **Findings**:
     1. [NEW] {description} — {action taken}
     2. [DUPLICATE of Pass {M}.{item}] {description} — skipped
   - **Plan revisions**: {brief description of what changed in the plan body}
   ```
4. **Revise the plan body** (Architecture, Implementation Details, etc.) to address all [NEW] findings. Do NOT re-revise for [DUPLICATE] findings.
5. **Check convergence**:
   - `pass < 3` → **ALWAYS CONTINUE** (minimum 3 passes required)
   - `pass >= 3 AND new_findings == 0` → **STOP** (converged)
   - `pass >= 3 AND new_findings > 0 AND pass < 5` → **CONTINUE**
   - `pass == 5` → **STOP** (hard cap — flag any remaining [NEW] findings as unresolved)

### After loop completes

1. **Re-read the plan file** to see the full Review Pass History
2. If the loop hit the hard cap (pass 5) with remaining new findings, present them to the user for decision
3. Present the final revised plan to user for approval

**GATE CHECK**: Before moving to Phase 5, confirm: "I ran {N} plan review passes. Findings converged at pass {N} with zero new findings." (Or: "Hard cap reached at pass 5 with {X} unresolved findings — user approved proceeding.") If you cannot confirm this, go back and run the loop now.

**CRITICAL**: Plan review is a gate, not just informational. The loop must run at least 3 passes, and critical findings **must** be addressed in the plan before moving to implementation.

---

## Phase 5: Autonomous Execution (Default)

**Goal**: Automatically execute the approved plan without requiring user intervention.

**IMPORTANT**: Autonomous execution is the DEFAULT mode. Do NOT ask the user to choose between autonomous and interactive — proceed directly to autonomous execution after plan approval.

**Actions**:
1. Present a brief final plan summary to the user
2. Inform the user that autonomous execution is starting:

   > **Plan approved. Starting autonomous execution.**
   > I'll implement everything, write Playwright tests, run design review, QA, and create the PR — all without stopping. You'll get a final report when the PR is ready and CI is green.

3. **Start Ralph Loop for hands-free execution** using the Skill tool: `/ralph-loop "Continue autonomous execution. Read the plan file at docs/plans/<name>.md and the progress log at .claude/logs/autonomous/ to determine which phases are complete. Resume from the first incomplete phase and execute through to PR creation and green CI. Output <promise>AUTONOMOUS EXECUTION COMPLETE</promise> only when the PR exists and CI is green." --completion-promise "AUTONOMOUS EXECUTION COMPLETE" --max-iterations 3`

   Replace `<name>` with the actual plan filename. Ralph Loop re-invokes the same prompt each iteration — Claude reads its own progress log to resume from where it left off, without user nudging. This handles everything from implementation through PR creation. Skip Phases 6-9 below — they are all handled by the loop.

---

## Phase 6: Quality Review (Interactive Mode)

**Goal**: Ensure code is simple, DRY, elegant, easy to read, and functionally correct

**MANDATORY — DO NOT SKIP `/test-more`. You MUST execute it using the Skill tool before proceeding to Phase 7.**

**Actions**:
1. **Re-read the plan file** (`docs/plans/<name>.md`) to recover full context
2. **Execute `/test-more` using the Skill tool** — pass the plan file path: `/test-more --plan-file docs/plans/<name>.md`. This runs the adversarial and comprehensive testing checklist. This is NOT optional. Do NOT just list what tests to write — actually invoke the skill so it drives the testing process.
3. Launch 3 code-reviewer agents in parallel with different focuses: simplicity/DRY/elegance, bugs/functional correctness, project conventions/abstractions
4. Review INSIGHTS.md pattern compliance — check changes against documented anti-patterns
5. Validate adherence to ARCHITECTURE.md
6. Consolidate findings and identify highest severity issues that you recommend fixing
7. **Present findings to user and ask what they want to do** (fix now, fix later, or proceed as-is)
8. Address issues based on user decision
9. **Iterate until**: all tests pass, no lint errors, frontend builds, all review comments addressed
10. **Re-read the plan file** after test-more completes — it may have been updated with testing strategy

**GATE CHECK**: Before moving to Phase 7, confirm: "I executed `/test-more` via the Skill tool and all critical test gaps have been addressed." If you cannot confirm this, go back and run it now.

---

## Phase 7: Summary & PR (Interactive Mode)

**Goal**: Document what was accomplished and prepare for review

**Actions**:
1. Mark all todos complete
2. **Re-read the plan file** (`docs/plans/<name>.md`) for accurate summary
3. Summarize:
   - What was built
   - Key decisions made
   - Files modified
   - Suggested next steps
4. **Execute `/pr` using the Skill tool** to run the full PR preparation workflow (health checks, code quality, review cycle, integration testing, screenshots, and PR creation). Do NOT manually replicate what `/pr` does — invoke it via the Skill tool so it drives each phase.

---

## Phase 8: Workflow Retrospective

**Goal**: Collect feedback on how the development workflow and tooling performed.

**Actions**:

1. **Solicit feedback** — Ask the user using `AskUserQuestion`:

   > **Quick retro on this feature build:**
   >
   > 1. How did the workflow go? (0-10)
   > 2. What worked well?
   > 3. What was slow, frustrating, or broken in the tooling?
   >
   > (Brief is fine — even just a number and a few words.)

2. **Capture improvements** — Save to `tool-improvements/feature-dev-workflow.md` (append if exists):

   ```markdown
   ## YYYY-MM-DD — <feature name>
   **Rating:** <0-10>

   ### What worked
   - <from feedback>

   ### Tooling / workflow improvements
   - [ ] <actionable item>
   ```

---
