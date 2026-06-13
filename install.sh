#!/usr/bin/env bash
# /flow + /flow-lite installer — Claude Code user-level
# Installs every skill under skills/ and all flow-* subagents into ~/.claude/
#   skills:  flow (full orchestrated pipeline), flow-lite (clarify-then-do)
#   agents:  pm, triager, architect, planner, test-author, implementer,
#            test-runner, failure-triager, security-reviewer, reporter

set -e

SKILLS_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.claude/agents"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing flow skills to user-level Claude Code..."

# Remove any existing installations of skills we ship
for skill_src in "$SCRIPT_DIR/skills"/*/; do
  name="$(basename "$skill_src")"
  if [ -d "$SKILLS_DIR/$name" ]; then
    echo "  → removing existing $SKILLS_DIR/$name/"
    rm -rf "$SKILLS_DIR/$name"
  fi
done

# Remove any existing flow-* agents from prior attempts
for agent in "$AGENTS_DIR"/flow-*.md; do
  if [ -f "$agent" ]; then
    echo "  → removing existing $(basename "$agent")"
    rm -f "$agent"
  fi
done

# Create directories
mkdir -p "$SKILLS_DIR"
mkdir -p "$AGENTS_DIR"

# Install skills (every directory under skills/ that has a SKILL.md)
for skill_src in "$SCRIPT_DIR/skills"/*/; do
  name="$(basename "$skill_src")"
  if [ -f "$skill_src/SKILL.md" ]; then
    mkdir -p "$SKILLS_DIR/$name"
    cp "$skill_src/SKILL.md" "$SKILLS_DIR/$name/SKILL.md"
    echo "  ✓ installed $SKILLS_DIR/$name/SKILL.md"
  fi
done

# Install agents
for agent in "$SCRIPT_DIR/agents/"flow-*.md; do
  name="$(basename "$agent")"
  cp "$agent" "$AGENTS_DIR/$name"
  echo "  ✓ installed $AGENTS_DIR/$name"
done

echo ""
echo "Done. Verify with:"
echo "  ls $SKILLS_DIR/"
echo "  ls $AGENTS_DIR/flow-*.md"
echo ""
echo "Then in any Claude Code session: /flow <task> or /flow-lite <task>"
