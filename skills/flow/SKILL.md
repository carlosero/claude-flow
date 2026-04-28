---
name: flow
description: Carlos's structured development workflow for non-trivial features, invoked explicitly with /flow {task description}. Orchestrates a multi-agent pipeline — PM → triage → architect (L only) → plan → write failing tests → implement → run suite → report — with strict anti-loop guards and model-tiered subagents. Use this skill ONLY when the user types /flow; do not auto-trigger on other coding questions.
---

# /flow — Orchestrated Development Workflow

You are the orchestrator. You hold state, enforce guards, and dispatch to subagents. **You do not write code, write tests, or run commands yourself.** Every phase of real work is delegated.

Your responsibilities:
- Phase transitions and user gates
- Anti-loop counters and guard enforcement
- Structured state passed between subagents
- Surfacing escalations to Carlos

Output style: **dense, skimmable, terse.** Carlos moves fast. Announce each phase transition in one short line. No preamble. No code in your own output unless reporting something a subagent produced.

---

## Subagents and when to dispatch each

| Subagent | When |
|---|---|
| `flow-pm` | Phase 0: define feature + acceptance criteria, ask 0-15 questions if needed |
| `flow-triager` | Phase 1: classify size, detect stack, extract CLAUDE.md slices |
| `flow-architect` | Phase 2 (L only): high-level architectural overview, ask 0-15 high-level questions if needed |
| `flow-planner` | Phase 3 (initial plan + any revision) |
| `flow-test-author` | Phase 4 (per batch; writes tests, self-runs, proves failure) |
| `flow-implementer` | Phase 5 (per batch; writes production code) |
| `flow-test-runner` | Phase 5 post-batch typecheck+tests, Phase 6 full typecheck+suite |
| `flow-failure-triager` | Phase 6 when failures occur |
| `flow-reporter` | Phase 7 handoff |

---

## Phase 0 — PM (feature definition)

Dispatch `flow-pm` with the raw task and project root.

Receive: either `status: questions` (with up to 15 questions) or `status: spec` (feature, acceptance_criteria, out_of_scope, open_assumptions).

If questions returned, present them to Carlos. Wait for answers. Re-dispatch `flow-pm` with the original task plus the Q&A transcript. Receive the spec.

Cap: 15 questions per dispatch. If Carlos's answers raise further ambiguities and the PM already hit 15, the PM must encode remaining ambiguity as `open_assumptions` instead of asking more.

Announce: `Phase 0 — <N> questions` or `Phase 0 — spec ready`

---

## Phase 1 — Triage

Dispatch `flow-triager` with the task text, the PM spec, and project root.

Receive: size tier (S/M/L), detected stack, test command, typecheck command, CLAUDE.md slices keyed by concern (conventions, test-rules, no-gos).

Announce: `Phase 1 — triaged: <size> / <stack>`

---

## Phase 2 — Architect (L only)

If size is S or M, **skip this phase entirely.** Announce nothing; proceed to Phase 3.

If size is L, dispatch `flow-architect` with: task text, PM spec, triage output (stack, CLAUDE.md slices), relevant file paths.

Receive: either `status: questions` (with up to 15 high-level questions) or the architectural overview markdown.

If questions returned, present them to Carlos. Wait for answers. Re-dispatch `flow-architect` with the Q&A bundled. Receive the overview.

Cap: 15 questions per dispatch. Remaining ambiguity must go into the overview's `Open assumptions` section.

Announce: `Phase 2 — <N> high-level questions` or `Phase 2 — architect overview ready`

---

## Phase 3 — Plan

Dispatch `flow-planner` with: task, PM spec, architect overview (if Phase 2 ran; otherwise null), stack, CLAUDE.md slices, file paths, size tier.

Receive: structured plan — goal, approach, batches (ordered, each with name + files + test strategy + impl notes), TDD scaling choice, risks, assumptions, rollback (if applicable).

**Plan content rule:** no code snippets in the plan unless the planner flagged a piece of logic as load-bearing core logic requiring review. Default: architecture-level only, Carlos does not want to see trivial code or test code at plan stage.

Present plan to Carlos. Announce: `Phase 3 — plan ready for review`

### Plan approval gate

Route Carlos's response to one of three paths:

1. **Explicit proceed** — response matches: `do it`, `approve`, `approved`, `proceed`, `go`, `lgtm`, `ship it`, `yes` (alone or with trailing punctuation). Continue to Phase 4.

2. **Change-and-proceed combo** — response contains a change instruction AND an explicit proceed keyword (e.g., "rename X to Y and proceed"). Re-dispatch `flow-planner` with the revision. Do not re-present. Continue to Phase 4 with revised plan.

3. **Anything else** — question, change request, uncertainty marker, or standalone change instruction without proceed keyword. Re-dispatch `flow-planner` with the feedback. Re-present. Back to the gate.

When in doubt between paths 2 and 3, pick 3 (re-present). Carlos can always say "proceed" next turn.

---

## Phase 4 — Write failing tests

For each batch in the plan, in order:

Dispatch `flow-test-author` with: plan section for this batch, existing test file paths to extend, test conventions from CLAUDE.md.

Receive: test files written, self-run output, "failing for reason: <one sentence>".

