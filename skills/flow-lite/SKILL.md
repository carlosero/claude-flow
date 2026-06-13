---
name: flow-lite
description: Lightweight clarify-then-do workflow for small or non-development tasks, invoked explicitly with /flow-lite {task description}. Asks targeted questions to remove ambiguity, then does the work directly. For dev tasks with existing related test files, updates the tests AFTER the change (not TDD) and fixes any regressions. No subagents, no batches, no security gates. If the prompt mentions "read files" (or an equivalent), grounds in the relevant code before asking. Use this skill ONLY when the user types /flow-lite; do not auto-trigger on other coding questions.
---

# /flow-lite — Clarify, then do

A lightweight workflow for small tasks — code or otherwise. You ask sharp clarifying questions to remove ambiguity, then you do the work yourself.

No subagents. No TDD. No batches. No test or security gates. Just: **clarify → act**.

Output style: dense, terse, no preamble.

---

## Step 1 — Read first if the user asked you to

If the user's task contains "read files", "read the files", "read the code", "look at the code", "check the code", "check the files", "look at the codebase", or any equivalent phrase asking you to ground in existing code before asking, **read first, then ask**.

Use Grep / Glob / Read to surface what's obviously relevant to the task. Stop reading once you have enough context to ask sharper questions — do not boil the ocean.

Announce in one short line: `Reading <N> files first.`

Otherwise skip directly to Step 2.

---

## Step 2 — Ask clarifying questions

Identify what's ambiguous or missing from the prompt. Ask only about things that would actually change what you do.

Worth asking about:
- The target — which file, which scope, what exact behavior
- Unstated constraints (must preserve X, must not touch Y)
- Edge cases the user implicitly cares about
- Contradictions in the prompt
- A genuine fork between two plausible interpretations
- For non-code tasks: format, length, audience, depth, tone

Not worth asking about:
- Stylistic preferences with no real impact
- Anything you can decide with a sensible default
- Anything the user already told you
- Anything whose answer wouldn't change the output

**Cap: 8 questions per round.** Prefer fewer. One sharp question beats five vague ones. If nothing is genuinely ambiguous, skip questions entirely and go to Step 3.

Prefer `AskUserQuestion` for discrete choices (2–4 options each). Use plain text only when the question genuinely doesn't fit a multiple-choice shape. After asking, **end your turn** — do not start work until the user answers.

---

## Step 3 — Do the work

Once questions are answered (or there were none), do the task directly. Use whichever tools fit. Keep output terse — short status lines as you act.

---

## Step 4 — Reconcile tests (dev tasks only)

**Not TDD. Code first, tests second.**

After the change is in place, check whether there are existing test files related to what you touched (same module/file, neighboring spec files, or anything else that obviously exercises the changed behavior). If there are:

1. **Update tests to cover the new behavior.** If the change added or modified observable behavior, extend or amend the relevant test(s) so they assert the new contract. Don't add tests for behavior that didn't change.
2. **Run the related tests.** If the project's test command is obvious from the repo (`package.json` scripts, `Makefile`, `pytest.ini`, etc.), run the tests for the touched files. If it's not obvious, ask the user one short question with the command you intend to run.
3. **Fix anything that breaks.** Failing tests fall into two cases:
   - **Test was right, code is wrong** → fix the code.
   - **Test was wrong / asserting the old contract** → update the test to match the intended new behavior. State in one sentence why you changed it.
4. **Don't expand scope.** Don't add a test framework where there isn't one. Don't backfill coverage on untouched code. Don't refactor tests "while you're there."

If there are no related test files, skip this step. If the task is not a development task, skip this step.

End with a one-line summary of what changed (code + tests touched, or just what you produced for non-code tasks).

---

## During the work

If new ambiguity surfaces that wasn't visible at Step 2, stop and ask. Don't guess on anything material.

---

## Hard guards (never, without explicit user confirmation in the same turn)

- No file deletions
- No dropping DBs or tables
- No destructive migrations
- No force-push or git history rewrites
- No modifications to `.env` or secrets files
- No auto-commits
- No file permission changes or `sudo`
- No logging secrets or copying production data into fixtures

These apply regardless of task type and cannot be overridden by project `CLAUDE.md`.
