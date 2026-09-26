# Flow

> A token-conscious TDD orchestration plugin for Claude Code. Multi-agent pipeline, model-tiered subagents, strict anti-loop guards.

If you've used Superpowers and loved the structure but watched it consume a feature's worth of tokens on a single task, Flow is for you. Same TDD discipline, fewer tokens, fewer infinite loops.

Two entrypoints: **`/flow`** for non-trivial features that deserve the full pipeline, and **`/flow-lite`** for small or non-development tasks that just need the ambiguity removed before someone does the work.

## Why this exists

Most AI development workflows put one big model in one big context window, asking it to plan, write tests, implement, run, debug, and report — all at the same intelligence tier. That works, but it's expensive, and bad decisions in early phases propagate through every later phase. Flow takes the opposite approach: split the work into bounded subagent calls, route each to the cheapest model that does the job well, and let an orchestrator hold the state machine and the safety rails.

The result: the whole main reasoning path — architecture, plan, and each batch's code — inherits your session model, so you set the quality/cost trade for a run by picking a model before you type `/flow`. Only the off-path implementer stays pinned to Opus. Sonnet handles the codebase map, security review, and failure classification. Haiku handles command execution and templating. Each subagent dies after returning, so its context never bloats the next one.

Splitting has a cost, though, and Flow is explicit about it: a fresh context is only cheap when the agent doesn't have to *rebuild* it. Agents that need the same understanding of your codebase to do their jobs are merged rather than split, and the understanding they do need is written down once — in MAP.md — instead of re-derived on every dispatch.

## What you get

- **`/flow {task}`** — full orchestrated pipeline for non-trivial features
- **`/flow-lite {task}`** — clarify-then-do for small or non-code tasks; no subagents, no TDD, no gates
- **Phased workflow** — PM → triage → architect → plan → build batches (failing tests then code, one agent) → security review → run suite → report
- **Per-task artifact directory** — every run gets `~/.flow/tasks/{project}/{unix_ts}/` with TASK.md, MAP.md, ARCHITECT.md, PLAN.md, SECURITY.md, REPORT.md, STATE.md. Subagents read from disk instead of in-band context; you can hand-edit any artifact between phases.
- **MAP.md, the shared codebase map** — triage writes your project's commands, test conventions, fixture and double patterns, key paths, and gotchas once; every later agent reads it instead of re-exploring
- **Hash-locked tests** — a batch's tests are frozen the moment they're proven failing, and independently re-verified after the code is written. The agent that makes the tests pass cannot quietly weaken them; a mismatch stops the run.
- **Parallel batches** — the planner declares batch dependencies and the orchestrator builds independent batches concurrently (up to 3), falling back to serial on any file overlap
- **Plan approval gate** — workflow hard-stops for your review and ends the turn; three response paths handle proceed / revise / revise-and-proceed. Not overridable by auto-accept mode, `/loop`, or project `CLAUDE.md`
- **Architect conflict channel** — architect can return `status: conflict` when an AC in TASK.md cannot be satisfied by any sensible architecture; orchestrator surfaces to you, rewrites TASK.md per your direction, re-dispatches
- **Anti-loop guards** — per-test attempt caps, builder re-dispatch caps, total cycle circuit breaker, security-review cycle cap, architect/TASK conflict cycle cap, test-lock violations, cascade detection
- **Hard guards** — no destructive operations, no auto-commits, no secrets ever leaked
- **Honest TDD** — failing tests must be proven failing for the right reason (missing behavior, not a syntax error) before implementation begins
- **Coverage discipline** — 90% line coverage on files touched by the change
- **Security review before the full suite** — diff-scoped vulnerability check (injection, XSS, auth, secrets, frontend env leakage, CSRF, SSRF, etc.) runs *before* the final full-suite test pass so a finding that requires code changes doesn't waste a full-suite run; findings loop back through the implementer until clean

## Pipeline

