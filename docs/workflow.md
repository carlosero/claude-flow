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
~/.claude/tasks/{project_folder}/{unix_ts}/
  TASK.md       # PM-owned: feature, AC checkboxes, out-of-scope, open assumptions
  ARCHITECT.md  # Architect-owned: shape, subsystems, data flow, integration points, trade-offs
  PLAN.md       # Planner-owned: goal, approach, batches, AC-to-batch mapping, risks, rollback
  SECURITY.md   # Security-reviewer-owned: findings (overwritten each cycle)
  REPORT.md     # Reporter-owned: Phase 8 handoff
  STATE.md      # Orchestrator-owned: task metadata, triage, counters, batch progress, modified-test log, escalations
```

Each artifact is written only by its owner. Subagents read what they need from disk instead of receiving it in-band. You can hand-edit any file between phases — re-dispatched agents re-read on entry, so your edits take effect immediately.

The orchestrator has two narrow write exceptions: it maintains STATE.md throughout, and it ticks AC checkboxes in TASK.md as each Phase 5 batch turns green.

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

The AC are **markdown checkboxes**. Every AC becomes a test target — every criterion must be reachable by at least one batch's tests, and the planner's AC-to-batch mapping makes that contract explicit. As Phase 5 batches turn green, the orchestrator ticks the corresponding boxes.

```
Phase 0 — 2 questions
```

You answer; PM writes TASK.md:

```
Phase 0 — TASK.md ready
```

## Phase 1 — Triage

The triager (Haiku) reads TASK.md, then inspects the project root. It produces:

- **Size tier** — `S`, `M`, or `L`
- **Stack** — detected framework, test runner, typecheck command
- **CLAUDE.md slices** — relevant conventions, test rules, no-gos extracted from your project's CLAUDE.md

The orchestrator writes these into STATE.md under `## Triage`. You see one short status line. No interaction required.

```
Phase 1 — triaged: M / Next.js + TypeScript + Vitest
```

## Phase 2 — Architect

The architect (Opus) runs on **every task**. It reads TASK.md and STATE.md (for triage context), then reads broadly enough through the codebase to understand integration points and existing patterns. Depth is calibrated to triage size — a quick sweep on S, a deeper read on L. It produces ARCHITECT.md: shape (2–4 sentences), subsystems and boundaries, data flow, integration points, key trade-offs, open assumptions. No code, no batches, no test strategy — that's the planner's job.

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

## Phase 4 — Write failing tests

For each batch, the test-author (Sonnet) writes tests, runs them, and confirms they fail **for the right reason** — meaning the behavior doesn't exist yet, not because of syntax errors or missing imports.

If a test fails for a setup reason (typo, missing module), the test-author fixes and re-runs until all failures are right-reason failures. If it can't get there in 2 attempts, it escalates.

```
Phase 4 — batch 1/3 — tests failing for right reason
```

## Phase 5 — Implement

For each batch, in order:

1. Implementer (Opus) reads TASK.md, ARCHITECT.md, PLAN.md, then writes the minimum production code to make this batch's tests pass
2. Test-runner (Haiku) runs typecheck + this batch's tests
3. If green, orchestrator ticks the AC checkboxes in TASK.md that this batch satisfies (per PLAN.md's AC-to-batch mapping); next batch
4. If typecheck fails, implementer retries with errors
5. If tests fail, failure-triager classifies; orchestrator routes by classification

```
Phase 5 — batch 1/3 — green
Phase 5 — batch 2/3 — green
Phase 5 — batch 3/3 — green
```

## Phase 6 — Security review

Security review runs **before** the full suite. If a finding requires code changes, re-running the full suite afterwards would be wasted work — so the review goes first, the fix loop has no test run inside it, and the full suite runs once at the end as the final gate.

The security reviewer (Sonnet) runs `git diff` and `git status` to inspect every uncommitted change, then checks the diff against a category list (injection, XSS, auth/authz gaps including IDOR, secrets, frontend env leakage, CSRF, SSRF, path traversal, open redirect, insecure deserialization, mass assignment, weak crypto, CORS, sensitive logging). It writes SECURITY.md (overwriting any prior cycle) showing current open findings plus resolution notes for prior-cycle findings.

Scope: only issues *introduced or worsened by this diff*. Pre-existing problems outside the change are out of scope by design.

If clean:

```
Phase 6 — security: clean
```

If findings:

```
Phase 6 — security: 2 findings (1 high, 1 medium), routing to implementer (cycle 1/3)
```

The orchestrator then:

1. Hands the findings to the implementer (Opus) to fix
2. Re-runs the security reviewer to confirm each prior finding is resolved and no new issue was introduced

No test run inside this loop — the Phase 7 full suite is the gate. If a security fix breaks a test, the failure-triager in Phase 7 picks it up.

This loops until the review comes back clean or the security-cycle cap (3) trips. On trip, the orchestrator surfaces remaining findings to you with the cycles already spent and waits for direction.

## Phase 7 — Full suite

Once Phase 6 is clean:

1. Test-runner runs full typecheck
2. Test-runner runs full test suite
3. Test-runner reports coverage on touched files

If all green and coverage ≥ 90% on touched files, orchestrator confirms all AC checkboxes in TASK.md are ticked, → Phase 8.

If coverage below 90% on touched files, test-author writes the missing tests, test-runner re-runs.

If failures, failure-triager (Sonnet) classifies each:

- **Case 1: test was wrong** — fix automatically, log for the handoff
- **Case 2: plan invalidation** — STOP. Surface to user. Wait.
- **Case 3: code regression** — re-dispatch implementer

Cascades (3+ failures with shared root) are fixed at the root, not per-failure.

```
Phase 7 — full suite: 47/47, coverage 94%
```

## Phase 8 — Handoff

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

The task directory persists after Phase 8. The full audit trail (TASK / ARCHITECT / PLAN / SECURITY / STATE / REPORT) is available at `~/.claude/tasks/{project}/{unix_ts}/` for as long as you want to keep it.

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
