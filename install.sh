#!/bin/bash
# Install multi-llm into a target project by creating symlinks.
#
# Usage:
#   /path/to/multi-llm/install.sh [target-project-dir]
#
# If no target dir is given, uses the current working directory.
# Creates symlinks in .claude/ and .agent/skills/ that point back
# to this repo, so scripts and skills resolve correctly.

set -e

MULTI_LLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "Installing multi-llm into: $TARGET_DIR"
echo "Source: $MULTI_LLM_DIR"

# Compute relative path from target subdirectory to multi-llm root.
# Usage: relpath <from-dir> <to-dir>
relpath() {
  python3 -c "import os; print(os.path.relpath('$2', '$1'))"
}

# --- .claude/ directory ---
mkdir -p "$TARGET_DIR/.claude"

# Symlink scripts/ directory
SCRIPTS_REL=$(relpath "$TARGET_DIR/.claude" "$MULTI_LLM_DIR/scripts")
if [ -L "$TARGET_DIR/.claude/scripts" ]; then
  echo "  .claude/scripts: already symlinked (skipping)"
elif [ -d "$TARGET_DIR/.claude/scripts" ]; then
  echo "  .claude/scripts: real directory exists — skipping (remove it first to symlink)"
else
  ln -s "$SCRIPTS_REL" "$TARGET_DIR/.claude/scripts"
  echo "  .claude/scripts -> $SCRIPTS_REL"
fi

# Symlink prompts/ directory (dev prompts: explore, architect, plan-review)
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
# (scripts reference them as .claude/<tool>-code-review-prompt.md)
for prompt in codex-code-review-prompt.md gemini-code-review-prompt.md cursor-code-review-prompt.md claude-code-review-prompt.md; do
  PROMPT_REL=$(relpath "$TARGET_DIR/.claude" "$MULTI_LLM_DIR/prompts/$prompt")
  if [ -L "$TARGET_DIR/.claude/$prompt" ] || [ -f "$TARGET_DIR/.claude/$prompt" ]; then
    echo "  .claude/$prompt: already exists (skipping)"
  else
    ln -s "$PROMPT_REL" "$TARGET_DIR/.claude/$prompt"
    echo "  .claude/$prompt -> $PROMPT_REL"
  fi
done

# --- .agent/skills/ directory ---
mkdir -p "$TARGET_DIR/.agent/skills"

for skill in multi-review plan-review codex-review gemini-review cursor-review review-stats feature-custom-dev pr autonomous-execute pr-ready; do
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

# --- Create output directories (project-local, not symlinked) ---
mkdir -p "$TARGET_DIR/.claude/reviews"
mkdir -p "$TARGET_DIR/.claude/logs"

echo ""
echo "Done. Verify with: ls -la $TARGET_DIR/.claude/ $TARGET_DIR/.agent/skills/"
