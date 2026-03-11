---
name: gemini-review
description: Run Google Gemini code review using gemini CLI in non-interactive mode
---

## Gemini Code Review

Run a comprehensive code review using Google's Gemini CLI agent with the `gemini-review.sh` script.

### Usage

**Review current branch (with change description):**
```bash
./.claude/scripts/gemini-review.sh --description "Description of changes"
```

**Review specific commit (with change description):**
```bash
./.claude/scripts/gemini-review.sh <commit-hash> --description "Description of changes"
```

**Review commit range (with change description):**
```bash
./.claude/scripts/gemini-review.sh <start-commit>..<end-commit> --description "Description of changes"
```

**Alternative syntax for description:**
```bash
./.claude/scripts/gemini-review.sh --description="Description of changes" <commit-hash>
```

**Test if gemini command is available:**
```bash
./.claude/scripts/gemini-review.sh --test
```

**Note**: The `--description` flag is strongly recommended. The agent will validate code changes against the provided description and assess how changes fit into the larger codebase.

### Behavior

- **On main branch**: Reviews the latest commit with prefix "Run for <commit hash> commit"
- **On other branches**: Reviews branch changes with prefix "run on <branch name>"
- **With commit hash**: Reviews the specified commit with prefix "Run for <commit hash> commit"
- **With commit range**: Reviews commits between start and end (inclusive) with prefix "Run for commits <start hash>..<end hash>"

The script uses the prompt from `.claude/gemini-code-review-prompt.md` and runs it through `gemini -p` (non-interactive mode).

### Change Description Validation

When a change description is provided, the agent will:
1. **Validate implementation matches intent**: Compare actual code changes to the described purpose
2. **Check for missing features**: Identify if described functionality is missing from implementation
3. **Identify extra changes**: Flag changes not mentioned in the description
4. **Assess codebase integration**: Evaluate how changes fit into existing architecture, patterns, and conventions
5. **Check for related updates**: Identify related files/modules that may need updates

### Prerequisites

- `gemini` command must be available in PATH (install with `npm i -g @google/gemini-cli`)
- Git repository must be initialized
- `.claude/gemini-code-review-prompt.md` must exist
- Google authentication configured (run `gemini` once to authenticate)
