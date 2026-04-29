# Architecture

This doc explains *why* Flow looks the way it does. If you're trying to understand how to use it, see [workflow.md](workflow.md). If you're trying to understand what tradeoffs were made and where to push if you want to change them, you're in the right place.

## Design goals

Flow optimizes for three things, in order:

1. **Token efficiency** — no model bigger than the task warrants, no context window bigger than the subagent needs
2. **No infinite loops** — bounded retries with explicit escalation, no silent burning of cycles
3. **Honest TDD** — failing tests proven failing for the right reason, before any production code is written

Things Flow deliberately does *not* optimize for:

- Maximum autonomy. Flow stops at the plan gate. By design.
- One-shot speed. Phased pipelines have overhead.
- Doing trivial work. `/flow` is for non-trivial features. Don't use it on typos.

## The skill-orchestrator-subagent split

Flow is one skill (`/flow`) that orchestrates many subagents.

The skill is the entrypoint and the state machine. It holds the cycle counters, enforces the guards, makes phase transitions, and dispatches to subagents. **It writes no code itself.**

Subagents do bounded technical work. Each runs in its own fresh context window, sees only what the orchestrator passed in, and dies after returning. Their outputs flow back into the orchestrator's state.

Why split this way? Two reasons:

1. **Context isolation.** A failure-triager looking at test #7 doesn't need to know that tests #1–6 also exist, what the planner thought last week, or what the user originally asked. Giving it less context produces sharper output and saves tokens.
2. **Model tiering.** The orchestrator's role (state tracking, dispatching) is cheap. Test running is cheap. Plan writing is expensive. Letting each subagent declare its own model means you only pay Opus prices when you need Opus reasoning.

Skills "chaining" was considered and rejected. Skills are contextual instruction sets, not runtime processes. Chaining them would mean reading more instructions in the same context — which is exactly the problem we're trying to avoid.

## Model tier assignments

| Subagent | Model | Reason |
|---|---|---|
| Orchestrator (the skill) | inherits session model | Lightweight state machine, no heavy lifting |
| `flow-pm` | Sonnet | First responder. Defining a feature + acceptance criteria is judgment work but bounded — Sonnet is sufficient and the architect handles the heavy reasoning for L. |
| `flow-triager` | Haiku | Pattern-match against rubric, classify, parse files. Cheap. |
| `flow-architect` | Opus | L-only. Architectural shape decisions are load-bearing for the planner; deep judgment about subsystems and integration warrants Opus. Skipped entirely for S/M. |
| `flow-planner` | Opus + ultrathink keyword | Highest-leverage call in the pipeline. A bad plan poisons every later phase. |
| `flow-test-author` | Sonnet | Competent test writing. Doesn't need Opus. Self-runs to prove failure. |
| `flow-implementer` | Opus | Hardest reasoning task. Worth the cost. |
| `flow-test-runner` | Haiku | Pure command execution and result parsing. No reasoning needed. |
| `flow-failure-triager` | Sonnet | Classifying a failure into one of three buckets is judgment work, but bounded. |
| `flow-security-reviewer` | Sonnet | Diff-scoped vulnerability review. Pattern recognition over a small surface, with judgment calls about severity and scope. Sonnet is sufficient; Opus would be overkill for a bounded checklist task. |
| `flow-reporter` | Haiku | Templating from structured state. |

The PM-then-architect split is intentional. The PM grounds the work in user-facing terms (what's being built, when it's done) regardless of size — the cheapest tier that can do that job well. The architect runs only when size is L, where architectural shape decisions warrant Opus and would otherwise dominate the planner's already-Opus call. For S/M tasks, the architect would be overkill and is skipped.

## Why merge test-author and test-runner for the cold path, but split for the hot path

**Cold path (Phase 4 — initial test writing):** the test-author writes tests AND runs them itself, proves they fail for the right reason, then returns. One subagent, Sonnet.

**Hot path (Phase 5/6 — implementation):** test-runner is its own dedicated Haiku subagent that the orchestrator dispatches separately from the implementer.

Why the asymmetry?

The cold path runs once per batch — writing tests is the work, running them is the validation. Splitting that into two subagents would add round-trips through the orchestrator for something the test-author should handle itself. Merge wins.

The hot path runs many times per cycle — implementer dispatches, test-runner dispatches, possibly retry, possibly cascade detection. The implementer is Opus. You do not want Opus thinking tokens spent on "did the tests pass?" That's pure command execution. Haiku nails it for a fraction of the cost. Split wins.

## Anti-loop guards

The biggest source of token waste in AI-assisted TDD is unconscious test/fix looping: Claude regenerates code, runs tests, gets failures, regenerates again, never actually reads the error output. Three attempts later, 50k tokens are gone.

The guards layer multiple brakes:

| Layer | Cap | Purpose |
|---|---|---|
| Per-test fix attempts | 3 | Hard stop on individual flailing |
| Implementer re-dispatches per batch | 3 | Hard stop on whole-batch flailing |
| Full-suite runs in Phase 6 | 3 | Hard stop on suite-level flailing |
| Total test/fix cycles | 5 | Catch slow-burn waste |
| Security review cycles in Phase 7 | 3 | Bound the review/fix loop; surface persistent findings instead of looping silently |
| Cascade detection | 3+ failures with same root | Fix root only, not each downstream symptom |
| Diagnose-before-retry | always | Force articulation of root cause before any retry |
| No silent test mutations | always | Every test edit logged with reason |

Numbers were chosen for a typical M-size feature. They are intentionally tight — getting hit by a guard means escalating to the user, which is how Flow surfaces problems early instead of letting them compound.

