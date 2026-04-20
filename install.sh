#!/bin/bash
# Install multi-llm into a target project by creating symlinks.
#
# Usage:
#   /path/to/multi-llm/install.sh [target-project-dir] [flags]
#
# Flags:
#   --install-deps    Install missing npm CLI tools automatically
#   --skip-deps       Skip dependency check entirely
#   --deps-only       Only run dependency check, no symlinks
#
# If no target dir is given, uses the current working directory.
# Creates symlinks in .claude/ and .agent/skills/ that point back
# to this repo, so scripts and skills resolve correctly.

set -e

# ── Parse args ───────────────────────────────────────────────────────────
INSTALL_DEPS=false
SKIP_DEPS=false
DEPS_ONLY=false
TARGET_DIR=""

for arg in "$@"; do
  case "$arg" in
    --install-deps) INSTALL_DEPS=true ;;
    --skip-deps)    SKIP_DEPS=true ;;
    --deps-only)    DEPS_ONLY=true ;;
    --*) echo "Unknown flag: $arg"; exit 1 ;;
    *)   TARGET_DIR="$arg" ;;
  esac
done

MULTI_LLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "Installing multi-llm into: $TARGET_DIR"
echo "Source: $MULTI_LLM_DIR"
echo ""

# Compute relative path from target subdirectory to multi-llm root.
# Usage: relpath <from-dir> <to-dir>
relpath() {
  python3 -c "import os; print(os.path.relpath('$2', '$1'))"
}

# ═══════════════════════════════════════════════════════════════════════
#  Dependency check
# ═══════════════════════════════════════════════════════════════════════
#
# The pipeline orchestrates multiple external CLIs. Each tool is optional —
# scripts gracefully skip tools that aren't installed. But you should install
# the ones you intend to use.
#
# Tool matrix:
#   REQUIRED        Shell + system tools (bash, git, python3)
#   NPM (Claude)    @anthropic-ai/claude-code      → claude        (required)
#   NPM (Codex)     @openai/codex                  → codex         (optional)
#   NPM (Gemini)    @google/gemini-cli             → gemini        (optional)
#   NPM (Copilot)   @github/copilot                → copilot       (optional)
#   CUSTOM          Cursor Agent CLI               → agent         (optional)
#   CUSTOM          GitHub CLI                     → gh            (PR bot reviews)
#   CUSTOM          jq                             → jq            (JSON parsing)
#   CUSTOM          uuidgen                        → uuidgen       (canary probes)

