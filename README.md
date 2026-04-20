# multi-llm

Multi-LLM development and code review pipeline for Claude Code. Orchestrates Claude, OpenAI Codex, Google Gemini, Cursor Agent, and GitHub Copilot for parallel code review (standard + adversarial), codebase exploration, architecture design, and plan validation.

## What's Included

### Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `codex-dev.sh` | Codex development tasks (explore, architect, plan-review, adversarial-plan-review) |
| `gemini-dev.sh` | Gemini development tasks |
| `cursor-dev.sh` | Cursor Agent development tasks |
| `copilot-dev.sh` | GitHub Copilot CLI development tasks |
| `codex-review.sh` | Codex code review |
| `codex-adversarial-review.sh` | Codex adversarial review (challenges assumptions, surfaces hidden failures) |
| `gemini-review.sh` | Gemini code review |
| `cursor-review.sh` | Cursor Agent code review |
| `claude-review.sh` | Claude Code code review |
| `copilot-review.sh` | GitHub Copilot CLI code review |
| `copilot-adversarial-review.sh` | GitHub Copilot adversarial code review |
| `review-analyze.sh` | Cross-tool finding extraction and agreement analysis |
| `harvest-pr-reviews.sh` | Ingest GitHub bot reviews (Copilot, Cursor BugBot) |
| `ensure-pr.sh` | Create PR if one doesn't exist for current branch |
| `request-github-reviews.sh` | Request reviews from GitHub bots |
| `gh-comment-threaded.sh` | Post threaded PR comments |
| `gh-find-comment-thread.sh` | Find existing comment threads |
| `test-skill-access.sh` | Probe whether external review CLIs can discover/invoke skills (research tool) |
| `dev-common.sh` | Shared logic for dev scripts |
| `review-common.sh` | Shared logic for review scripts |
| `log-common.sh` | Error logging and timeout utilities |

### Prompts (`prompts/`)

- **Code review prompts**: Per-tool review instructions with confidence scoring, false positive filtering, and structured output format. Adversarial variants for Codex and Copilot flip the stance — assume the change is broken and hunt for failure paths.
- **Explore prompts**: Codebase analysis and feature tracing instructions (Codex, Gemini, Cursor, Copilot)
- **Architect prompts**: Architecture blueprint generation with component design and build sequences (Codex, Gemini, Cursor, Copilot)
- **Plan review prompts**: Implementation plan validation (Codex, Gemini, Cursor, Copilot). Adversarial variants for Codex and Copilot stress-test plans by assuming they'll fail.

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

The install script checks for all dependencies and reports what's missing. You can also install them manually:

| Tool | Package / Install | CLI | Required |
|------|-------------------|-----|----------|
| Claude Code | `npm i -g @anthropic-ai/claude-code` | `claude` | **yes** |
| OpenAI Codex | `npm i -g @openai/codex` | `codex` | optional |
| Google Gemini | `npm i -g @google/gemini-cli` | `gemini` | optional |
| GitHub Copilot CLI | `npm i -g @github/copilot` or `brew install copilot-cli` | `copilot` | optional |
| Cursor Agent | [docs.cursor.com/cli](https://docs.cursor.com/cli) | `agent` | optional |
| GitHub CLI | `brew install gh` | `gh` | for PR bot harvesting |
| jq | `brew install jq` | `jq` | for JSON parsing |
| Python 3 | system package manager | `python3` | **yes** |

Each optional tool is independent — scripts gracefully skip tools that aren't installed.

### Install into a project

```bash
# From your project root:
/path/to/multi-llm/install.sh .

# Or from anywhere:
/path/to/multi-llm/install.sh /path/to/your/project

# Auto-install missing npm packages:
/path/to/multi-llm/install.sh . --install-deps

# Only run dependency check (no symlinks):
/path/to/multi-llm/install.sh --deps-only

# Skip dependency check:
/path/to/multi-llm/install.sh . --skip-deps
```

This creates symlinks in `.claude/` and `.agent/skills/` pointing back to this repo.

### Manual setup

```bash
cd your-project

# Scripts and prompts
ln -s ../multi-llm/scripts .claude/scripts
ln -s ../multi-llm/prompts .claude/prompts

# Review prompts (referenced from .claude/ root by scripts)
for p in claude codex gemini cursor copilot copilot-adversarial; do
  ln -s ../multi-llm/prompts/${p}-code-review-prompt.md .claude/${p}-code-review-prompt.md
done

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
| `COPILOT_MODEL` | `claude-sonnet-4.6` | GitHub Copilot CLI model |
| `CLAUDE_REVIEW_MODEL` | `opus-4.6` | Claude review model |
| `REVIEW_TIMEOUT` | `600` | Timeout in seconds for each review tool |

## Architecture

```
scripts/
  log-common.sh          ← Timeout, error logging, branch detection
  dev-common.sh          ← Arg parsing, prompt loading for dev tasks
  review-common.sh       ← Arg parsing, diff context, prompt loading for reviews
  {codex,gemini,cursor,copilot}-dev.sh              ← Thin wrappers: set tool vars, source dev-common
  {codex,gemini,cursor,claude,copilot}-review.sh    ← Thin wrappers: set tool vars, source review-common
  {codex,copilot}-adversarial-review.sh             ← Adversarial variants using hostile prompts
  review-analyze.sh      ← Deterministic cross-tool finding extraction + agreement analysis
  harvest-pr-reviews.sh  ← Ingest GitHub bot reviews into the analytics pipeline
```

The shared libraries (`log-common.sh`, `dev-common.sh`, `review-common.sh`) handle all the complexity. Each tool script is ~10-20 lines that sets tool-specific variables and invokes the CLI.

`review-analyze.sh` uses deterministic Python parsing (no LLM dependency) to extract findings, match across tools by file path, and correlate with post-review git actions. Results are appended to `review-analytics.json` for cumulative tracking.
