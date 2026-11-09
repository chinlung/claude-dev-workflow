# Changelog

All notable changes to the `pr-closeout` plugin will be documented in this file.

## [1.0.0] - 2026-11-09

### Added

- **`scripts/pr-closeout.mjs ready <owner/repo> <pr>`** — one GraphQL query plus the three review endpoints, read as a verdict. The exit code is the most urgent of every condition met; `hits[]` lists all of them:

  | Exit | Meaning |
  |---|---|
  | 0 | Ready |
  | 2 | Conflict |
  | 3 | Unresolved review threads, outdated ones included |
  | 4 | A check failed, the rollup is FAILURE or ERROR, a conclusion is not SUCCESS, NEUTRAL or SKIPPED, or a required check is missing |
  | 5 | Pending, including `mergeable: UNKNOWN` |
  | 6 | Merge gate; the `gate` field says which |
  | 7 | Query failed or a value is unknown |

  The gates in exit 6 are `not-open`, `draft`, `changes-requested`, `head-mismatch`, `unreviewed`, `blocked-unseen` and `behind`. `blocked-unseen` is GitHub reporting BLOCKED while nothing visible is wrong; it is never read as green.
- **Fail-closed.** An unknown enum, a missing field or a list of 100 or more entries is exit 7.
- **Query path.** `gh api` runs first. When it fails, the token from `gh auth token` reaches curl on stdin (`-H @-`), so it never appears in argv or output.
- **`--repo-dir`: reviewed bytes equal merged bytes.** Each file the PR adds or changes is compared, blob and mode, with review-branch's last record. A file the review never saw, or saw in another version, is gate `unreviewed`. Documents are listed but do not block. `--accept-unreviewed <path>=<reason>` lets one file through; the reason is required. No record, a different branch or a head not fetched gives `unknown`.
- **`--repo-dir`: openspec warning.** Changes the PR leaves unarchived are listed, each with `reconcile-check verify`'s answer. This never sets the exit.
- **Required checks.** A per-user list in `PR_CLOSEOUT_CONFIG`, default `~/.claude/pr-closeout/required-checks.json`, names the checks a repo's PRs must show. A missing one is exit 4. A check that finished under its `minSeconds` is listed in `suspectedSkip`.
- **Extra facts.** The JSON also carries the precedent (how the last PR was merged), `baseBehind` and comment counts per endpoint.
- **`landed <owner/repo> <pr> --expect-head <sha> --repo-dir <path> [--branch <name>]`** — proves the merge:
  - `merged_at` is set.
  - The merged head is the one expected.
  - The merge commit, never the branch tip, is an ancestor of `origin/<base>`.
  - With `--branch`: no open PR remains, and neither does the remote or the local branch.

  Its gates are `not-merged`, `head-mismatch`, `not-on-base` and `branch-remains`.
- **Merge gate hook.** `hooks/pr-merge-gate.sh` is a PreToolUse hook on Bash and on the GitHub MCP merge tool. It finds `gh pr merge` (number, URL, `--repo`/`-R`, `--match-head-commit`) and `gh api …/pulls/<n>/merge` in command position, including behind wrappers, full paths and backticks, and runs `ready` for that PR; only exit 0 passes.
  - A merge whose PR it cannot read is denied, a GraphQL `mergePullRequest` among them.
  - Missing jq, node or the script also denies.
  - `PR_CLOSEOUT_OK=1` bypasses once.
  - Commands that are not a merge leave at a builtin `case`.
- **Skill.** `skills/pr-closeout` maps the six closeout steps to these commands, says what to do for each exit and gate, and carries the CI failure rules: re-run a flake once, read the log on the second failure, check `baseBehind` when the failure is in code the PR did not touch.

### Notes

- Tests: `tests/pr-closeout.test.sh` (144 checks, 32 mutants) and `tests/pr-merge-gate.test.sh` (64 checks, 12 mutants). Each mutant must fail on the case written for it.
- Verified against real PRs before release:
  - `ready` on a merged PR reported `not-open` and listed the five code files a fix commit added after the last review-branch round.
  - `landed` on another merged PR reported exit 0 with the branch gone everywhere.
- After installing or upgrading, run `claude plugin update pr-closeout`; installed copies are cached by version.