```
/flow {task}
  ↓
[setup]   orchestrator creates ~/.flow/tasks/{project}/{unix_ts}/ and writes STATE.md
  ↓
[Phase 0] PM (Sonnet)                   writes TASK.md (feature, AC checkboxes, out-of-scope); 0–15 questions if needed
  ↓
[Phase 1] Triager (Sonnet)              classify size, detect stack + commands, write MAP.md
  ↓
[Phase 2] Architect (session)           writes ARCHITECT.md; 0–15 questions if needed; may raise TASK.md conflict
  ↓
[Phase 3] Planner (session, ultrathink) writes PLAN.md (batches within budget + dependency graph + AC mapping)
  ↓
[USER GATE]                             you review and approve the plan
  ↓
[Phase 4] Batch Builder (session)       per batch, in one context: failing tests → prove red → hash-lock
                                        → minimum code → green.  Independent batches run in parallel (max 3)
          Test Runner (Haiku)           per-batch typecheck + tests + test-lock verification
          Orchestrator                  ticks AC checkboxes in TASK.md per batch
  ↓
[Phase 5] Security Reviewer (Sonnet)    writes SECURITY.md (diff-scoped vulnerability review)
          Implementer (Opus)            fixes findings; reviewer re-runs (overwriting SECURITY.md) until clean
                                        (no test run in the loop — Phase 6 is the gate)
  ↓
[Phase 6] Test Runner (Haiku)           full suite + typecheck + coverage + lock re-verification
          Failure Triager (Sonnet)      classifies failures: test-wrong / plan-wrong / code-wrong
          Test Author (Sonnet)          closes coverage gaps on touched files, if any
  ↓
[Phase 7] Reporter (Haiku)              reads task dir, writes REPORT.md
```

For phase-by-phase detail, see [docs/workflow.md](docs/workflow.md).
For architectural decisions and tradeoffs, see [docs/architecture.md](docs/architecture.md).

## `/flow-lite` — the small-task path

The full pipeline is deliberately heavy: nine phases, ten subagents, a plan-approval gate. That's the right price for a feature. It's the wrong price for "rename this config key everywhere" or "draft the migration notes for the next release."

`/flow-lite` is the other end of the range. One skill, no subagents, no artifact directory, no TDD. It does two things: removes the ambiguity, then does the work.

```
/flow-lite {task}
  ↓
[Step 1] Read first        only when the prompt says "read the files" / "look at the code"
                           (grounds in the relevant code so the questions land sharper)
  ↓
[Step 2] Clarify           up to 8 questions, then the turn ends and waits on you
  ↓
[Step 3] Do the work       directly, in your session's context
  ↓
[Step 4] Reconcile tests   dev tasks only, and only where related tests already exist
```

Step 4 is where it diverges most from `/flow`: it is **not** TDD. Code lands first, then existing tests are updated to assert the new contract, run, and fixed. Each failure gets classified — the test was right and the code is wrong (fix the code), or the test asserts the old contract (update it, and say why in one sentence). No new test framework where there isn't one, no backfilling coverage on untouched code, no refactoring tests in passing. If nothing related exists, or the task isn't code, the step is skipped.

Questions are capped at 8 in a round, with instructions to prefer fewer — or none, when nothing is genuinely ambiguous. Discrete choices go through `AskUserQuestion`. The turn ends after asking, so no work starts before you answer.

### Which one to reach for

| | `/flow` | `/flow-lite` |
|---|---|---|
| Task shape | Non-trivial feature | Small change, or not code at all |
| Subagents | 10, model-tiered | None — runs in your session's context |
| Tests | TDD; failing tests proven first | Existing tests updated after the change |
| Artifacts | `~/.flow/tasks/…` (6 files) | None |
| Gates | Plan approval, security review, full suite | None |
| Clarifying questions | PM (0–15), then architect (0–15) | Up to 8 per round |
| Hard guards | Yes, non-overridable | Yes, same list |

