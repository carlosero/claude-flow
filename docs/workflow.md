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

## The task directory

Before Phase 0, the orchestrator creates a per-task directory:

```
~/.flow/tasks/{project_folder}/{unix_ts}/
  TASK.md       # PM-owned: feature, AC checkboxes, out-of-scope, open assumptions
  ARCHITECT.md  # Architect-owned: shape, subsystems, data flow, integration points, trade-offs
  PLAN.md       # Planner-owned: goal, approach, batches, AC-to-batch mapping, risks, rollback
  SECURITY.md   # Security-reviewer-owned: findings (overwritten each cycle)
  REPORT.md     # Reporter-owned: Phase 7 handoff
  STATE.md      # Orchestrator-owned: task metadata, triage, counters, batch progress, modified-test log, escalations
```

Each artifact is written only by its owner. Subagents read what they need from disk instead of receiving it in-band. You can hand-edit any file between phases — re-dispatched agents re-read on entry, so your edits take effect immediately.

The orchestrator has two narrow write exceptions: it maintains STATE.md throughout, and it ticks AC checkboxes in TASK.md as each Phase 4 batch turns green.

## Phase 0 — PM (feature definition)

The PM (Sonnet) is the first responder. It reads your task and turns it into a tight feature definition with explicit, testable acceptance criteria — written to disk as TASK.md. If the task has gaps or contradictions, it asks up to 15 multi-choice questions before drafting the spec.

TASK.md looks like:

```markdown
# TASK

## Feature
<one short paragraph>

## Acceptance criteria
- [ ] <observable, testable criterion>
- [ ] <observable, testable criterion>

## Out of scope
- <thing the user might assume is included but isn't>

## Open assumptions
- <residual assumption made because the question budget was capped>
```

The AC are **markdown checkboxes**. Every AC becomes a test target — every criterion must be reachable by at least one batch's tests, and the planner's AC-to-batch mapping makes that contract explicit. As Phase 4 batches turn green, the orchestrator ticks the corresponding boxes.

```
Phase 0 — 2 questions
```

You answer; PM writes TASK.md:

```
Phase 0 — TASK.md ready
```

## Phase 1 — Triage

The triager (Sonnet) reads TASK.md, then inspects the project root. It produces:

