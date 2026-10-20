# Changelog

All notable changes to the `pr` plugin will be documented in this file.

## [1.2.0] - 2026-10-20

### Added

- **Language rule.** The body follows the language of the repository's existing PRs (checked with `gh pr list --state all --limit 5 --json title,body`, or what the user says); when that cannot be checked or there are none, it is written in Traditional Chinese. Section headings, `**Door:**` / `**Blast Radius:**`, `one-way` / `two-way`, file names, flags, commands, code and output stay as they are, and `Not verified:` becomes `未驗證：` in a Chinese body.
- **Eval suite** (`evals/`, seven cases, with/without ablation): a result stated only in words is not treated as evidence, no fabricated evidence, repository template kept, Traditional Chinese without a precedent, English precedent followed, pasted output quoted with its source and a merge-risk call, and a should-not-fire commit-message case. Before the language rule, `04-lang-no-precedent` scored 0.00 in both arms; after it, 1.00 with vs 0.00 without. Final run over three runs per case (sonnet agent, opus judge): every case 1.00 with the plugin, mean Δ +0.32, $3.79; `01-verbal-claim-only` 1.00 vs 0.53 (without the plugin, two of three runs presented "tests pass" as verified). The delivery section has no case: testing it would let the agent write to GitHub.
- `README.zh-TW.md`.

### Changed

- **`SKILL.md` is now in Traditional Chinese**; the English text is kept as `skills/pr/SKILL.en.md` (no frontmatter, not loaded by Claude). The frontmatter `description` stays `"Use when writing a PR body."` — changing the trigger wording is left until an eval can measure it.
- **Evidence sources include output the user pasted.** 1.1.0 allowed only output run in the session or CI results, so a body quoting the test output a user pasted broke the rule even though it is not fabricated (found by codex while reviewing the `06-evidence-given` grader). Pasted command output is now accepted when quoted verbatim, not completed, and labelled with its source (for example "author's local `npm test`"); a result the user only describes in words ("tests all pass") is still not evidence and gets `Not verified` / `未驗證`, which the new `01-verbal-claim-only` case guards.

## [1.1.0] - 2026-10-20

### Added

These four rules go beyond the ported reference; each closes a way the 1.0.0 skill could produce a wrong or lost body.

- **Delivering the body** — a new closing section: write the body to a file outside the repository; only when the user asked to open or update the PR, pass it with `gh pr create --body-file`, or `gh pr edit <number> --body-file` for an existing PR, and otherwise hand over the file's path; never inline with `--body`, where the shell runs backticks and expands `$`. In 1.0.0 this route lived only in the README, which the model does not read when the skill loads.
- **Evidence must be observed** — only output from commands run in this session or CI results for the branch, quoted; when there is none, `Not verified: <reason>` instead of a before/after.
- **Repository PR templates win** — when the repo has `pull_request_template.md` (root, `docs/`, `.github/`) or a `PULL_REQUEST_TEMPLATE/` directory, its headings and order are kept and this guidance is applied inside them.
- **Screenshots** — `gh` cannot upload images, so a needed screenshot becomes a visible `**Screenshot pending:**` placeholder and the user is asked to drag the image in on GitHub.

## [1.0.0] - 2026-10-20

### Added

- Initial release: the `pr` skill, a PR-body template with three sections — Summary (the smallest visual that makes the point: pseudocode, call tree, component or file tree, Mermaid, or a diff sketch), Evidence (before / after), and Merge Danger (one-way vs two-way door, blast radius). Ported from a standalone `pr` skill; the `GLOSSARY.md` instruction now applies only when the repository has one, and the Codex-only `agents/openai.yaml` was not carried over. Summary visuals credited to Dex Horthy's `show-me` skill in `skills/pr/CREDITS.md`.
