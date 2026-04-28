#!/usr/bin/env bash
# /flow v2 installer — Claude Code user-level
# Installs the flow skill and all 9 subagents into ~/.claude/
#   pm, triager, architect, planner, test-author, implementer,
#   test-runner, failure-triager, reporter

set -e

SKILL_DIR="$HOME/.claude/skills/flow"
AGENTS_DIR="$HOME/.claude/agents"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing /flow v2 to user-level Claude Code..."

# Remove any existing v1
if [ -d "$SKILL_DIR" ]; then
  echo "  → removing existing ~/.claude/skills/flow/"
  rm -rf "$SKILL_DIR"
fi

# Remove any existing flow-* agents from prior attempts
for agent in "$AGENTS_DIR"/flow-*.md; do
  if [ -f "$agent" ]; then
    echo "  → removing existing $(basename "$agent")"
    rm -f "$agent"
  fi
done

# Create directories
mkdir -p "$SKILL_DIR"
mkdir -p "$AGENTS_DIR"

# Install skill
cp "$SCRIPT_DIR/skills/flow/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "  ✓ installed $SKILL_DIR/SKILL.md"

# Install agents
for agent in "$SCRIPT_DIR/agents/"flow-*.md; do
  name="$(basename "$agent")"
  cp "$agent" "$AGENTS_DIR/$name"
  echo "  ✓ installed $AGENTS_DIR/$name"
done

echo ""
echo "Done. Verify with:"
echo "  ls $SKILL_DIR/"
echo "  ls $AGENTS_DIR/flow-*.md"
echo ""
echo "Then in any Claude Code session: /flow <task>"
