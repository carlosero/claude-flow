# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Flow is a **Claude Code plugin** — there is no application code, no build, no test runner. The "code" is prompts: one orchestrator skill (`skills/flow/SKILL.md`) and nine subagent definitions (`agents/flow-*.md`), all distributed as Markdown with YAML frontmatter. Changes here are prompt edits, not feature code.

## Install / try changes locally

```bash
./install.sh          # copies skill + agents into ~/.claude/
```

Then start a fresh Claude Code session and run `/flow <task>` to exercise the pipeline. The installer wipes any prior `~/.claude/skills/flow/` and `~/.claude/agents/flow-*.md` before copying — re-run it after every edit to pick up changes.

There is no automated test suite. Validation is end-to-end: run `/flow` on a real feature in a sample project and watch the phase transitions.

## Architecture in one paragraph

`/flow` is a state machine implemented as an orchestrator skill that dispatches to bounded subagents and never writes code itself. Each phase routes work to the cheapest subagent that can do it: Haiku for classification/command-execution/templating (triager, test-runner, reporter), Sonnet for moderate judgment (small-task clarifier, test-author, failure-triager), Opus for the load-bearing reasoning calls (medium/large clarifier, planner, implementer). Subagents run in fresh contexts, see only what the orchestrator hands them, and die after returning. The orchestrator holds all cross-phase state — cycle counters, modified-test log, batch progress.

Read `skills/flow/SKILL.md` for the full state machine. Read `docs/architecture.md` for the rationale behind each split. Read `docs/workflow.md` for the user-facing phase walkthrough. The three documents intentionally cover different audiences (orchestrator implementation / design rationale / user guide); keep that separation when editing.

## Editing rules

- **Subagent prompts ship on every invocation.** Every token in `agents/flow-*.md` is paid each call. Keep them terse; resist adding examples or hedging language.
- **Model assignments live in agent frontmatter** (`model: claude-...` or alias `opus`/`sonnet`/`haiku`). The model tier table in `docs/architecture.md` documents the rationale — if you change a model, update the rationale too.
- **Anti-loop guards and hard guards are non-negotiable.** They are duplicated across `README.md`, `skills/flow/SKILL.md`, and `docs/architecture.md` by design — if you change a cap or a guard rule, update all three locations. The guards must remain non-overridable by project `CLAUDE.md`.
- **The plan-approval gate has three response paths** (explicit proceed / revise-and-represent / change-and-proceed combo). Don't collapse them. The "when in doubt, re-present" default is intentional.
- **Plans don't include code by default** — only `[core logic preview]` exceptions. Don't loosen this in the planner prompt.
- **No `Carlos` references in the published skill/agents.** `PUBLISHING_TODO.md` lists the suggested neutral replacements; honor them in any new prompt copy.

## Versioning

Semver, per `docs/architecture.md`:
- **Major** — breaking install changes (new required field, removed subagent)
- **Minor** — additive (new subagent, new optional config)
- **Patch** — prompt clarifications, model ID bumps

Bump `version` in `.claude-plugin/plugin.json` and add an entry to `CHANGELOG.md` under the matching heading.