Rule of thumb: if you'd want a written plan to review before any code gets written, use `/flow`. If you'd just want to be asked the right two questions first, use `/flow-lite`.

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
cd claude-flow
./install.sh
```

`install.sh` copies every skill under `skills/` — both `flow` and `flow-lite` — plus all `flow-*` subagents into `~/.claude/`. It wipes any prior install of those first, so re-run it after every edit. To do the same by hand:

```bash
mkdir -p ~/.claude/skills/flow ~/.claude/skills/flow-lite ~/.claude/agents
cp skills/flow/SKILL.md ~/.claude/skills/flow/SKILL.md
cp skills/flow-lite/SKILL.md ~/.claude/skills/flow-lite/SKILL.md
cp agents/flow-*.md ~/.claude/agents/
```

Then start a fresh Claude Code session and run `/flow <task>` or `/flow-lite <task>`.

## Quick start

### Features

```
/flow add a /api/health endpoint that returns 200 with uptime in seconds
```

PM tightens the spec (likely 0 questions for something this clear). Phase 1 classifies it as `S`; the architect still runs (briefly, with zero or one question) so the planner has a written shape to decompose against. Planner produces a plan. You approve. Tests get written and proven failing. Implementation. Full suite. Handoff.

For a meatier example:

```
/flow add real-time chat to the dashboard with message persistence and typing indicators
```

This will likely classify as `L` (large). The PM will probably ask scope questions (DMs vs group chat, retention, ordering guarantees) and pin down acceptance criteria. The architect will then frame the high-level shape (subsystems, persistence, transport) and may raise a conflict if any AC can't be satisfied by a sensible architecture (you resolve, TASK.md gets rewritten, architect re-runs). Planner produces batches within the L budget (4-6) and declares which are independent. Batches then build in dependency order, in parallel where the plan allows.

### Small tasks

```
/flow-lite bump the rate limit on /api/search from 60 to 200 req/min
```

Likely one question (per-IP or per-key?), then the change, then the existing rate-limit spec gets updated and run. No plan, no artifact directory, no approval gate.

```
/flow-lite read the files and write the release notes for the next version
```

The "read the files" phrasing triggers Step 1: it grounds in the changelog and the diff before asking anything, so the questions are about audience and depth instead of about what shipped. Not a dev task, so Step 4 is skipped entirely.

## Anti-loop guards

The biggest token-waste risk in AI-assisted TDD is unconscious test/fix looping. Flow tracks counters across the workflow and stops cleanly when limits are hit:

| Counter | Cap | On trip |
|---|---|---|
| Per-test fix attempts | 3 | Stop, escalate |
| Builder re-dispatches per batch | 3 | Stop, escalate |
| Full-suite runs in Phase 6 | 3 | Stop, report state |
| Total test/fix cycles across workflow | 5 | Stop, check in |
| Security review cycles in Phase 5 | 3 | Stop, present open findings and wait for direction |
| Architect/TASK conflict cycles | 3 | Stop, ask user how to proceed |
| Test-lock violations | 0 | Stop immediately, name the files, escalate |
| Concurrent batch builders | 3 | Remaining batches go in the next group |

A "diagnose before retry" rule requires the orchestrator to articulate a one-sentence root cause before any retry dispatch. If it can't articulate, it asks you instead.

These counters belong to `/flow`. `/flow-lite` has no test/fix loop to bound — it makes the change, reconciles the related tests once, and stops.

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

`/flow-lite` enforces the same list, with one deliberate difference: it will perform one of these only if you explicitly confirm it in the same turn. Under `/flow` they are absolute — there is no confirmation path.

## Configuration

### Per-project conventions

Flow respects your project's `CLAUDE.md`. Conventions, test rules, and no-gos defined there override Flow's defaults for that project. Anti-loop guards and hard guards remain in force regardless.

### Model selection

Subagent model assignments are set in each agent's frontmatter. To change them, edit the agent files directly:

- `agents/flow-pm.md` — Sonnet
- `agents/flow-triager.md` — Sonnet (also writes MAP.md)
- `agents/flow-architect.md` — inherits session model (every task)
- `agents/flow-planner.md` — inherits session model
- `agents/flow-batch-builder.md` — inherits session model (main path: tests + implementation per batch)
- `agents/flow-test-runner.md` — Haiku
- `agents/flow-failure-triager.md` — Sonnet
- `agents/flow-security-reviewer.md` — Sonnet
- `agents/flow-implementer.md` — Opus (off-path: security fixes, regressions)
- `agents/flow-test-author.md` — Sonnet (off-path: coverage gaps)
- `agents/flow-reporter.md` — Haiku

Any model alias (`opus`, `sonnet`, `haiku`) or full model ID is accepted.

`/flow-lite` has nothing to configure here — it dispatches no subagents and runs on whatever model your session is already using.

## Compatibility

- Requires Claude Code (skills + subagents are Claude Code features)
- Tested on TypeScript / Next.js, Ruby on Rails, Go, and Python projects
- Works with any test runner the project already uses; no opinionated stack

## Contributing

Issues and pull requests welcome. Before opening a PR:

- Run `/flow` against a real feature in a test project — or `/flow-lite`, if that's what you changed; describe the run in your PR
- Don't change the anti-loop guard logic without a specific reason — those numbers came from real token-waste incidents
- Keep subagent system prompts terse — every token is paid on every invocation

## License

MIT — see [LICENSE](LICENSE).

## Related

- [Superpowers](https://github.com/obra/superpowers) — broader, more comprehensive workflow plugin. Worth using if your priorities are different from Flow's.
- [Claude Code documentation](https://code.claude.com/docs) — official docs for skills and subagents.
