# pr

> Write a PR body that's fast to review. [繁體中文](README.zh-TW.md)

## Quick start

```bash
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install pr@scl-claude-plugins
```

The `pr` skill triggers when Claude is writing a pull-request description — for example when you ask "write the PR body". You can also call it explicitly with `/pr:pr`. `/commit-commands:commit-push-pr` does not load it: that command has Claude do everything in one message with no other tools, and writes its own body from the diff.

## What the body looks like

```markdown
## Summary
<diagram, diff-sketch, or tree>

## Evidence
- **Before:** <screenshot/output/failing test run>
  **After:** <screenshot/output/passing test run>

## Merge Danger
**Door:** <one-way or two-way>
**Blast Radius:** <one-word description>
```

- **Summary** — the smallest view that makes the key point clear: pseudocode, a call tree, a component or file tree, a Mermaid diagram, or a `diff` sketch of the shape that changes. Each visual sits next to the short text it supports.
- **Evidence** — before and after. Screenshots rank highest for visual changes; test runs and console output come next.
- **Merge Danger** — whether the change is a one-way door (destructive or hard to reverse) or a two-way door (cheap to roll back), and how far its effects reach.

Prose stays brief. If the repository has a `GLOSSARY.md`, the body uses its terms.

Rules added on top of the reference:

- **The repo's language wins** (1.2.0). The body is written in the language of the repository's existing PRs (looked up with `gh pr list`, or what you tell it); when that cannot be found, or there are none, it is written in Traditional Chinese. Section headings, field names such as `**Door:**`, file names, commands and code stay as they are.
- **Your repo's PR template wins** (1.1.0). If the repository has a pull request template, its headings stay and the three sections' guidance is applied inside them.
- **Evidence is observed, not written** (1.1.0, widened in 1.2.0). Only output from commands run in the session, CI results, or command output you paste, quoted verbatim with its source; a result you only describe in words ("tests pass") is not evidence, and the body then says `Not verified: <reason>` (`未驗證：<原因>` in a Chinese body).
- **Screenshots** (1.1.0). `gh` cannot upload images, so the body gets a `**Screenshot pending:**` placeholder and you drag the image in on GitHub.

## What it does not do

It only shapes the body. It does not commit, push, or pick reviewers, and it opens or updates a PR only when you ask. The skill tells Claude to write the body to a file outside the repository; asked for a draft, it hands you the file's path, and asked to open or update the PR, it passes the file with `gh pr create --body-file <file>` (or `gh pr edit <number> --body-file <file>`).

## Files

- `skills/pr/SKILL.md` — the version Claude loads, in Traditional Chinese.
- `skills/pr/SKILL.en.md` — an English reference copy the model does not read. Change both together.
- `evals/` — behaviour regression suite, below.

## Behaviour checks (eval)

`evals/` holds seven cases, each run with and without the plugin so the suite measures uplift (Δ): a result stated only in words not treated as evidence, no fabricated evidence, the repository's template kept, Traditional Chinese when there is no precedent, an English precedent followed, pasted output quoted with its source and a merge-risk call, and one should-not-fire case (a commit message). From the plugin root:

```bash
claude plugin eval . --ablation with-without --model sonnet --judge-model opus --no-publish
```

The judge must not be the agent's model. Results go to `evals/results/`, which is not committed. The delivery section (`gh pr create` / `edit`) has no case: testing it would let the agent write to GitHub, and `gh` cannot be mocked.

## Origin and credits

Ported from a standalone `pr` skill. 1.0.0 changed one line (the `GLOSSARY.md` instruction applies when the repository has one); 1.1.0 added the three rules marked 1.1.0 above and a closing "Delivering the body" section in the skill (described under "What it does not do"); 1.2.0 added the language rule and rewrote the skill in Traditional Chinese, keeping the English text as `SKILL.en.md`. The skill's Codex-only `agents/openai.yaml` interface file was not carried over, since Claude Code does not read it. The Summary section's menu of visuals comes from Dex Horthy's `show-me` skill (Humanlayer) — see [`skills/pr/CREDITS.md`](skills/pr/CREDITS.md).
