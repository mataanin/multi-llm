# multi-llm

Multi-LLM development and code review pipeline for Claude Code. Orchestrates Claude, OpenAI Codex, Google Gemini, and Cursor Agent for parallel code review, codebase exploration, architecture design, and plan validation.

## What's Included

### Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `codex-dev.sh` | Codex development tasks (explore, architect, plan-review) |
| `gemini-dev.sh` | Gemini development tasks |
| `cursor-dev.sh` | Cursor Agent development tasks |
| `codex-review.sh` | Codex code review |
| `gemini-review.sh` | Gemini code review |
| `cursor-review.sh` | Cursor Agent code review |
| `claude-review.sh` | Claude Code code review |
| `review-analyze.sh` | Cross-tool finding extraction and agreement analysis |
| `harvest-pr-reviews.sh` | Ingest GitHub bot reviews (Copilot, Cursor BugBot) |
| `ensure-pr.sh` | Create PR if one doesn't exist for current branch |
| `request-github-reviews.sh` | Request reviews from GitHub bots |
| `gh-comment-threaded.sh` | Post threaded PR comments |
| `gh-find-comment-thread.sh` | Find existing comment threads |
| `dev-common.sh` | Shared logic for dev scripts |
| `review-common.sh` | Shared logic for review scripts |
| `log-common.sh` | Error logging and timeout utilities |

### Prompts (`prompts/`)

- **Code review prompts**: Per-tool review instructions with confidence scoring, false positive filtering, and structured output format
- **Explore prompts**: Codebase analysis and feature tracing instructions
- **Architect prompts**: Architecture blueprint generation with component design and build sequences
- **Plan review prompts**: Implementation plan validation with adversarial test assessment

### Skills (`skills/`)

Claude Code skills (`.agent/skills/`) for orchestrating the pipeline:

| Skill | Description |
|-------|-------------|
| `multi-review` | Run all review tools in parallel, analyze cross-tool agreement |
| `plan-review` | Validate implementation plans with multiple LLMs |
| `codex-review` | Single-tool Codex review |
| `gemini-review` | Single-tool Gemini review |
| `cursor-review` | Single-tool Cursor review |
| `review-stats` | Cumulative analytics across all reviews |
| `feature-custom-dev` | Multi-phase feature development with multi-LLM exploration and architecture |

## Installation

### Prerequisites

Install the CLI tools you want to use:

```bash
# Claude Code (required)
npm i -g @anthropic-ai/claude-code

# OpenAI Codex (optional)
npm i -g @openai/codex

# Google Gemini (optional)
npm i -g @google/gemini-cli

# Cursor Agent (optional)
# Follow Cursor Agent CLI installation instructions
```

### Install into a project

```bash
# From your project root:
/path/to/multi-llm/install.sh .

# Or from anywhere:
/path/to/multi-llm/install.sh /path/to/your/project
```

This creates symlinks in `.claude/` and `.agent/skills/` pointing back to this repo.

### Manual setup

```bash
cd your-project

# Scripts and prompts
ln -s ../multi-llm/scripts .claude/scripts
ln -s ../multi-llm/prompts .claude/prompts

# Review prompts (referenced from .claude/ root by scripts)
ln -s ../multi-llm/prompts/codex-code-review-prompt.md .claude/codex-code-review-prompt.md
ln -s ../multi-llm/prompts/gemini-code-review-prompt.md .claude/gemini-code-review-prompt.md
ln -s ../multi-llm/prompts/cursor-code-review-prompt.md .claude/cursor-code-review-prompt.md
ln -s ../multi-llm/prompts/claude-code-review-prompt.md .claude/claude-code-review-prompt.md

# Skills
for skill in multi-review plan-review codex-review gemini-review cursor-review review-stats feature-custom-dev; do
  ln -s ../../multi-llm/skills/$skill .agent/skills/$skill
done

# Project-local output directories
mkdir -p .claude/reviews .claude/logs
```

## Usage

### Code Review

```bash
# Single tool
./.claude/scripts/codex-review.sh --description "What changed"
./.claude/scripts/gemini-review.sh --description "What changed"

# All tools via skill (in Claude Code)
/multi-review Description of changes
```

### Development Tasks

```bash
# Explore codebase
./.claude/scripts/codex-dev.sh --mode explore --task "feature description"

# Architecture design
CODEX_REASONING=high ./.claude/scripts/codex-dev.sh --mode architect --task "feature description"

# Plan review
./.claude/scripts/gemini-dev.sh --mode plan-review --plan "implementation plan text"
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CODEX_MODEL` | `gpt-5-codex` | Codex model |
| `CODEX_REASONING` | `medium` | Reasoning effort: `low`, `medium`, `high`, `xhigh` |
| `GEMINI_MODEL` | *(CLI default)* | Gemini model |
| `GEMINI_NODE_VERSION` | `20` | Minimum Node.js version for Gemini CLI |
| `CURSOR_MODEL` | `composer-1.5` | Cursor Agent model |
| `CLAUDE_REVIEW_MODEL` | `opus-4.6` | Claude review model |
| `REVIEW_TIMEOUT` | `600` | Timeout in seconds for each review tool |

## Architecture

```
scripts/
  log-common.sh          ← Timeout, error logging, branch detection
  dev-common.sh          ← Arg parsing, prompt loading for dev tasks
  review-common.sh       ← Arg parsing, diff context, prompt loading for reviews
  {codex,gemini,cursor}-dev.sh     ← Thin wrappers: set tool vars, source dev-common
  {codex,gemini,cursor,claude}-review.sh  ← Thin wrappers: set tool vars, source review-common
  review-analyze.sh      ← Deterministic cross-tool finding extraction + agreement analysis
  harvest-pr-reviews.sh  ← Ingest GitHub bot reviews into the analytics pipeline
```

The shared libraries (`log-common.sh`, `dev-common.sh`, `review-common.sh`) handle all the complexity. Each tool script is ~10-20 lines that sets tool-specific variables and invokes the CLI.

`review-analyze.sh` uses deterministic Python parsing (no LLM dependency) to extract findings, match across tools by file path, and correlate with post-review git actions. Results are appended to `review-analytics.json` for cumulative tracking.
