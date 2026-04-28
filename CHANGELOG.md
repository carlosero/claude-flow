# Changelog

All notable changes to Flow are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/TODO-username/flow/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/TODO-username/flow/releases/tag/v0.1.0
