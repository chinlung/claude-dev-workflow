# Changelog

All notable changes to the `pr-closeout` plugin will be documented in this file.

## [1.0.5] - 2026-11-12

### Fixed

- **Merge gate: a comment no longer hides the merge after it.** A `#` that starts a word comments out the rest of its line; the tokenizer used to read an apostrophe in `# don't merge yet` as the start of a single-quoted string that ran to the next apostrophe, so `gh pr merge 12 --repo o/r` on the next line reached GitHub without `ready` being asked. The heredoc pass already skipped comments, the tokenizer did not. A `#` inside a word (`echo x#y`) is not a comment. Two things bash knows went into the tokenizer with it: inside `` `…` `` a comment ends at the closing backtick (`` echo `# don't`; gh pr merge 8 --repo o/r `` is still checked), and `${…}` is the inside of one word, where a `#`, a quote or a blank starts nothing (`echo ${x:- #}; gh pr merge 12 --repo o/r` is still checked) and a `}` inside quotes does not close it; the `$( … )` and backticks a `${…}` holds are still scanned as commands, except inside its own single quotes. Found by the differential test added to openspec-superpowers-workflow 3.1.2, which runs generated commands in bash and compares.

### Tests

- `pr-merge-gate.test.sh`: 170 checks, 42 mutants (`comment`, `backtick-comment` and four for `${…}`, and a case only the heredoc pass's comment rule can save).

## [1.0.4] - 2026-11-11

### Fixed

- **Merge gate: a heredoc body is scanned as one text.** The `$( … )` and backticks of an unquoted heredoc body were scanned line by line, so a substitution that runs across lines was cut apart. `cat <<EOF`, `$(echo hi`, `gh pr merge 7 --repo o/r)`, `EOF` merges (bash takes the newline inside `$( … )` as a command separator) and reached GitHub without `ready`; a merge written as text inside single quotes in such a substitution was taken for a merge and sent to `ready`. 1.0.0 scanned it the same way. Found by a cross-vendor review of openspec-superpowers-workflow 3.1.1, which brought archive-gate onto this tokenizer.
- The header comment said quoted text and heredoc bodies never match; it now names the substitutions that do.

### Changed

- The tokenizer's two regions are marked `# >>> shared-tokenizer:` … `# <<< shared-tokenizer:`; openspec-superpowers-workflow's `tests/shared-tokenizer.test.sh` keeps them identical to archive-gate's copy. The double-quoted text handed to the substitution scan is a plain slice now, with no change in what it holds.

### Tests

- `pr-merge-gate.test.sh`: 146 checks, 36 mutants (two cases and the `per-line-body` mutant for the fix above).

## [1.0.3] - 2026-11-10

### Fixed

- **Merge gate: `$'…'` is a quote.** Inside it `\'` does not close the string. The hook read `$'it\'s'` as a string that ended at the backslash, every quote after it paired wrongly, and a `gh pr merge` on a later line reached GitHub without `ready` being asked. 1.0.0 missed it the same way. Both the heredoc pass and the tokenizer read it now. Only `\'`, `\"` and `\\` are decoded: a word written with any other escape (`$'1\062'` is `12` to bash) keeps its backslash, so it is never taken for another PR number and the merge is denied as unreadable. Three mutants must die on their cases.

### Tests

- `pr-merge-gate.test.sh`: 142 checks, 35 mutants.

## [1.0.2] - 2026-11-10

### Changed

- **Merge gate: `--match-head-commit` must be a literal 40-hex sha.** The hook reads the command text, where `"$SHA"` or `$(git rev-parse HEAD)` is not expanded, and passed that text to `ready` as the expected head. `ready` answered `head-mismatch` with nothing to say why. Such a value, a short sha or a branch name is now denied with a message that says so; the MCP tool's `sha` is held to the same rule.
- **`ready`: `reconcile-check verify` shares the run's deadline.** A checker that hung held `ready` until the hook's own timeout. It is cut off and the change is listed with `verify: "unavailable"`.

### Docs

- The README says what the merge gate does not find (it reads the command with a scanner of its own, and guards against a mistake, not against a command built to pass it), that a clone where git rewrites bytes or does not track the mode can report an unchanged file as `unreviewed`, and that `verify` reads the working tree of `--repo-dir`, not the PR's head.
- "No subprocess" for a command that is not a merge was one `cat` short of true; the hook comment and both READMEs now say no jq, perl or node starts.

### Tests

- `pr-closeout.test.sh`: a symlink recorded as `link:<hash>` and a regular file swapped for a symlink with the same bytes (the `link:` branch of the record key had no case), and a `verify` that hangs. 160 checks, 38 mutants.
- `pr-merge-gate.test.sh`: 136 checks, 32 mutants.

## [1.0.1] - 2026-11-10

### Fixed

- **Merge gate: a `<<` inside a quoted string is not a heredoc.** `echo "<<true"` followed by `gh pr merge …` and a later line that read `true` made the hook drop the merge line as a heredoc body, so `ready` was never asked. The heredoc pass now walks the characters and carries an open quote from one line to the next, so a `<<` opens a heredoc only outside quotes, including inside a string that spans lines; a heredoc opened on a line that is not finished yet (its string is still open, or it ends in a continuation backslash) starts its body after that line ends, as bash does. `cat <<EOF \` followed by `&& gh pr merge …` used to lose the merge to the body. A `$( … )` starts over inside the quote around it, so the heredoc of `git commit -m "$(cat <<'EOF' …)"` counts and a lone quote in its body pairs with nothing outside; inside `$(( … ))` and `(( … ))` a `<<` is a shift, and a `#` comment is skipped, so a lone quote in one opens nothing.
- **Merge gate: a heredoc that never closes is scanned again, and each `<<` on a line has its own body.** Its lines were put back as commands without looking for a heredoc among them, so a real heredoc after `$((1<<n))` had its body read as commands, which denied a merge only mentioned in it. The closing line must still equal the delimiter: `EOF)` inside `$( … )` is not taken as one.
- **Merge gate: the heredoc delimiter is read as a whole word.** `<<EOF-TEXT` closes on `EOF-TEXT`; only the leading `\w+` used to be taken, so the heredoc never closed and its text was read as commands, which denied a merge that was only mentioned in it.

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
- **Fail-closed.** An unknown enum, a missing field or a list of 100 or more entries is exit 7. All queries share one 20 s deadline (`PR_CLOSEOUT_DEADLINE_MS`), under the merge gate hook's 30 s timeout.
- **Query path.** `gh api` runs first. When it fails, the token from `gh auth token` reaches curl on stdin (`-H @-`), so it never appears in argv or output.
- **`--repo-dir`: reviewed bytes equal merged bytes.** Each file the PR adds or changes is compared, blob and mode, with review-branch's last record. A file the review never saw, or saw in another version, is gate `unreviewed`. Documents are listed but do not block; prompt files (`skills/`, `commands/`, `agents/`, `output-styles/`, `hooks/`) and `requirements*.txt` / `CMakeLists.txt` are not documents. A file review-branch skipped as unchanged since an earlier round counts as reviewed, as review-branch itself counts it. Deleted files count too: a deletion the last review did not record as `deleted` is unreviewed. `--accept-unreviewed <path>=<reason>` lets one file through; the reason is required. No record, a different branch or a head not fetched gives `unknown`.
- **`--repo-dir`: openspec warning.** Changes the PR leaves unarchived are listed, each with `reconcile-check verify`'s answer. This never sets the exit.
- **Required checks.** A per-user list in `PR_CLOSEOUT_CONFIG`, default `~/.claude/pr-closeout/required-checks.json`, names the checks a repo's PRs must show. A missing one is exit 4. A check that finished under its `minSeconds` is listed in `suspectedSkip`.
- **Extra facts.** The JSON also carries the precedent (how the last PR was merged), `baseBehind` and comment counts per endpoint.
- **`landed <owner/repo> <pr> --expect-head <sha> --repo-dir <path> [--branch <name>]`** — proves the merge:
  - `merged_at` is set.
  - The merged head is the one expected.
  - The merge commit, never the branch tip, is an ancestor of `origin/<base>`.
  - With `--branch`: no open PR remains, and neither does the remote or the local branch.

  Its gates are `not-merged`, `head-mismatch`, `not-on-base` and `branch-remains`.
- **Merge gate hook.** `hooks/pr-merge-gate.sh` is a PreToolUse hook on Bash and on the GitHub MCP merge tool. It finds `gh pr merge` (number, URL, `--repo`/`-R`, `--match-head-commit`) and `gh api …/pulls/<n>/merge` in command position, including behind wrappers, full paths and backticks, and inside `$( )` or backticks that still run within double quotes or an unquoted heredoc (options that take a value, such as `--subject`, never lend it as the PR number; two PR numbers are denied), and inside a command string handed to `bash -c`, `sh -lc` or `eval`, and runs `ready` for that PR; only exit 0 passes.
  - A merge whose PR it cannot read is denied, a GraphQL `mergePullRequest` among them.
  - Missing jq, node or the script also denies.
  - `PR_CLOSEOUT_OK=1` bypasses once.
  - All `ready` runs of one command share a 25 s budget (`PR_MERGE_GATE_BUDGET`) under the hook's 30 s timeout; too little left is a deny.
  - Commands that are not a merge leave at a builtin `case`.
- **Skill.** `skills/pr-closeout` maps the six closeout steps to these commands, says what to do for each exit and gate, and carries the CI failure rules: re-run a flake once, read the log on the second failure, check `baseBehind` when the failure is in code the PR did not touch.

### Notes

- Tests: `tests/pr-closeout.test.sh` (155 checks, 36 mutants) and `tests/pr-merge-gate.test.sh` (91 checks, 20 mutants). Each mutant must fail on the case written for it.
- Verified against real PRs before release:
  - `ready` on a merged PR reported `not-open` and listed the five code files a fix commit added after the last review-branch round.
  - `landed` on another merged PR reported exit 0 with the branch gone everywhere.
- After installing or upgrading, run `claude plugin update pr-closeout`; installed copies are cached by version.
