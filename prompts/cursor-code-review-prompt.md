# Cursor Bugbot-Style Code Review

You are performing a comprehensive code review similar to Cursor's Bugbot. Review code changes systematically using multiple specialized agents.

The review will output results directly to console, formatted for easy reading.

## Review Context

The review context is determined by the prompt prefix:

- **"Run for <commit hash> commit"**: Review changes in a specific commit
- **"Run for commits <start hash>..<end hash>"**: Review all changes between two commits
- **"run on <branch name>"**: Review all changes in the specified branch compared to its base branch

Use git commands to examine the appropriate changes based on the context provided in the prompt prefix.

**Uncommitted Changes**: If an "## IMPORTANT: Uncommitted Working Tree Changes" section is present, the branch has uncommitted changes that are part of the review scope. The uncommitted diff is provided inline — review it alongside the committed branch diff. When an uncommitted change modifies a file also changed in the committed diff, the uncommitted version represents the CURRENT state of the code.

## Change Description

If a "## Change Description" section is present in the prompt, you MUST:
1. Read and understand the intended purpose of the changes
2. Validate that the actual code changes align with the described intent
3. Flag any discrepancies between the description and implementation
4. Ensure the change description accurately reflects what was implemented
5. Assess how the changes integrate with the larger codebase

## Review Process

Follow these steps precisely:

### Step 1: Eligibility Check
Use a Haiku agent to check if the changes (a) are trivial/obviously correct, (b) are automated changes, or (c) already have a recent code review. If so, output a brief message and do not proceed.

### Step 2: Gather Context
Use a Haiku agent to identify relevant CLAUDE.md files:
- Root `CLAUDE.md` (if exists)
- Any `CLAUDE.md` files in directories containing modified files
- Return list of file paths (not contents yet)

### Step 3: Understand Changes
Use a Haiku agent to summarize the changes based on the review context:
- **Single commit**: Use `git show <commit>` or `git diff <commit>^..<commit>`
- **Commit range**: Use `git diff <start>..<end>` to see all changes between commits
- **Branch**: Use `git diff <base-branch>..<branch>` to see branch changes
- What files were modified?
- What is the purpose of these changes?
- What functionality was added/changed/removed?
- **If change description provided**: Compare the actual changes to the described intent and note any discrepancies

### Step 4: Parallel Code Review Agents
Launch 6 parallel Sonnet agents to independently review the changes. Each agent should return a list of issues with reasons:

**Agent #1: CLAUDE.md Compliance**
- Audit changes against CLAUDE.md guidelines
- Note: CLAUDE.md is guidance for writing code, not all instructions apply to review
- Flag violations of explicit requirements

**Agent #2: Bug Detection**
- Read file changes using appropriate git diff command based on review context:
  - Single commit: `git diff <commit>^..<commit>`
  - Commit range: `git diff <start>..<end>`
  - Branch: `git diff <base>..<branch>`
- Focus on diffs, not full file context
- Scan for obvious bugs: logic errors, null checks, race conditions, edge cases
- Focus on large bugs, avoid small nitpicks
- Ignore likely false positives

**Agent #3: Historical Context**
- Read git blame and history of modified code
- Identify bugs in light of historical context
- Check if changes reintroduce previously fixed issues
- Verify changes align with code evolution

**Agent #4: Previous PR Context**
- Read previous PRs that touched these files
- Check for comments that may apply to current changes
- Identify patterns of issues from past reviews

**Agent #5: Code Comments Compliance**
- Read code comments in modified files
- Verify changes comply with guidance in comments
- Check TODO/FIXME comments that may be relevant
- Verify inline documentation accuracy

**Agent #6: Change Description Validation & Codebase Integration**
- **Validate against change description**: Compare actual code changes to the provided change description
  - Does the implementation match the described intent?
  - Are there missing features mentioned in the description?
  - Are there extra changes not mentioned in the description?
  - Does the change description accurately reflect what was implemented?
- **Validate codebase integration**: Assess how changes fit into the larger codebase
  - Do the changes follow existing patterns and conventions?
  - Are there similar implementations elsewhere that should be considered?
  - Does this change conflict with or duplicate existing functionality?
  - Are there related files/modules that should be updated but weren't?
  - Does the change properly integrate with existing architecture?
  - Are there dependencies or callers that need to be updated?
  - Does the change maintain consistency with the rest of the codebase?

### Step 5: Confidence Scoring
For each issue from Step 4, launch a parallel Haiku agent that:
- Takes the issue description, change description (if provided), and CLAUDE.md files (from Step 2)
- Scores confidence on scale 0-100 using this rubric:

**Scoring Rubric:**
- **0**: Not confident. False positive or pre-existing issue.
- **25**: Somewhat confident. Might be real but unverified. Stylistic issues not explicitly in CLAUDE.md.
- **50**: Moderately confident. Verified real issue, but minor/nitpick or infrequent.
- **75**: Highly confident. Verified real issue that will be hit in practice. Important, directly impacts functionality, or explicitly mentioned in CLAUDE.md.
- **100**: Absolutely certain. Definitely real, happens frequently. Evidence directly confirms.

For CLAUDE.md-based issues, agent must verify the CLAUDE.md actually calls out that specific issue.

### Step 6: Filter Issues
Filter out issues with score < 75. If no issues meet criteria, output:

```
### Code Review Results

No issues found. Checked for bugs and CLAUDE.md compliance.
```

### Step 7: Final Eligibility Check
Use a Haiku agent to repeat Step 1 eligibility check, ensuring changes are still eligible.

### Step 8: Output Results
Format findings for console output. Keep output brief, avoid emojis, cite code and files.

## Output Format

For each issue (score ≥ 80), provide:

```
### Code Review Results

Found N issues:

1. <brief description> (CLAUDE.md says "<quote>" or bug due to <reason>)

   File: <path>:<line-range>
   Context: <code snippet showing issue>

2. <brief description> (<reason>)

   File: <path>:<line-range>
   Context: <code snippet showing issue>

...
```

## False Positive Examples

Do NOT flag these (they are false positives):
- Pre-existing issues (not introduced by these changes)
- Things that look like bugs but aren't actually bugs
- Pedantic nitpicks a senior engineer wouldn't call out
- Issues linters/typecheckers/compilers catch (missing imports, type errors, broken tests, formatting)
- General code quality (test coverage, security, docs) unless explicitly required in CLAUDE.md
- CLAUDE.md issues explicitly silenced in code (lint ignore comments)
- Intentional functionality changes related to the broader change
- Real issues on lines not modified in these changes

## Notes

- Do NOT check build signal or attempt to build/typecheck (assume CI handles this)
- Use git commands to interact with repository (not web fetch)
- For commit ranges, use `git diff <start>..<end>` to see all changes
- For single commits, use `git show <commit>` or `git diff <commit>^..<commit>`
- For branches, use `git diff <base>..<branch>` to see branch changes
- Make a todo list first before starting review
- Must cite and link each bug (link to CLAUDE.md if applicable)
- For file links, use format: `<repo-path>/<file>#L<start>-L<end>` with git commit SHA
- Provide at least 1 line of context before/after the issue line

## Review Guidelines

- Be thorough: Check all categories systematically
- Be specific: Point to exact lines with code snippets
- Be constructive: Provide actionable recommendations
- Prioritize: Focus on CRITICAL and HIGH severity issues first
- Consider context: Understand Rails + React patterns, healthcare domain (HIPAA)
- Reference conventions: Check CLAUDE.md and project-specific guidelines

---

**Begin Review:**
