# Changelog

All notable changes to Flow are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-09-02

Flow runs were taking hours on features that warranted far less. Instrumenting real runs showed the cost was not the retry loops — anti-loop guards barely fired — but **duplicated codebase exploration, paid twice per batch, across too many batches**. On a measured 10-batch run, the test-author and implementer were 82% of all subagent wall-clock; roughly 70% of a test-author dispatch and 50% of an implementer dispatch elapsed before either wrote a line, and 46% of the files the implementer read had already been read by the test-author minutes earlier in a context that was then discarded. This release attacks that directly.

### Added
- **`flow-batch-builder` (Opus) — merged red-green batch agent.** One agent per batch now writes the failing tests, proves them red, hash-locks them, and writes the code to green, all in one context and one exploration pass. Phases 4 and 5 collapse into a single Phase 4.
- **Hash-locked tests.** The builder hashes every test file at the moment it is proven failing and reports the digests; the Haiku test-runner independently re-verifies them after the code is written, and again at the full suite. A mismatch is a guard trip (cap 0) — the run stops and names the files. This preserves the invariant the old two-agent split existed to protect (the agent that makes tests pass cannot weaken them) using a cheap external check instead of an expensive context boundary. The only sanctioned route to changing a locked test is a failure-triager Case 1 ruling, which returns as an explicit `amend_tests` re-dispatch that re-proves red, re-freezes, and is logged in `## Modified tests`.
- **`MAP.md` — a shared codebase map, written once at triage.** Commands (including single-file test invocation), test and source conventions, fixture and double patterns, key paths for the task, CLAUDE.md slices, and gotchas. Downstream agents are instructed to trust it rather than re-derive conventions. New triager-owned artifact; the task directory now holds seven files.
- **Parallel batch execution.** The planner emits a `## Batch dependency graph`; the orchestrator dispatches every ready batch concurrently, up to 3 at a time. Any file overlap between two batches forces serial execution regardless of the declared graph, so a wrong declaration costs parallelism, never correctness. Supersedes the "parallel implementer dispatches" entry under *What was deliberately left out*.
- **Batch budget, enforced by size tier.** S: 1-2 batches, M: 2-4, L: 4-6. The planner returns `status: over_budget` rather than over-splitting, which surfaces "this task is bigger than its triage tier" as a user decision instead of a silent cost. Observed pre-0.6 plans ran 5-7 batches on M and 10 on one L.
- Anti-loop guards: **test-lock violations (cap 0)** and **concurrent batch builders (cap 3)**.

