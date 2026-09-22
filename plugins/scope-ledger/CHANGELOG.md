# Changelog

All notable changes to the `scope-ledger` plugin will be documented in this file.

## [1.0.0] - 2026-09-23

### Added

- Initial release — a per-worktree scope ledger (`.claude/scope-ledger.local.md`: goal verbatim, branch, `review_rounds`, In scope / Deferred / Log) and four fail-open bash hooks that read it:
  - `scope-gate.sh` (PreToolUse `Edit|Write|MultiEdit|NotebookEdit`) — the first edit of a source file in a git worktree with no ledger for the current branch is denied once with a message asking for `/scope-ledger:scope init`; the retry passes. `.claude/`, `openspec/`, non-source files and paths outside the project are exempt. Same batch-window and session-flag mechanics as `openspec-superpowers-workflow`'s skip-gate.
  - `scope-review-triage.sh` (PostToolUse `Skill|Agent`) — after a review / scan / audit skill is loaded or a review-type subagent dispatched, increments `review_rounds` and injects the triage policy (findings are input, not a work order; adopt / defer / needs-user / noise; nothing fixed before it is in the ledger; until the goal is done only must-fix findings of this change are adopted). From round 3 a convergence warning asks for the remaining and deferred lists first.
  - `scope-stop-check.sh` (Stop) — blocks once per distinct open-item state while In scope has unticked items, listing them and the three ways out; `stop_hook_active` always passes.
  - `scope-session-start.sh` (SessionStart `startup|resume|compact|clear`) — prints the ledger with open and round counts into the new context, which is what brings the original goal back after a compaction.
- `/scope-ledger:scope` skill — `init "<goal>"`, `status`, `defer "<item>" --why … --to …`, `done`; carries the triage table and the convergence rule; reports git-ignore status of the ledger with all three `check-ignore` exit codes handled and never edits `.gitignore`.
- `tests/scope-hooks.test.sh` — 91 assertions, two inputs per branch, green under bash 5 and macOS bash 3.2; wired into CI. Mutation-verified on a copy before release (three mutations, each red).

### Notes

- Under `set -u`, bash reads a full-width character glued to a bare variable name (`$ledger：`) as part of the name and aborts; every interpolation next to non-ASCII text in the hooks is `${var}` for that reason.
