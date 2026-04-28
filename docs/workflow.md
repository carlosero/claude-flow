# Workflow guide

Phase-by-phase walkthrough of what happens when you run `/flow`.

For *why* it works this way, see [architecture.md](architecture.md).

## When to use `/flow`

Use it for non-trivial features:
- Adding new behavior across multiple files
- Anything that should have tests
- Anything you'd want a plan for before implementing

**Don't** use `/flow` for:
- Typos or single-line changes
- Renames you can grep for
- Quick experiments
- Anything where a real plan + TDD ceremony costs more than the work itself

If the task is too small for ceremony, just ask Claude directly without `/flow`.

## Invocation

```
/flow {task description}
```

Examples:

```
/flow add a /api/health endpoint that returns 200 with uptime in seconds
/flow implement saved-search persistence for the dashboard search bar
/flow add real-time chat with message history and typing indicators
```

## Phase 0 — PM (feature definition)

The PM (Sonnet) is the first responder. It reads your task and turns it into a tight feature definition with explicit, testable acceptance criteria. If the task has gaps or contradictions, it asks up to 15 multi-choice questions before drafting the spec.

The artifact looks like:

```
feature: <one short paragraph>
acceptance_criteria:
  - <observable, testable criterion>
  - <observable, testable criterion>
out_of_scope:
  - <thing the user might assume is included but isn't>
open_assumptions:
  - <residual assumption made because the question budget was capped>
```

The acceptance criteria become the test targets — every criterion should be reachable by at least one batch's tests.

```
Phase 0 — 2 questions
```

You answer; PM returns the spec:

```
Phase 0 — spec ready
```

## Phase 1 — Triage

The triager (Haiku) reads your task and the PM spec, then inspects the project root. It produces:

- **Size tier** — `S`, `M`, or `L`
- **Stack** — detected framework, test runner, typecheck command
- **CLAUDE.md slices** — relevant conventions, test rules, no-gos extracted from your project's CLAUDE.md

You see one short status line. No interaction required.

```
Phase 1 — triaged: M / Next.js + TypeScript + Vitest
```

## Phase 2 — Architect (L only)

For S and M tasks, this phase is **skipped silently**. Flow goes straight from triage to plan.

For L tasks, the architect (Opus) reviews the PM spec, the triage output, and relevant integration points in the codebase, then produces a high-level overview: subsystems and boundaries, data flow, integration points, key trade-offs, open assumptions. No code, no batches, no test strategy — that's the planner's job.

The architect can ask up to 15 high-level questions before producing the overview (subsystem placement, sync vs async, transactional boundaries, etc.).

```
Phase 2 — 4 high-level questions
```

You answer; architect returns the overview:

```
Phase 2 — architect overview ready
```

## Phase 3 — Plan

The planner (Opus, ultrathink) produces a structured plan:

```markdown
## Goal
<one sentence>

## Approach
- <architecture decision>
- <architecture decision>

## Batches (TDD scaling: batched)

### Batch 1 — <name>
- Files to create: ...
- Files to modify: ...
- Test strategy: ...
- Implementation notes: ...

### Batch 2 — <name>
...

## Risks & assumptions
- ...

## Rollback
<only for destructive ops>
```

**Plans don't include code** unless a piece of logic is genuinely load-bearing (complex algorithm, subtle contract). When that happens, a sketch is tagged `[core logic preview]`.

### Approval gate

Three response paths:

| You say | Flow does |
|---|---|
| "approve" / "go" / "proceed" / "lgtm" / "ship it" | Continues to Phase 4 |
| "change X" / "what about Y?" / "I don't like Z" | Re-dispatches planner with feedback, re-presents |
| "change X and proceed" | Re-dispatches planner silently, continues |

When in doubt, Flow re-presents. You can always say "proceed" on the next turn.

## Phase 4 — Write failing tests

For each batch, the test-author (Sonnet) writes tests, runs them, and confirms they fail **for the right reason** — meaning the behavior doesn't exist yet, not because of syntax errors or missing imports.

If a test fails for a setup reason (typo, missing module), the test-author fixes and re-runs until all failures are right-reason failures. If it can't get there in 2 attempts, it escalates.

```
Phase 4 — batch 1/3 — tests failing for right reason
```

## Phase 5 — Implement

For each batch, in order:

1. Implementer (Opus) writes the minimum production code to make this batch's tests pass
2. Test-runner (Haiku) runs typecheck + this batch's tests
3. If green, next batch
4. If typecheck fails, implementer retries with errors
5. If tests fail, failure-triager classifies; orchestrator routes by classification

```
Phase 5 — batch 1/3 — green
Phase 5 — batch 2/3 — green
Phase 5 — batch 3/3 — green
```

## Phase 6 — Full suite

After all batches implemented:

1. Test-runner runs full typecheck
2. Test-runner runs full test suite
3. Test-runner reports coverage on touched files

If all green and coverage ≥ 90% on touched files, → Phase 7.

If coverage below 90% on touched files, test-author writes the missing tests, test-runner re-runs.

If failures, failure-triager (Sonnet) classifies each:

- **Case 1: test was wrong** — fix automatically, log for the handoff
- **Case 2: plan invalidation** — STOP. Surface to user. Wait.
- **Case 3: code regression** — re-dispatch implementer

Cascades (3+ failures with shared root) are fixed at the root, not per-failure.

```
Phase 6 — full suite: 47/47, coverage 94%
```

## Phase 7 — Handoff

The reporter (Haiku) formats a summary:

```markdown
## Done
<one-sentence summary>

## Files changed
- ...

## Tests added
- ...

## Tests modified ⚠️
- `path/to/test.ts` — <reason>

## Final results
- Suite: 47/47 passing
- Typecheck: clean
- Coverage on touched files: 94%

## Deferred
- <refactor opportunity noted but not done>
```

The ⚠️ on "Tests modified" is intentional — every test mutation is surfaced explicitly so you can sanity-check the rationale.

You commit when ready. Flow never auto-commits.

## What can go wrong, and what happens

### Hit per-test fix cap (3 attempts)
Orchestrator stops, shows the test, the 3 attempts, and the current hypothesis. You direct.

### Hit implementer cap (3 retries per batch)
Same pattern — stop, show what was tried, you direct.

### Hit total cycle cap (5 cycles)
Orchestrator pauses: "5 cycles done. State: X pass, Y fail. Continue or pause?" You decide.

### Plan invalidation mid-flow (Case 2)
A test reveals the plan's approach can't work. Orchestrator stops, surfaces the conflict, waits for direction. You may re-plan, redirect, or abandon.

### Cascade detected (3+ failures, same root)
Failure-triager flags it. Orchestrator fixes the root only — does not iterate on downstream failures independently.

## Customization

### Per-project conventions
Your project's `CLAUDE.md` is read at Phase 1 (triage) and respected throughout. Conventions, test rules, and no-gos override Flow defaults — but anti-loop guards and hard guards stay enforced.

### Changing model assignments
Edit the `model` field in the relevant `agents/flow-*.md` file. Aliases (`opus`, `sonnet`, `haiku`) auto-track latest releases; full IDs pin to specific versions.

### Changing guard caps
Edit the SKILL.md anti-loop guards table. Defaults are tuned for typical M-size features. Real-use feedback should drive any adjustments.