check_deps() {
  echo "── Dependency check ──────────────────────────────────────────"

  local missing_required=()
  local missing_npm=()
  local missing_custom=()

  # System tools (REQUIRED)
  for cmd in bash git python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "  [ok]   %-14s (%s)\n" "$cmd" "$(command -v "$cmd")"
    else
      printf "  [MISS] %-14s — REQUIRED, install via system package manager\n" "$cmd"
      missing_required+=("$cmd")
    fi
  done

  # NPM-based LLM CLIs
  check_npm() {
    local cmd="$1"; local pkg="$2"; local label="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "  [ok]   %-14s (%s)\n" "$cmd" "$(command -v "$cmd")"
    else
      printf "  [MISS] %-14s — %s: npm i -g %s\n" "$cmd" "$label" "$pkg"
      missing_npm+=("$pkg")
    fi
  }

  check_npm "claude"  "@anthropic-ai/claude-code" "Claude Code (required)"
  check_npm "codex"   "@openai/codex"             "OpenAI Codex (optional)"
  check_npm "gemini"  "@google/gemini-cli"        "Google Gemini (optional)"
  check_npm "copilot" "@github/copilot"           "GitHub Copilot CLI (optional)"

  # Non-npm CLIs (install instructions vary)
  check_custom() {
    local cmd="$1"; local label="$2"; local hint="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "  [ok]   %-14s (%s)\n" "$cmd" "$(command -v "$cmd")"
    else
      printf "  [MISS] %-14s — %s: %s\n" "$cmd" "$label" "$hint"
      missing_custom+=("$cmd")
    fi
  }

  check_custom "agent"   "Cursor Agent (optional)"   "https://docs.cursor.com/cli"
  check_custom "gh"      "GitHub CLI (PR bot reviews)" "brew install gh  OR  https://cli.github.com/"
  check_custom "jq"      "jq (JSON parsing)"         "brew install jq"
  check_custom "uuidgen" "uuidgen (canary probes)"    "usually preinstalled; util-linux on Debian/Ubuntu"

  echo ""

  # Fail hard if required system tools are missing
  if [ ${#missing_required[@]} -gt 0 ]; then
    echo "  ERROR: missing required system tools: ${missing_required[*]}"
    echo "  Install them via your system package manager before continuing."
    exit 1
  fi

  # Auto-install npm tools if requested
  if [ ${#missing_npm[@]} -gt 0 ] && [ "$INSTALL_DEPS" = true ]; then
    if ! command -v npm >/dev/null 2>&1; then
      echo "  ERROR: --install-deps requires npm, which is not installed."
      echo "  Install Node.js (https://nodejs.org/) first."
      exit 1
    fi
    echo "  Installing missing npm packages..."
    for pkg in "${missing_npm[@]}"; do
      echo "    npm i -g $pkg"
      npm i -g "$pkg" || echo "    WARN: failed to install $pkg (continuing)"
    done
    echo ""
  elif [ ${#missing_npm[@]} -gt 0 ]; then
    echo "  To auto-install missing npm packages, re-run with --install-deps."
    echo ""
  fi

  if [ ${#missing_custom[@]} -gt 0 ]; then
    echo "  Non-npm CLIs are optional — install them manually as needed."
    echo ""
  fi
}

if [ "$SKIP_DEPS" != true ]; then
  check_deps
fi

if [ "$DEPS_ONLY" = true ]; then
  echo "Done (deps-only mode)."
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
#  Symlinks: .claude/
# ═══════════════════════════════════════════════════════════════════════

echo "── Symlinks ──────────────────────────────────────────────────"

mkdir -p "$TARGET_DIR/.claude"

# Symlink scripts/ directory (all scripts, including new additions)
SCRIPTS_REL=$(relpath "$TARGET_DIR/.claude" "$MULTI_LLM_DIR/scripts")
if [ -L "$TARGET_DIR/.claude/scripts" ]; then
  echo "  .claude/scripts: already symlinked (skipping)"
elif [ -d "$TARGET_DIR/.claude/scripts" ]; then
  echo "  .claude/scripts: real directory exists — skipping (remove it first to symlink)"
else
  ln -s "$SCRIPTS_REL" "$TARGET_DIR/.claude/scripts"
  echo "  .claude/scripts -> $SCRIPTS_REL"
fi

# Symlink prompts/ directory (dev prompts: explore, architect, plan-review, adversarial-plan-review)
PROMPTS_REL=$(relpath "$TARGET_DIR/.claude" "$MULTI_LLM_DIR/prompts")
if [ -L "$TARGET_DIR/.claude/prompts" ]; then
  echo "  .claude/prompts: already symlinked (skipping)"
elif [ -d "$TARGET_DIR/.claude/prompts" ]; then
  echo "  .claude/prompts: real directory exists — skipping (remove it first to symlink)"
else
  ln -s "$PROMPTS_REL" "$TARGET_DIR/.claude/prompts"
  echo "  .claude/prompts -> $PROMPTS_REL"
fi

# Symlink individual review prompt files into .claude/ root
# (review scripts reference them via .claude/<tool>-code-review-prompt.md)
ROOT_PROMPTS=(
  claude-code-review-prompt.md
  codex-code-review-prompt.md
  gemini-code-review-prompt.md
  cursor-code-review-prompt.md
  copilot-code-review-prompt.md
  copilot-adversarial-code-review-prompt.md
)
for prompt in "${ROOT_PROMPTS[@]}"; do
  PROMPT_REL=$(relpath "$TARGET_DIR/.claude" "$MULTI_LLM_DIR/prompts/$prompt")
  if [ -L "$TARGET_DIR/.claude/$prompt" ] || [ -f "$TARGET_DIR/.claude/$prompt" ]; then
    echo "  .claude/$prompt: already exists (skipping)"
  else
    ln -s "$PROMPT_REL" "$TARGET_DIR/.claude/$prompt"
    echo "  .claude/$prompt -> $PROMPT_REL"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
#  Symlinks: .agent/skills/
# ═══════════════════════════════════════════════════════════════════════

mkdir -p "$TARGET_DIR/.agent/skills"

SKILLS=(
  multi-review
  plan-review
  codex-review
  gemini-review
  cursor-review
  review-stats
  feature-custom-dev
  pr
  pr-ready
  autonomous-execute
)
for skill in "${SKILLS[@]}"; do
  SKILL_REL=$(relpath "$TARGET_DIR/.agent/skills" "$MULTI_LLM_DIR/skills/$skill")
  if [ -L "$TARGET_DIR/.agent/skills/$skill" ]; then
    echo "  .agent/skills/$skill: already symlinked (skipping)"
  elif [ -d "$TARGET_DIR/.agent/skills/$skill" ]; then
    echo "  .agent/skills/$skill: real directory exists (skipping)"
  else
    ln -s "$SKILL_REL" "$TARGET_DIR/.agent/skills/$skill"
    echo "  .agent/skills/$skill -> $SKILL_REL"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
#  Output directories (project-local, not symlinked)
# ═══════════════════════════════════════════════════════════════════════

mkdir -p "$TARGET_DIR/.claude/reviews"
mkdir -p "$TARGET_DIR/.claude/logs"

echo ""
echo "Done. Verify with: ls -la $TARGET_DIR/.claude/ $TARGET_DIR/.agent/skills/"