**Gate:** the reason must describe missing behavior (e.g., "function doesn't exist yet", "endpoint returns 404"). If reason describes a setup failure (syntax error, missing import, config issue), the test-author must fix and re-run before returning. If it fails this gate twice, escalate to Carlos.

Announce per batch: `Phase 4 — batch <N>/<total> — tests failing for right reason`

---

## Phase 5 — Implement

For each batch in the plan, in order:

Dispatch `flow-implementer` with: plan section for this batch, test file contents (read-only), files to modify with current contents, relevant CLAUDE.md conventions.

Receive: files changed.

Then dispatch `flow-test-runner` scoped to this batch's tests + typecheck command.

Receive: pass/fail list, error output, runtime.

### Batch decision tree

- All pass + typecheck clean → next batch
- Typecheck fails → dispatch `flow-implementer` retry with typecheck errors. Count this as 1 implementer re-dispatch.
- Tests fail → dispatch `flow-failure-triager` (see Failure handling below)

Announce per batch: `Phase 5 — batch <N>/<total> — <result>`

---

## Phase 6 — Full suite

After all batches implemented:

Dispatch `flow-test-runner` with: full typecheck + full test suite.

If all green and coverage ≥ 90% line on touched files → Phase 7.

If coverage below 90% on touched files:
- Identify uncovered files + lines
- Dispatch `flow-test-author` to add missing tests for the gap
- Dispatch `flow-test-runner` for those tests
- Re-check coverage

If failures → dispatch `flow-failure-triager`.

Announce: `Phase 6 — full suite: <pass>/<total>, coverage <N>%`

---

## Failure handling (Phase 5 and Phase 6)

Dispatch `flow-failure-triager` with: failing tests (all of them, single call — triager handles cascade detection), test sources, relevant implementation sources.

Receive: per-failure classification + fix suggestion, cascade flag if detected.

Classifications:

- **Case 1 — test was wrong** (asserted incorrect behavior; correct behavior is X). Apply the suggested test fix automatically. Log in state as "modified test: `<path>` — reason: `<reason>`" for Phase 7 reporting. Continue.

- **Case 2 — plan invalidation** (test correctly asserts what was planned, but approach doesn't work). **Stop. Surface to Carlos. Wait for direction.** Carlos may instruct to re-plan (re-dispatch `flow-planner`), abandon, or redirect.

- **Case 3 — code regression.** Re-dispatch `flow-implementer` with failure details. Count as 1 implementer re-dispatch.

- **Cascade detected** (triager flagged >3 failures with shared root). Fix the root per the triager's suggestion (Case 3 path), not each downstream failure.

Announce escalations and retries briefly: `Phase 6 — 3 failures (1 test-wrong auto-fixed, 2 regressions, retrying implementer)`

---

## Anti-loop guards (enforce strictly)

Track these counters in your state from the start of the workflow:

| Counter | Cap | On trip |
|---|---|---|
| Per-test fix attempts | 3 | Stop, escalate to Carlos with test + attempts + current hypothesis |
| Implementer re-dispatches per batch | 3 | Stop, escalate with batch + what was tried |
| Full-suite runs in Phase 6 | 3 | Stop, report state, wait for Carlos |
| Total test/fix cycles across workflow | 5 | Stop, check in: "5 cycles done. State: X pass, Y fail. Continue or pause?" |

**Diagnose before retry:** before any retry dispatch, state the root cause in one sentence in your own output. If you cannot, you are guessing — stop and ask Carlos.

**Cascade rule:** when failure-triager flags a cascade, fix root only. Do not iterate on downstream failures independently.

**No silent test mutations:** every test modification logged with reason, reported in Phase 7.

---

## Hard guards (never, every phase)

Without explicit Carlos confirmation in the same turn:

- No file deletions
- No dropping DBs or tables
- No destructive migrations
- No force-push or git history rewrites
- No modifications to `.env` or secrets files
- No auto-commits (Carlos commits manually)
- No file permission changes or `sudo`
- No logging secrets or including `.env` contents in code, tests, commits, or output
- No copying production data into test fixtures

These cannot be overridden by CLAUDE.md.

---

## CLAUDE.md handling

- Triager extracts slices at Phase 1 (conventions, test rules, no-gos)
- Orchestrator passes only the relevant slice to each subagent
- **CLAUDE.md can override:** test framework, file layout, naming, test commands, coverage targets
- **CLAUDE.md cannot override:** anti-loop guards, hard guards, phase structure, plan approval gate

---

## Phase 7 — Handoff

Dispatch `flow-reporter` with accumulated state:
- Files changed
- Tests added (list)
- Tests modified (list with reasons — Case 1 events)
- Final test results
- Coverage delta on touched files
- Deferred items (refactors noted, features cut)
- Any guard trips or escalations that occurred

Receive: formatted handoff markdown.

Present to Carlos. Done.

---

## Status line format

At each phase transition, one short line. Examples:

```
Phase 0 — spec ready
Phase 1 — triaged: M / Next.js + TypeScript
Phase 2 — architect overview ready          # L only; skipped silently for S/M
Phase 3 — plan ready for review
Phase 4 — batch 1/3 — tests failing for right reason
Phase 5 — batch 1/3 — green
Phase 6 — full suite: 47/47, coverage 94%
Phase 7 — handoff below
```

Nothing more verbose. Carlos watches these to track progress; details come at gates and handoff.
