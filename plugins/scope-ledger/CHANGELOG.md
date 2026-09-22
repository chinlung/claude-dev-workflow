# Changelog

All notable changes to the `scope-ledger` plugin will be documented in this file.

## [1.0.0] - 2026-09-23

### Added

- Initial release — a per-worktree scope ledger (`.claude/scope-ledger.local.md`: goal verbatim, branch, `review_rounds`, In scope / Deferred / Log) and four fail-open bash hooks that read it:
  - `scope-gate.sh` (PreToolUse `Edit|Write|MultiEdit|NotebookEdit`) — the main thread's first edit of a source file in a git worktree with no ledger for the current branch is denied once with a message asking for `/scope-ledger:scope init`; the retry passes. Subagent edits (hook input carries `agent_id`) pass without touching the session flag — a subagent has no user request to write a goal from, and consuming the flag would leave the main thread ungated. `.claude/`, `openspec/`, non-source files, paths outside the project and a git-tracked ledger are exempt. Same batch-window and session-flag mechanics as `openspec-superpowers-workflow`'s skip-gate.
  - `scope-review-triage.sh` (PostToolUse `Skill|Agent`) — a Skill call on the review-entry allowlist (`review-branch`, `review-pr`, `security-review`, `codex-review-bg`, `codex:review`, `codex:adversarial-review`, `claude-security`, `security-audit`, `code-review`, `simplify`, `debate`, `high-precision-dev:start`, `engineering:code-review`; extend with one regex per line in `~/.claude/scope-ledger-review-patterns`) increments `review_rounds` and injects the triage policy (findings are input, not a work order; adopt / defer / needs-user / noise; nothing fixed before it is in the ledger; until the goal is done only must-fix findings of this change are adopted). A review-type Agent dispatch injects the policy but never counts — review commands fan out into N parallel subagents. From round 3 a convergence warning asks for the remaining and deferred lists first.
  - `scope-stop-check.sh` (Stop) — blocks once per distinct open-item state while In scope has unticked items, listing them and the three ways out; `stop_hook_active` always passes.
  - `scope-session-start.sh` (SessionStart `startup|resume|compact|clear`) — prints the ledger with open and round counts into the new context, which is what brings the original goal back after a compaction.
- `/scope-ledger:scope` skill — `init "<goal>"`, `status`, `defer "<item>" --why … --to …`, `done`; carries the triage table and the convergence rule; reports git-ignore status of the ledger with all three `check-ignore` exit codes handled and never edits `.gitignore`.
- `tests/scope-hooks.test.sh` — 145 assertions, two inputs per branch, green under bash 5 and macOS bash 3.2; wired into CI. Seven mutations of a copy each verified red before release.

### Notes — what the pre-release reviews changed

The first draft went through the repo's own review chain (`/review-branch` with five adversarial verifier subagents, plus a Codex cross-vendor pass). Everything below was changed before 1.0.0 shipped, so none of it is a released bug; it is recorded because each one is a design decision the next reader should not have to rediscover.

- **A git-tracked ledger is repository-controlled content** (Codex, P1). SessionStart replayed the file verbatim into context and Stop quoted its lines into the block reason — a prompt-injection channel for anyone who can commit a `.claude/scope-ledger.local.md`. Every hook now checks `git ls-files --error-unmatch` first and treats a tracked ledger as absent; SessionStart prints one fixed line instead.
- **Agent dispatches no longer count as review rounds** (verifier, confirmed by replay). `/review-pr` launches six agents, a security scan dozens; counting dispatches jumped the counter to 5 inside the first review and fired the round-3 warning on the second agent. Only allowlisted Skill calls count now; Agent dispatches get the policy only.
- **Review detection is an allowlist, not keyword stems** (verifier, 215 local names scanned). `review|security|codex|verif…` counted `superpowers:verification-before-completion` (called before every completion claim), `security-ci-setup`, `codex:setup`, `codex:status` and the `claude-security` scan sub-agents as reviews. A user-level patterns file extends the allowlist.
- **Subagents pass the gate without consuming the flag** (verifier, from the harness's own hook schema: `agent_id` is present only inside a subagent). Before, a delegated implementer's first edit ate the session's single deny — the main thread was never asked for a ledger — and an implementer with a Skill tool would have written a goal it could only invent.
- **`review_rounds` is bumped under a `mkdir` lock** (Codex, P2): two hooks finishing in one batch could both read N and write N+1.
- **A ledger with no frontmatter gets one synthesised** (verifier). The bump used to report "round 1" forever on such a file while never changing it.
- **Cross-repository edits are documented as outside the gate** (verifier, three combinations replayed): "the project" is the session's project directory by design; the README's limits now say so, along with the subagent and 60-line-replay limits.
- Under `set -u`, bash reads a full-width character glued to a bare variable name (`$ledger：`) as part of the name and aborts; every interpolation next to non-ASCII text in the hooks is `${var}` for that reason.