- **Size tier** — `S`, `M`, or `L` (this sets the plan's batch budget)
- **Commands** — test, single-file test, typecheck, coverage, lint, format
- **MAP.md** — the codebase map: test and source conventions, how this repo builds fixtures and doubles, the key paths for this task, your CLAUDE.md slices, and gotchas

MAP.md is the artifact that makes the rest of the run cheap. Every later agent reads it instead of re-deriving your project's conventions from scratch — which is what they used to do, once per dispatch. It's why triage is a Sonnet call rather than a Haiku one: a shallow map gets ignored, and then everyone re-explores anyway.

The orchestrator writes the summary into STATE.md under `## Triage`. You see one short status line. No interaction required.

```
Phase 1 — triaged: M / Next.js + TypeScript + Vitest / MAP.md ready
```

## Phase 2 — Architect

The architect (Opus) runs on **every task**. It reads TASK.md and MAP.md, then starts from the map's key paths and reads further only where the integration points and existing patterns aren't yet clear. Depth is calibrated to triage size — a quick sweep on S, a deeper read on L. It produces ARCHITECT.md: shape (2–4 sentences), subsystems and boundaries, data flow, integration points, key trade-offs, open assumptions. No code, no batches, no test strategy — that's the planner's job.

The architect can ask up to 15 high-level questions before producing ARCHITECT.md (subsystem placement, sync vs async, transactional boundaries, etc.):

```
Phase 2 — 4 high-level questions
```

It can also raise a **conflict** — when one or more AC in TASK.md cannot be satisfied by any sensible architecture (e.g., two AC contradict each other, or an AC fights an immovable codebase constraint). When this happens, the architect does *not* write ARCHITECT.md. Instead it returns `status: conflict` with the AC verbatim and a one-sentence reason. The orchestrator surfaces it:

```
Phase 2 — conflict: AC #3 ("notifications arrive within 50ms") cannot be satisfied — the existing message bus has a 200ms p95.
```

You tell Flow how TASK.md should change. The orchestrator rewrites TASK.md per your direction (preserving every other field) and re-dispatches the architect. This loop is bounded by the architect/TASK conflict cycle cap (3); on trip, Flow stops and asks you how to proceed.

Once stable:

```
Phase 2 — ARCHITECT.md ready
```

## Phase 3 — Plan

The planner (Opus, ultrathink) reads TASK.md, ARCHITECT.md, and STATE.md, then writes PLAN.md:

```markdown
# PLAN

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
- Satisfies AC: 1, 3

### Batch 2 — <name>
...

## AC → Batch mapping
- AC 1 (<short paraphrase>): batch 1
- AC 2 (<short paraphrase>): batch 2
- AC 3 (<short paraphrase>): batch 1, 2

## Risks & assumptions
- ...

## Rollback
<only for destructive ops>
```

The AC-to-batch mapping is mandatory — it maps every TASK.md checkbox to the batch(es) that satisfy it, and the orchestrator uses it to tick checkboxes as batches turn green.

**Plans don't include code** unless a piece of logic is genuinely load-bearing (complex algorithm, subtle contract). When that happens, a sketch is tagged `[core logic preview]`.

### Approval gate

Three response paths:

| You say | Flow does |
|---|---|
| "approve" / "go" / "proceed" / "lgtm" / "ship it" | Continues to Phase 4 |
| "change X" / "what about Y?" / "I don't like Z" | Re-dispatches planner with feedback, re-presents |
| "change X and proceed" | Re-dispatches planner silently, continues |

When in doubt, Flow re-presents. You can always say "proceed" on the next turn.

## Phase 4 — Build batches

One agent per batch (`flow-batch-builder`, Opus) does the full red-green cycle in a single context:

1. Reads MAP.md and ARCHITECT.md, plus the batch brief the orchestrator passes inline — that batch's files, test strategy, notes, and the verbatim acceptance criteria it has to satisfy
2. Writes the tests and runs them, confirming they fail **for the right reason** — the behavior doesn't exist yet, not a syntax error or a missing import
3. **Hash-locks the test files** and reports the digests
4. Writes the minimum production code to make them pass
5. Runs typecheck and the scoped tests again

Then the test-runner (Haiku) independently re-verifies: typecheck, the batch's tests, and the hashes. If a test file changed between the freeze and the green, that's a lock violation — the run stops and tells you which files, because the passing suite wasn't earned against the tests that were proven failing.

Writing tests and writing code used to be two separate phases with two separate agents per batch. They were merged because both had to learn the same things about your codebase to do their jobs, and the second one started from nothing — which is where flow runs were actually spending their time. The guarantee that the implementing agent can't weaken the tests is now enforced by the hash lock instead of by the context boundary.

**Batches run in parallel where the plan allows.** The planner marks each batch's dependencies; the orchestrator dispatches every ready batch at once, up to three at a time, and falls back to serial for any two batches whose file lists overlap.

If green, the orchestrator ticks the AC checkboxes that batch satisfies and moves to the next ready batch. If typecheck fails, the builder retries with the errors. If tests fail, the failure-triager classifies and the orchestrator routes from there.

```
Phase 4 — batch 1/4 — green (lock verified)
Phase 4 — batches 2,3/4 dispatched in parallel
Phase 4 — batch 2/4 — green (lock verified)
Phase 4 — batch 3/4 — green (lock verified)
Phase 4 — batch 4/4 — green (lock verified)
```

## Phase 5 — Security review

Security review runs **before** the full suite. If a finding requires code changes, re-running the full suite afterwards would be wasted work — so the review goes first, the fix loop has no test run inside it, and the full suite runs once at the end as the final gate.

The security reviewer (Sonnet) runs `git diff` and `git status` to inspect every uncommitted change, then checks the diff against a category list (injection, XSS, auth/authz gaps including IDOR, secrets, frontend env leakage, CSRF, SSRF, path traversal, open redirect, insecure deserialization, mass assignment, weak crypto, CORS, sensitive logging). It writes SECURITY.md (overwriting any prior cycle) showing current open findings plus resolution notes for prior-cycle findings.

Scope: only issues *introduced or worsened by this diff*. Pre-existing problems outside the change are out of scope by design.

If clean:

```
Phase 5 — security: clean
```

If findings:

```
Phase 5 — security: 2 findings (1 high, 1 medium), routing to implementer (cycle 1/3)
```

The orchestrator then:

1. Hands the findings to the implementer (Opus) to fix
2. Re-runs the security reviewer to confirm each prior finding is resolved and no new issue was introduced

No test run inside this loop — the Phase 6 full suite is the gate. If a security fix breaks a test, the failure-triager in Phase 6 picks it up.

Security fixes touch production code only; the batch test locks stay in force through this phase.

This loops until the review comes back clean or the security-cycle cap (3) trips. On trip, the orchestrator surfaces remaining findings to you with the cycles already spent and waits for direction.

## Phase 6 — Full suite

Once Phase 5 is clean:

1. Test-runner runs full typecheck
2. Test-runner runs the full test suite and re-verifies every batch's test lock
3. Test-runner reports coverage on touched files

If all green, locks verified, and coverage ≥ 90% on touched files, the orchestrator confirms all AC checkboxes in TASK.md are ticked → Phase 7.

If coverage is below 90% on touched files, the test-author (Sonnet) writes tests for the uncovered lines and the test-runner re-runs. It can also report a gap as `not_covered` with a reason — composition roots, thin SDK wrappers, integration-gated code — and that's accepted rather than papered over with tests that assert nothing.

If failures, failure-triager (Sonnet) classifies each:

- **Case 1: test was wrong** — the batch builder is re-dispatched with explicit authorization to amend that test, re-proves it red, and re-locks it. Logged for the handoff. This is the only way a locked test changes.
- **Case 2: plan invalidation** — STOP. Surface to user. Wait.
- **Case 3: code regression** — dispatch the implementer to fix the code

Cascades (3+ failures with shared root) are fixed at the root, not per-failure.

```
Phase 6 — full suite: 47/47, coverage 94%
```

## Phase 7 — Handoff

The reporter (Haiku) reads the entire task dir (TASK, ARCHITECT, PLAN, SECURITY, STATE) and writes REPORT.md:

```markdown
# REPORT

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

## Security findings resolved
- `app/api/users/route.ts` — high — auth (added session check on PATCH handler)
- ...

## Deferred
- <refactor opportunity noted but not done>
```

The ⚠️ on "Tests modified" is intentional — every test mutation is surfaced explicitly so you can sanity-check the rationale.

The task directory persists after Phase 7. The full audit trail (TASK / MAP / ARCHITECT / PLAN / SECURITY / STATE / REPORT) is available at `~/.flow/tasks/{project}/{unix_ts}/` for as long as you want to keep it.

You commit when ready. Flow never auto-commits.

## What can go wrong, and what happens

### Hit per-test fix cap (3 attempts)
Orchestrator stops, shows the test, the 3 attempts, and the current hypothesis. You direct.

### Hit implementer cap (3 retries per batch)
Same pattern — stop, show what was tried, you direct.

### Hit total cycle cap (5 cycles)
Orchestrator pauses: "5 cycles done. State: X pass, Y fail. Continue or pause?" You decide.

### Hit security review cap (3 cycles)
Orchestrator stops in Phase 6, lists the open findings and the fix attempts so far, and waits for direction. You may direct the implementer with extra context, accept lower-severity findings as deferred, or abandon.

### Hit architect/TASK conflict cap (3 cycles)
The architect kept finding AC conflicts that couldn't be resolved by your TASK.md rewrites. Orchestrator stops at Phase 2 with the current conflict list and asks how to proceed. Usually means the spec needs a deeper rethink rather than another edit.

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
