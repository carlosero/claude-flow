# Changelog

All notable changes to Flow are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/TODO-username/flow/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/TODO-username/flow/releases/tag/v0.2.0
[0.1.0]: https://github.com/TODO-username/flow/releases/tag/v0.1.0
