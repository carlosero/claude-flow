# Publishing checklist

Things to do before pushing this repo public. Delete this file once you're done with it.

## Required customization

- [ ] **`.claude-plugin/plugin.json`** — replace all `TODO` placeholders (author name, email, GitHub URLs)
- [ ] **`LICENSE`** — replace `TODO: your name` in the copyright line with your actual name
- [ ] **`README.md`** — replace all `TODO-username` references with your GitHub username
- [ ] **`CHANGELOG.md`** — same `TODO-username` replacements in the link references at the bottom

Quick way to find them all:

```bash
grep -rn "TODO" .
```

## Strip personalization from the skill and agents

The current `skills/flow/SKILL.md` and `agents/flow-*.md` files mention "Carlos" by name in several places. Before publishing:

- [ ] Search for "Carlos" across all files: `grep -rn -i "carlos" skills/ agents/`
- [ ] Replace each occurrence with "the user" or remove the personalization
- [ ] Re-read the orchestrator's tone notes — anywhere it says "Carlos moves fast" or similar should become "users prefer dense, skimmable output" or be removed

Suggested neutral replacements:

| Original | Replacement |
|---|---|
| "Carlos's structured development workflow" | "A structured development workflow" |
| "Carlos moves fast" | "Users prefer dense, skimmable output" |
| "Carlos commits manually" | "The user commits manually" |
| "Carlos validates manually" | "The user validates manually" |
| "Carlos can override" | "The user can override" |
| "Carlos doesn't want to see code" | "Plans omit code by default" |

## Optional but recommended

- [ ] **Run Flow on 3–5 real features** before pushing public. The first published version should be one that survived real use, not an untested draft.
- [ ] **Run a token comparison** against Superpowers (or similar) on one representative task. Add real numbers to the README's "Why this exists" section. Without real numbers, the token-efficiency claim is marketing; with them, it's a benchmark.
- [ ] **Add a `CONTRIBUTING.md`** if you want to invite community PRs. A short one is fine.
- [ ] **Add a `.gitignore`** appropriate for what you'll be committing — at minimum `.DS_Store` and editor swap files.
- [ ] **Add a GitHub issue template** under `.github/ISSUE_TEMPLATE/` if you want to standardize bug reports.
- [ ] **Add a screenshot or asciinema recording** of `/flow` in action — README adoption rates roughly double with one good visual.

## Repo hygiene before first push

- [ ] Verify the directory structure matches what's documented:
  ```
  flow/
  ├── .claude-plugin/plugin.json
  ├── README.md
  ├── LICENSE
  ├── CHANGELOG.md
  ├── docs/
  │   ├── architecture.md
  │   └── workflow.md
  ├── skills/flow/SKILL.md
  └── agents/flow-*.md      (8 files)
  ```
- [ ] Delete this `PUBLISHING_TODO.md` file
- [ ] Commit, tag `v0.1.0`, push

## Marketplace submission (optional)

If you want the plugin listed on Anthropic's canonical marketplace:

- [ ] Submit at https://claude.ai/settings/plugins/submit (or platform.claude.com/plugins/submit)
- [ ] Community marketplaces (like ClaudePluginHub) auto-discover from GitHub once you push — no submission needed

## Post-publish

- [ ] Watch for issues in the first week — that's when the most useful real-use feedback arrives
- [ ] Tag patch releases (`v0.1.1`, etc.) for prompt clarifications and small fixes
- [ ] Save `v0.2.0` for any structural change (new subagent, removed phase, etc.)
