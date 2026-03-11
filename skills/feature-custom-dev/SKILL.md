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

---

## Phase 4.5: Plan Review & Revision

**Goal**: Validate the architecture plan with external reviewers before implementation

**MANDATORY — DO NOT SKIP THIS PHASE. You MUST execute `/plan-review` using the Skill tool before proceeding to implementation.**

**Actions**:
1. **Execute `/plan-review` using the Skill tool** — pass the architecture plan as the argument. This is NOT optional. Do NOT summarize what plan-review would do — actually run it.
2. If reviewers identify critical findings (security gaps, missing edge cases, architectural issues):
   - **Revise the plan** to address those findings before proceeding
   - Re-run `/plan-review` via the Skill tool again if changes are substantial
3. Present revised plan to user for final approval

**GATE CHECK**: Before moving to Phase 5, confirm: "I executed `/plan-review` and addressed its findings." If you cannot confirm this, go back and run it now.

**CRITICAL**: Plan review is a gate, not just informational. Critical findings **must** be addressed in the plan before moving to implementation.

---

## Phase 5: Implementation

**Goal**: Build the feature

**DO NOT START WITHOUT USER APPROVAL**

**Actions**:
1. Wait for explicit user approval
2. Read all relevant files identified in previous phases
3. Implement following chosen architecture
4. Follow codebase conventions strictly
5. Write clean, well-documented code
6. Update todos as you progress

---

## Phase 6: Quality Review

**Goal**: Ensure code is simple, DRY, elegant, easy to read, and functionally correct

**MANDATORY — DO NOT SKIP `/test-more`. You MUST execute it using the Skill tool before proceeding to Phase 7.**

**Actions**:
1. **Execute `/test-more` using the Skill tool** — this runs the adversarial and comprehensive testing checklist. This is NOT optional. Do NOT just list what tests to write — actually invoke the skill so it drives the testing process.
2. Launch 3 code-reviewer agents in parallel with different focuses: simplicity/DRY/elegance, bugs/functional correctness, project conventions/abstractions
3. Review INSIGHTS.md pattern compliance — check changes against documented anti-patterns
4. Validate adherence to ARCHITECTURE.md
5. Consolidate findings and identify highest severity issues that you recommend fixing
6. **Present findings to user and ask what they want to do** (fix now, fix later, or proceed as-is)
7. Address issues based on user decision
8. **Iterate until**: all tests pass, no lint errors, frontend builds, all review comments addressed

**GATE CHECK**: Before moving to Phase 7, confirm: "I executed `/test-more` via the Skill tool and all critical test gaps have been addressed." If you cannot confirm this, go back and run it now.

---

## Phase 7: Summary & PR

**Goal**: Document what was accomplished and prepare for review

**Actions**:
1. Mark all todos complete
2. Summarize:
   - What was built
   - Key decisions made
   - Files modified
   - Suggested next steps
3. **Execute `/pr` using the Skill tool** to run the full PR preparation workflow (health checks, code quality, multi-review, integration testing, screenshots, and PR creation). Do NOT manually replicate what `/pr` does — invoke it via the Skill tool so it drives each phase.

---