### Changed
- **Phases renumbered.** Security review 6 → 5, full suite 7 → 6, handoff 8 → 7. Test-writing and implementation are now one phase (4).
- **`flow-triager` promoted to Sonnet** (`claude-sonnet-5`, was `claude-haiku-4-5-20251001`). It now writes MAP.md, and a map nobody trusts is worse than no map — agents pay to read it *and* re-explore. This is the one place where paying more once saves considerably more later; rationale updated in the model tier table.
- **Agents read narrow slices instead of the whole task directory.** The batch builder reads only MAP.md and ARCHITECT.md from disk; the orchestrator assembles a batch brief (that batch's files, test strategy, notes, and the verbatim AC text) and passes it inline. No subagent reads STATE.md any more — it is the orchestrator's ledger, not a reading assignment. The architect, planner, and security reviewer read MAP.md in place of STATE.md. On the measured run those four artifacts totalled 82KB (~20k tokens) re-read by each of ~23 dispatches, with builder contexts peaking near 200k tokens and 3-6 minute pauses between tool calls.
- **`flow-implementer` is now off-path only** — security findings (`mode: security`) and failure-triager Case 3 regressions (`mode: regression`). It no longer builds batches.
- **`flow-test-author` is now off-path only** — Phase 6 coverage gaps against code that already exists. It may report a gap as `not_covered` with a structural reason (composition roots, thin SDK wrappers, integration-gated code) rather than writing tests that assert nothing.
- Counter `implementer_redispatches_per_batch` renamed to `builder_redispatches_per_batch`; `test_lock_violations` added to the STATE.md template.

## [Unreleased]

### Added
- **`/flow-lite` skill.** A lightweight clarify-then-do workflow for small or non-development tasks. Four steps: (1) if the prompt mentions "read files" or an equivalent, ground in the relevant code first; (2) ask up to 8 sharp clarifying questions (`AskUserQuestion` preferred for discrete choices) and end the turn; (3) do the work directly — explicitly NOT TDD; (4) for dev tasks with existing related test files, update the tests *after* the change to cover the new behavior, run them, and fix any regressions (deciding per-failure whether the code or the test was wrong). No subagents, no batches, no security gate. Hard guards mirror `/flow`. Installer now copies every skill directory under `skills/`, so both `/flow` and `/flow-lite` install with one `./install.sh` run.

### Changed
- **Model tiers bumped to current releases.** Opus subagents (`flow-architect`, `flow-planner`, `flow-implementer`) now target `claude-opus-4-8` (was `claude-opus-4-7`); Sonnet subagents (`flow-pm`, `flow-test-author`, `flow-failure-triager`, `flow-security-reviewer`) now target `claude-sonnet-5` (was `claude-sonnet-4-6`). Haiku subagents (`flow-triager`, `flow-test-runner`, `flow-reporter`) stay on `claude-haiku-4-5-20251001`, still the latest Haiku. Model-ID example in `docs/architecture.md` updated to match.

## [0.5.1] - 2026-05-17

### Fixed
- **Plan-approval gate now hard-stops the orchestrator turn.** Phase 3 previously said "Present PLAN.md. Route Carlos's response." with no explicit pause directive, so the orchestrator could walk straight from Phase 3 through Phases 4–7 in a single turn (observed in the wild under Claude Code's auto-accept-edits mode). The gate now explicitly instructs the orchestrator to end its turn after presenting the plan and resume only on the user's next message — not overridable by auto-accept, `/loop`, or project `CLAUDE.md`. Mirrored in `SKILL.md`, `README.md`, and `docs/architecture.md` per the guard-duplication rule.

## [0.5.0] - 2026-05-15

### Added
- **Per-task artifact directory.** Every `/flow` run now creates `~/.flow/tasks/{project_folder}/{unix_ts}/` and writes six artifacts there: `TASK.md` (PM), `ARCHITECT.md` (architect), `PLAN.md` (planner), `SECURITY.md` (security reviewer), `REPORT.md` (reporter), `STATE.md` (orchestrator). Subagents resolve their inputs by reading files from disk instead of receiving spec/architecture/plan content in-band. The user may hand-edit any file between phases — re-dispatched agents re-read on entry. Strict owner-only writes (two orchestrator exceptions: STATE.md throughout, and AC checkbox ticking in TASK.md).
- **Acceptance criteria as markdown checkboxes.** TASK.md AC are `- [ ]` items; the planner now produces an explicit `## AC → Batch mapping` section in PLAN.md, and the orchestrator ticks the corresponding boxes as each Phase 5 batch turns green. Final affirmation at Phase 7.
- **Architect conflict channel.** The architect can now return `status: conflict` when one or more AC in TASK.md cannot be satisfied by any sensible architecture. The orchestrator surfaces the conflict to the user, rewrites TASK.md per the user's direction, and re-dispatches the architect.
- Anti-loop guard: **Architect/TASK conflict cycles (cap 3)**. Bounds the architect↔TASK.md rewrite loop; on trip, the orchestrator stops and asks the user how to proceed.

### Changed
- **Architect runs on every task.** Previously L-only; now S/M/L. Calibrates depth to triage size (quick sweep on S, deeper read on L). Rationale: by the time you've reached for `/flow`, the work isn't trivial enough to skip a written architectural shape, and a uniform contract simplifies the planner's input. Cost: Opus call on every flow.
- **`Write` tool added** to `flow-pm`, `flow-architect`, `flow-planner`, `flow-security-reviewer`, `flow-reporter` frontmatter. Each writes only its owned artifact.
- **Subagent prompts rewritten** to read files from the task directory instead of receiving inputs in-band. Returns are now minimal status envelopes (`status: spec_written`, `status: plan_written`, etc.) plus the artifact path.
- **Status-line examples** updated across `SKILL.md`, `README.md`, `docs/workflow.md`, `docs/architecture.md` for the new artifact naming (`TASK.md ready`, `ARCHITECT.md ready`, `PLAN.md ready`, `conflict: <one-liner>`).

## [0.4.0] - 2026-05-12

### Changed
- **Security review moved before the full suite.** New phase ordering: `... 5=Implement, 6=Security review, 7=Full suite, 8=Handoff` (previously `6=Full suite, 7=Security review`). The full suite is the single most expensive call in the pipeline; running it before the reviewer meant burning a full pass every time security had findings, since the suite has to re-run after any code change. The reviewer now runs first and the full suite runs once, at the end, as the final gate.
- **No test run inside the security loop.** When the reviewer surfaces findings, the orchestrator dispatches the implementer to fix them and then re-dispatches the reviewer — no test-runner invocation between fix and re-review. The Phase 7 full suite is the gate; if a security fix breaks a test, the failure-triager picks it up there. This is the change that actually realizes the token savings — keeping a test run inside the loop would defeat the reorder. Trade-off: regressions caused by security patches surface one phase later than before.
- **Anti-loop guard labels renumbered.** "Full-suite runs in Phase 6 (cap 3)" → Phase 7; "Security review cycles in Phase 7 (cap 3)" → Phase 6. Caps and behavior unchanged.
- **Status-line examples** and all phase cross-references in `SKILL.md`, `README.md`, `docs/workflow.md`, and `docs/architecture.md` updated to the new ordering.

### Fixed
- `flow-reporter` frontmatter and prompt body said "Phase 7"; was stale from the 0.3.0 renumber. Now correctly says Phase 8.

## [0.3.0] - 2026-04-28

### Added
- `flow-security-reviewer` (Sonnet) — new Phase 7 subagent. Reviews the uncommitted diff for security issues (injection, XSS, auth/authz gaps including IDOR, secrets, frontend env leakage, CSRF, SSRF, path traversal, open redirect, insecure deserialization, mass assignment, weak crypto, CORS, sensitive logging) and returns a severity-tagged findings list. Scope is the diff, not the codebase.
- **Phase 7 — Security review.** Runs after Phase 6 is green. Findings loop back through the implementer; the test-runner re-runs the full suite after each fix; the reviewer re-runs to confirm resolution. Loops until clean or the security-cycle cap (3) trips.
- Anti-loop guard: **Security review cycles in Phase 7 (cap 3)**. On trip, the orchestrator surfaces open findings with what's been tried and waits for direction.
- Reporter now emits a "Security findings resolved" section when applicable.

### Changed
- **Phases renumbered.** Handoff moves from Phase 7 to Phase 8 to make room for the security-review phase. New layout: `0=PM, 1=Triage, 2=Architect (L only), 3=Plan, 4=Tests, 5=Implement, 6=Full suite, 7=Security review, 8=Handoff`. Status-line examples and cross-phase references updated accordingly.

## [0.2.0] - 2026-04-28

### Added
- `flow-pm` (Sonnet) — Phase 0 first responder. Defines the feature and acceptance criteria for every task; asks 0–15 clarifying questions if needed. Produces a structured spec (feature, acceptance_criteria, out_of_scope, open_assumptions) consumed by triage, architect, and planner.
- `flow-architect` (Opus) — Phase 2, runs **only when triage classifies size as L**. Produces a high-level architectural overview (subsystems, data flow, integration points, trade-offs); asks 0–15 high-level questions if needed.

### Changed
- **Phases renumbered.** New layout: `0=PM, 1=Triage, 2=Architect (L only), 3=Plan, 4=Tests, 5=Implement, 6=Full suite, 7=Handoff`. All anti-loop guard references and status-line examples updated accordingly.
- **Planner input shape.** `flow-planner` now receives the PM spec and (for L tasks) the architect overview, instead of a raw clarification Q&A transcript.
- **Triager input.** `flow-triager` now also receives the PM spec.

### Removed
- `flow-clarifier-sonnet` and `flow-clarifier-opus` — replaced by `flow-pm` (universal first responder) plus `flow-architect` (L-only architectural pass). Clarification Q&A is now owned by the PM (always) and the architect (when present), and the artifact each produces is consumed directly by the planner.

## [0.1.0] - 2026-04-28

Initial release.

### Added
- `/flow` orchestrator skill
- Eight tiered subagents: triager, clarifier (Sonnet/Opus), planner, test-author, implementer, test-runner, failure-triager, reporter
- Anti-loop guards: per-test attempt cap, implementer re-dispatch cap, full-suite run cap, total cycle circuit breaker, cascade detection
- Plan-approval gate with three response paths (proceed / revise-and-represent / revise-and-proceed)
- CLAUDE.md slice handling per subagent dispatch
- Hard guards: no destructive operations, no auto-commits, no secrets in code or output
- 90% line coverage requirement on touched files

[Unreleased]: https://github.com/TODO-username/flow/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/TODO-username/flow/releases/tag/v0.5.1
[0.5.0]: https://github.com/TODO-username/flow/releases/tag/v0.5.0
[0.4.0]: https://github.com/TODO-username/flow/releases/tag/v0.4.0
[0.3.0]: https://github.com/TODO-username/flow/releases/tag/v0.3.0
[0.2.0]: https://github.com/TODO-username/flow/releases/tag/v0.2.0
[0.1.0]: https://github.com/TODO-username/flow/releases/tag/v0.1.0
