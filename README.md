# Flow

> A token-conscious TDD orchestration plugin for Claude Code. Multi-agent pipeline, model-tiered subagents, strict anti-loop guards.

If you've used Superpowers and loved the structure but watched it consume a feature's worth of tokens on a single task, Flow is for you. Same TDD discipline, fewer tokens, fewer infinite loops.

## Why this exists

Most AI development workflows put one big model in one big context window, asking it to plan, write tests, implement, run, debug, and report — all at the same intelligence tier. That works, but it's expensive, and bad decisions in early phases propagate through every later phase. Flow takes the opposite approach: split the work into bounded subagent calls, route each to the cheapest model that does the job well, and let an orchestrator hold the state machine and the safety rails.

The result: Opus only fires when judgment matters (planning, implementing). Sonnet handles writing tests and classifying failures. Haiku handles classification, command execution, and templating. Each subagent dies after returning, so its context never bloats the next one.

## What you get

- **`/flow {task}`** — single entrypoint that runs the full pipeline
- **Phased workflow** — triage → clarify → plan → write failing tests → implement → run suite → report
- **Plan approval gate** — workflow stops for your review; three response paths handle proceed / revise / revise-and-proceed
- **Anti-loop guards** — per-test attempt caps, implementer re-dispatch caps, total cycle circuit breaker, cascade detection
- **Hard guards** — no destructive operations, no auto-commits, no secrets ever leaked
- **Honest TDD** — failing tests must be proven failing for the right reason (missing behavior, not a syntax error) before implementation begins
- **Coverage discipline** — 90% line coverage on files touched by the change

## Pipeline

```
/flow {task}
  ↓
[Phase 0] Triager (Haiku)            classify size, detect stack, extract CLAUDE.md slices
  ↓
[Phase 1] Clarifier (Sonnet or Opus) 0–15 questions if genuine ambiguity exists
  ↓
[Phase 2] Planner (Opus, ultrathink) structured plan
  ↓
[USER GATE]                          you review and approve the plan
  ↓
[Phase 3] Test Author (Sonnet)       writes failing tests, proves they fail for right reason
  ↓
[Phase 4] Implementer (Opus)         writes minimum code to pass tests
          Test Runner (Haiku)        per-batch typecheck + tests
  ↓
[Phase 5] Test Runner (Haiku)        full suite + typecheck + coverage
          Failure Triager (Sonnet)   classifies failures: test-wrong / plan-wrong / code-wrong
  ↓
[Phase 6] Reporter (Haiku)           formatted handoff
```

For phase-by-phase detail, see [docs/workflow.md](docs/workflow.md).
For architectural decisions and tradeoffs, see [docs/architecture.md](docs/architecture.md).

## Install

### Plugin install (recommended)

```bash
# in any Claude Code session
/plugin marketplace add carlosero/claude-flow
/plugin install flow
```

### Manual install (user-level, no marketplace)

```bash
git clone https://github.com/carlosero/claude-flow.git
cd flow
mkdir -p ~/.claude/skills/flow ~/.claude/agents
cp skills/flow/SKILL.md ~/.claude/skills/flow/SKILL.md
cp agents/flow-*.md ~/.claude/agents/
```

Then start a fresh Claude Code session and run `/flow <task>`.

## Quick start

```
/flow add a /api/health endpoint that returns 200 with uptime in seconds
```

Phase 0 will classify this as `S` (small). Clarifier likely has 0 questions. Planner produces a plan. You approve. Tests get written and proven failing. Implementation. Full suite. Handoff.

For a meatier example:

```
/flow add real-time chat to the dashboard with message persistence and typing indicators
```

This will likely classify as `L` (large). Expect clarifying questions from the Opus clarifier about scope (DMs vs group chat, persistence backend, message ordering guarantees). The plan will be batched. Implementation runs through batches in order.

## Anti-loop guards

The biggest token-waste risk in AI-assisted TDD is unconscious test/fix looping. Flow tracks counters across the workflow and stops cleanly when limits are hit:

| Counter | Cap | On trip |
|---|---|---|
| Per-test fix attempts | 3 | Stop, escalate |
| Implementer re-dispatches per batch | 3 | Stop, escalate |
| Full-suite runs in Phase 5 | 3 | Stop, report state |
| Total test/fix cycles across workflow | 5 | Stop, check in |

A "diagnose before retry" rule requires the orchestrator to articulate a one-sentence root cause before any retry dispatch. If it can't articulate, it asks you instead.

## Hard guards

These cannot be overridden — not by you, not by `CLAUDE.md`, not by any subagent:

- No file deletions
- No dropping databases or tables
- No destructive migrations
- No force-push or git history rewrites
- No modifications to `.env` or secrets files
- No auto-commits
- No file permission changes or `sudo`
- No logging secrets or including production data in tests

## Configuration

### Per-project conventions

Flow respects your project's `CLAUDE.md`. Conventions, test rules, and no-gos defined there override Flow's defaults for that project. Anti-loop guards and hard guards remain in force regardless.

### Model selection

Subagent model assignments are set in each agent's frontmatter. To change them, edit the agent files directly:

- `agents/flow-triager.md` — currently Haiku
- `agents/flow-clarifier-sonnet.md` — Sonnet (small tasks)
- `agents/flow-clarifier-opus.md` — Opus (medium/large tasks)
- `agents/flow-planner.md` — Opus
- `agents/flow-test-author.md` — Sonnet
- `agents/flow-implementer.md` — Opus
- `agents/flow-test-runner.md` — Haiku
- `agents/flow-failure-triager.md` — Sonnet
- `agents/flow-reporter.md` — Haiku

Any model alias (`opus`, `sonnet`, `haiku`) or full model ID is accepted.

## Compatibility

- Requires Claude Code (skills + subagents are Claude Code features)
- Tested on TypeScript / Next.js, Ruby on Rails, Go, and Python projects
- Works with any test runner the project already uses; no opinionated stack

## Contributing

Issues and pull requests welcome. Before opening a PR:

- Run `/flow` against a real feature in a test project; describe the run in your PR
- Don't change the anti-loop guard logic without a specific reason — those numbers came from real token-waste incidents
- Keep subagent system prompts terse — every token is paid on every invocation

## License

MIT — see [LICENSE](LICENSE).

## Related

- [Superpowers](https://github.com/obra/superpowers) — broader, more comprehensive workflow plugin. Worth using if your priorities are different from Flow's.
- [Claude Code documentation](https://code.claude.com/docs) — official docs for skills and subagents.
