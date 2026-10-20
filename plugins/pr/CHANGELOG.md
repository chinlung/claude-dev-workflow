# Changelog

All notable changes to the `pr` plugin will be documented in this file.

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
