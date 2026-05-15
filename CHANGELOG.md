# Changelog

All notable changes to Flow are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-05-15

### Added
- **Per-task artifact directory.** Every `/flow` run now creates `~/.claude/tasks/{project_folder}/{unix_ts}/` and writes six artifacts there: `TASK.md` (PM), `ARCHITECT.md` (architect), `PLAN.md` (planner), `SECURITY.md` (security reviewer), `REPORT.md` (reporter), `STATE.md` (orchestrator). Subagents resolve their inputs by reading files from disk instead of receiving spec/architecture/plan content in-band. The user may hand-edit any file between phases — re-dispatched agents re-read on entry. Strict owner-only writes (two orchestrator exceptions: STATE.md throughout, and AC checkbox ticking in TASK.md).
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

[Unreleased]: https://github.com/TODO-username/flow/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/TODO-username/flow/releases/tag/v0.5.0
[0.4.0]: https://github.com/TODO-username/flow/releases/tag/v0.4.0
[0.3.0]: https://github.com/TODO-username/flow/releases/tag/v0.3.0
[0.2.0]: https://github.com/TODO-username/flow/releases/tag/v0.2.0
[0.1.0]: https://github.com/TODO-username/flow/releases/tag/v0.1.0
