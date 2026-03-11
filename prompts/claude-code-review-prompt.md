# Claude Code Review

Perform a systematic, comprehensive code review as a single agent. Review all key categories in one thorough sequential pass. Output results directly to the console, formatted for clarity.

## Review Context

Determine the scope using the prompt prefix:

- **"Run for <commit hash> commit"**: Review the single commit's changes
- **"Run for commits <start hash>..<end hash>"**: Review all changes in the commit range
- **"run on <branch name>"**: Review branch changes against its base branch

Use relevant git commands for your analysis.

## Change Description

If a "## Change Description" section exists:
1. Read and understand the stated intent.
2. Validate if code changes align with the description.
3. Flag discrepancies between description and implementation.
4. Ensure the description accurately represents the changes.
5. Assess integration with the codebase.

## Review Steps

### 1: Eligibility Check
If any of these apply -- changes are trivial/obviously correct, automated, or recently reviewed -- output a brief message and stop.

### 2: Context Gathering
Check for relevant `CLAUDE.md` files:
- Root file (if any)
- Any in directories of modified files
- Review these for guidelines

### 3: Change Understanding
Summarize based on review context:
- **Single commit:** `git show <commit>` or `git diff <commit>^..<commit>`
- **Range:** `git diff <start>..<end>`
- **Branch:** `git diff <base-branch>..<branch>`
- Which files changed?
- What is the intent?
- What functionality changed?
- If change description present, compare and note discrepancies

### 4: Comprehensive Code Review
Review changes across all of the following categories:

1. **CLAUDE.md Compliance**
   - Compare code to explicit relevant guidelines
   - Flag violations of explicit requirements
2. **Bug Detection**
   - Focus on significant logic errors, edge cases, and race conditions; skip minor nitpicks
3. **Historical Context**
   - Use `git blame` and `git log` to review the history of modified code sections
   - Check if changes reintroduce previously fixed issues
   - Verify changes align with the code's evolution
4. **Previous PR Context**
   - Review past PRs that touched these files for relevant comments
   - Identify patterns of issues from past reviews
5. **Code Comments Compliance**
   - Ensure changes respect existing comments, TODOs, and inline documentation
6. **Description Validation & Codebase Integration**
   - Confirm changes match the description, follow conventions, and update dependencies/callers as needed
   - Check for similar implementations elsewhere
   - Identify related files/modules that may need updates

### 5: Confidence Scoring
Score each issue:

- **0:** Not confident; likely false positive/pre-existing
- **25:** Somewhat confident; unverified/stylistic
- **50:** Moderately confident; verified, minor, infrequent
- **75:** Highly confident; important, impacts functionality, or explicit guideline
- **100:** Absolutely certain; clearly evidenced

For guideline issues, cite explicit statements.

### 6: Issue Filtering
Exclude issues below 75 score. If none remain:

```
### Code Review Results

No issues found. Checked for bugs and CLAUDE.md compliance.
```

### 7: Review Output
Output for the console in this format:

```
### Code Review Results

Found N issues:

1. <Description> (include "CLAUDE.md says: <quote>" when relevant)

   File: <path>:<line-range>
   Context: <code snippet>

...
```

## False Positives: Do Not Flag
- Pre-existing or non-modified issues
- Correct, but superficially buggy code
- Minor nitpicks
- Issues covered by CI/tools
- Code intentionally silenced or part of larger planned changes
- Cases outside changed lines

## Additional Notes
- Do not check build/runtime; assume CI covers this
- Always use `git diff`/`git show` as specified
- For branch reviews, diff against the base branch
- Include at least one line of code context
- Be thorough, specific, constructive, and prioritize critical/high-severity findings
- Understand common Rails, React, and healthcare (HIPAA) patterns as relevant

---

**Begin Review:**
