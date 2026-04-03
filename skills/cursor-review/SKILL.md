---
name: cursor-review
description: Run Cursor Bugbot-style code review using Claude CLI agents
---

## Cursor Code Review

Run a comprehensive code review similar to Cursor's Bugbot using the `cursor-review.sh` script.

### Usage

**Review current branch (with change description):**
```bash
./.claude/scripts/cursor-review.sh --description "Description of changes"
```

**Review specific commit (with change description):**
```bash
./.claude/scripts/cursor-review.sh <commit-hash> --description "Description of changes"
```

**Review commit range (with change description):**
```bash
./.claude/scripts/cursor-review.sh <start-commit>..<end-commit> --description "Description of changes"
```

**Alternative syntax for description:**
```bash
./.claude/scripts/cursor-review.sh --description="Description of changes" <commit-hash>
```

**Test if agent command is available:**
```bash
./.claude/scripts/cursor-review.sh --test
```

**Note**: The `--description` flag is strongly recommended. The agent will validate code changes against the provided description and assess how changes fit into the larger codebase.

### Behavior

- **On main branch**: Reviews the latest commit with prefix "Run for <commit hash> commit"
- **On other branches**: Reviews branch changes with prefix "run on <branch name>"
- **With commit hash**: Reviews the specified commit with prefix "Run for <commit hash> commit"
- **With commit range**: Reviews commits between start and end (inclusive) with prefix "Run for commits <start hash>..<end hash>"

The script uses the prompt from `.claude/cursor-code-review-prompt.md` and runs it through the `agent` command using the **Composer 2** model.

### Change Description Validation

When a change description is provided, the agent will:
1. **Validate implementation matches intent**: Compare actual code changes to the described purpose
2. **Check for missing features**: Identify if described functionality is missing from implementation
3. **Identify extra changes**: Flag changes not mentioned in the description
4. **Assess codebase integration**: Evaluate how changes fit into existing architecture, patterns, and conventions
5. **Check for related updates**: Identify related files/modules that may need updates

The agent will flag discrepancies between the change description and actual implementation, ensuring code changes align with stated intent and properly integrate with the codebase.

### Prerequisites

- `agent` command must be available in PATH or as `./agent` in current directory
- Git repository must be initialized
- `.claude/cursor-code-review-prompt.md` must exist