If guards trigger too aggressively for your workflow, raise them in the orchestrator's SKILL.md. But before you do, consider: a guard trip means *something is wrong*. The fix is usually upstream (better plan, better tests), not "give the loop more attempts."

## The plan-approval gate

Phase 3 is the only mid-pipeline gate where flow stops and waits for the user explicitly to approve a structured artifact. (Phases 0 and 2 also stop for user input, but only when the PM or architect surfaces questions — and only to gather answers, not to approve an artifact.) The three response paths at the plan gate exist because real plan reviews aren't binary:

1. **Explicit proceed** ("approve", "go", "lgtm", etc.) — continue
2. **Question or change request** — revise, re-present, back to gate
3. **Change-and-proceed** ("rename X to Y and proceed") — revise silently, continue

The third path was contentious. It means the orchestrator updates the plan and moves on without showing you the revised version. The risk: a plan you didn't fully re-read. The benefit: faster iteration on small tweaks. The skill is conservative — when in doubt between "questions" and "change-and-proceed," it defaults to re-presenting.

## Plan format

Plans are produced as structured markdown so downstream subagents can extract slices. The planner outputs:

1. **Goal** — one sentence
2. **Approach** — 1–3 architecture bullets
3. **Batches** — ordered list (each: name, files, test strategy, impl notes)
4. **TDD scaling choice** — `all-upfront` / `batched` / `iterative`
5. **Risks & assumptions**
6. **Rollback** (only when destructive ops are involved)

**Code is not in the plan by default.** Plans describe architecture, not implementations. Carlos's design preference, but it also serves token discipline — Phase 3 review is faster when the plan is high-level.

The exception: if the planner identifies a piece of *load-bearing core logic* (subtle state machine, complex contract), it includes a brief sketch tagged `[core logic preview]` so the user can sanity-check the shape before implementation. Use sparingly.

## Why security review is its own phase, after tests pass

Tests prove the code does what was specified. They generally do not prove the code is *safe* — a SQL injection or an unauthenticated route can sail through a green suite. Security review is a separate concern with separate failure modes, so it gets its own phase rather than being piled into the implementer or the test-author.

Two design choices worth calling out:

1. **Scope is the diff, not the codebase.** The reviewer looks at uncommitted changes only. Cataloguing pre-existing issues outside the changed lines would scope-creep every `/flow` run into a full audit. Out of scope.
2. **Findings loop through the implementer, then the test runner, then back to the reviewer.** Tests re-run after every fix because security patches frequently change validation logic, query shape, or response payloads — exactly the surfaces the existing tests cover. Skipping the test run would let the reviewer happily mark a vulnerability resolved while quietly breaking a regression test. The cycle cap (3) bounds this loop the same way the test-fix caps bound Phase 5/6.

Sonnet is the right tier for this work. Severity calls and "is this issue introduced by the diff" judgments are bounded pattern-recognition; the heavy lifting (writing the actual fix) lives in the Opus implementer call that the reviewer's findings dispatch into.

## CLAUDE.md handling

`CLAUDE.md` files are project memory in Claude Code. They auto-load into the orchestrator's session at startup. Flow uses them in two ways:

- **Triager extracts slices** — at Phase 1, the triager pulls relevant pieces (conventions, test rules, no-gos) from `CLAUDE.md` files
- **Orchestrator passes slices to subagents** — only the relevant slice ships with each dispatch, not the whole file

`CLAUDE.md` *can* override:
- Test framework, runner, fixtures
- File layout and naming
- Test commands and coverage targets
- Coding style conventions

`CLAUDE.md` *cannot* override:
- Anti-loop guards
- Hard guards (no destructive ops, no auto-commits, no secrets handling)
- Phase structure
- Plan approval gate

The non-overridable list is non-negotiable by design. If a project's `CLAUDE.md` could turn off the anti-loop guards, it could be exploited (or just misconfigured) into a token-burning workflow. The guards exist precisely to prevent that.

## What was deliberately left out

Things considered and rejected for v0.1:

- **Auto-routing to project-defined agents** (frontend-agent, api-agent, etc.). Discovery is messy, contracts mismatch with TDD pipeline expectations, and project agents may have their own loop behavior that bypasses Flow's guards. Opt-in only via user instruction.
- **Token cost tracking and stop-on-cost triggers**. Token counting across subagent calls is awkward. Cycle counts are a usable proxy. Revisit if real-use shows cycle counts aren't catching slow-burn cases.
- **Parallel implementer dispatches**. Plans with independent batches could theoretically be implemented in parallel, but coordinating shared types and contracts across parallel subagents is hard. Sequential for now.
- **Extended thinking on the implementer**. The planner already did the reasoning; the implementer's job is to execute the plan, not re-think it.
- **Project-level subagent overrides**. Users could put their own `flow-test-author.md` in `.claude/agents/` to override the default. Not specified or supported in v0.1.
- **Trivial bypass mode**. `/flow` is for non-trivial features. Trivial work doesn't need this skill. If you find yourself wanting bypass, you're using `/flow` for the wrong thing.

## Versioning philosophy

Flow follows semver. The interpretation:

- **Major** — breaks installations, requires user action (e.g., new required field, removed subagent)
- **Minor** — adds capability without breaking existing behavior (new subagent, new optional config)
- **Patch** — bug fixes, prompt clarifications, model ID updates

Model IDs in subagent frontmatter (e.g., `claude-opus-4-7`) age as new models ship. We aim to keep these current, but if you want auto-tracking, change to aliases (`opus`, `sonnet`, `haiku`) — those follow the latest release.
