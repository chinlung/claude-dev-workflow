# pr-closeout

[繁體中文](README.zh-TW.md)

PR closeout as facts instead of hand-typed queries:

- **`ready` before the merge.** It reads a PR's merge readiness from GitHub and returns a fail-closed, exit-coded verdict.
- **`landed` after the merge.** It proves the merge happened as reviewed and that the branch is gone.
- **A merge gate.** A PreToolUse hook runs `ready` before any merge Claude attempts.
- **`pr-watch` after the push (1.2.0).** A skill that watches one PR until only the user can act, with `watch` judging each round and a guard hook keeping it from writing to GitHub.

## Install

```bash
/plugin install pr-closeout@scl-claude-plugins
```

After an upgrade, run `claude plugin update pr-closeout`. Installed copies are cached by version.

## `ready`

```bash
node ${CLAUDE_PLUGIN_ROOT}/scripts/pr-closeout.mjs ready <owner/repo> <pr> \
  [--expect-head <sha>] [--repo-dir <path>] [--accept-unreviewed <path>=<reason>]...
```

It prints one JSON object. Every check runs and `hits[]` lists each condition met; the exit code is the most urgent one.

| Exit | Meaning |
|---|---|
| 0 | Ready to merge |
| 2 | Conflicts with the base |
| 3 | Unresolved review threads; an outdated thread is not resolved |
| 4 | A check failed, the rollup is FAILURE or ERROR, or a required check is missing |
| 5 | Pending: a check is running, or GitHub is still computing mergeability |
| 6 | A merge gate; see `gate` |
| 7 | A query failed, a value is unknown, or a usage error |

| `gate` | Meaning |
|---|---|
| `not-open`, `draft` | The PR is not open, or is a draft |
| `changes-requested` | A reviewer requested changes |
| `head-mismatch` | The PR head is not `--expect-head` |
| `unreviewed` | With `--repo-dir`: files the last review-branch round did not see in this version |
| `blocked-unseen` | GitHub reports BLOCKED and nothing visible explains it (a required review, a ruleset) |
| `behind` | The base requires the branch to be up to date |

**Fail-closed.** An unknown enum value, a missing field, a failed query, 100 or more review threads or check contexts, or more than 1000 comments on one endpoint is exit 7, never ready. Comments are read page by page (1.2.0; before, 100 on one endpoint was exit 7). All queries share one 20 s deadline (`PR_CLOSEOUT_DEADLINE_MS`), so `ready` ends before the merge gate hook's 30 s timeout.

**Queries.** `gh api` runs first. If it fails, the token from `gh auth token` is passed to curl on stdin, so it never appears in argv or output.

**With `--repo-dir`** (the local clone of the PR's repo):

- **Review coverage.** Each file the PR adds or changes is compared, blob and mode, with review-branch's last record (`<gitdir>/review-branch-last.json`, same branch only). Documents are listed under `docsOnly` and never block; prompt files under `skills/`, `commands/`, `agents/`, `output-styles/` or `hooks/`, `requirements*.txt` and `CMakeLists.txt` are not documents. A file review-branch skipped as unchanged since an earlier round (`unchangedSince`) counts as reviewed. `--accept-unreviewed <path>=<reason>` lets one file through; the reason is required. No record, a different branch or a head that is not fetched gives `coverage.status: "unknown"`, which does not block. The comparison is of the bytes git stores: in a clone where git rewrites them on the way in or does not track the mode (`core.autocrlf`, `core.fileMode=false`), review-branch's record of the working tree can differ from the PR's blobs for a file nobody changed, and that file is reported `unreviewed`; pass `--accept-unreviewed` for it with that as the reason.
- **openspec.** If the repo has `openspec/`, the changes the PR touches that are still outside `archive/` are listed, with `reconcile-check verify`'s answer. This is a warning only. `verify` reads the change in the working tree of `--repo-dir`, not the PR's head, so it answers for the branch that is checked out there; it shares the run's deadline and a checker that does not answer in time is reported as `unavailable`.

**Also in the JSON**, without affecting the exit: `precedent` (whether the previous merged PR was squashed or merged), `baseBehind`, comment counts and authors per endpoint, and `suspectedSkip` (see below).

### Required checks

A per-user file, not part of this plugin. The script reads `$PR_CLOSEOUT_CONFIG`, or `~/.claude/pr-closeout/required-checks.json` when that is unset:

```json
{
  "<owner>/<repo>": {
    "required": ["security-review", "tests"],
    "minSeconds": { "security-review": 30 }
  }
}
```

- **A required check that never ran** (paths-ignore, a skipped workflow) is exit 4. To skip a required check on some PRs, such as docs-only ones, start the workflow on every PR and skip the job with an `if:`: a skipped job reports SKIPPED, which counts as passed. This repository's `.github/workflows/security-review.yml` does it with a `changes` job that reads the diff.
- **A check that finished faster than its `minSeconds`** is listed in `suspectedSkip`; a green check is not proof that the work ran.
- **No file** means nothing is required. **An unreadable file** is exit 7.

## `landed`

```bash
node ${CLAUDE_PLUGIN_ROOT}/scripts/pr-closeout.mjs landed <owner/repo> <pr> \
  --expect-head <sha> --repo-dir <path> [--branch <name>]
```

It checks four things and exits 0 or 6 (gates `not-merged`, `head-mismatch`, `not-on-base`, `branch-remains`), or 7 when a query or `git fetch` fails:

- `merged_at` is set.
- The merged head is `--expect-head`.
- The merge commit is an ancestor of `origin/<base>`, checked after a fetch. It never uses the branch tip, which a squash leaves off the base.
- With `--branch`: no open PR remains, and neither the remote nor the local branch exists.

## Merge gate

`hooks/pr-merge-gate.sh` runs before Bash commands and the GitHub MCP `merge_pull_request` tool.

- **What it finds.** `gh pr merge` (a number or URL, `--repo`/`-R`, `--match-head-commit`) and `gh api …/pulls/<n>/merge`, in command position, behind wrappers or a full path to `gh`, inside `$( )` or backticks that still run within double quotes or an unquoted heredoc, and inside a string handed to `bash -c`, `sh -c` or `eval`.
- **How it reads.** Each command is read three times and what any reading finds counts: the scanner's rules, the reading from before the comment rules (1.0.5), and since 1.1.0 a lexer that reads the text character by character the way bash does (a `\` line continuation, a quote inside backticks, a `$( )` holding double quotes inside double quotes, a `$( )` inside `$(( ))` or `$[ ]`, a heredoc delimiter in mixed quotes or closed by `EOF)`). A newer reading can add to what is checked, never take away.
- **What it does not find.** The hook reads the command text with scanners of its own, not with bash. It is there for a merge an agent types by mistake, not for a command built to get past it: a merge behind a variable or an alias, in a script file, or in a script fed to a shell on stdin (`bash <<EOF`, `… | bash`) can go unseen, and so can one on a line after a line bash rejects as a syntax error and drops, when a heredoc was opened on the dropped line (`a=(-( <<EOF`). A `gh api` call that also carries a merge path as an option's value is checked against the first merge path in it, not the endpoint gh merges (`gh api -H repos/o/r/pulls/3/merge repos/o/r/pulls/5/merge` checks PR 3 and merges PR 5). Branch protection is what stops a merge that must not happen.
- **What it does.** It runs `ready` for that PR; only exit 0 lets the merge through. The deny message lists what `ready` found.
- **When it denies.** A merge it cannot pin to a PR is denied, a GraphQL `mergePullRequest` among them. So is a missing jq, node or script. So is a `--match-head-commit` (or the MCP tool's `sha`) that is not a literal 40-hex sha: the hook reads the command text, where a variable or `$( )` is not expanded. For the same reason (1.1.1) a PR number, PR URL, repo, option name or `gh api` endpoint with a `$( )`, backticks or `${ }` in it is denied, never read as its literal part (`gh pr merge 3$(echo 0)` merges PR 30), and so is a merge with an unquoted one among its words, which may expand to no word at all (`gh pr merge --subject $(x) 3`). In a string handed to `bash -c`, `sh -c` or `eval`, a quoted one counts as unquoted: that shell splits the string into words again.
- **Time.** Reading the command and all `ready` runs of it share a 25 s budget (`PR_MERGE_GATE_BUDGET`) under the hook's 30 s timeout; when too little is left the merge is denied rather than left to a timed-out hook. The two older readings take time linear in the command's length; the lexer stops at a step limit (a merge it cannot read is denied).
- **When the hook itself fails (1.3.0).** Both hooks of this plugin carry `"onFailure": "block"` in `hooks.json`: a hook that times out, crashes or prints output Claude Code cannot read blocks the action instead of letting it through. This needs Claude Code v2.1.295 or later; an older version ignores the field and lets the action through. The hooks run under the first `bash` on PATH, `/bin/bash` 3.2 on a stock macOS, and CI runs their suites under bash 3.2 too. If a broken hook blocks every Bash call, disable the plugin (`/plugin disable pr-closeout`) and report it; `PR_CLOSEOUT_OK=1` works only while the hook runs.
- **Bypass.** Put `PR_CLOSEOUT_OK=1` in the command to bypass once. The MCP tool has no bypass; use `gh`.
- **Cost for other commands.** A command that is not a merge leaves at a builtin `case` on the input, after one `cat` to read it: no jq, perl or node starts.

## pr-watch

The `pr-watch` skill watches one PR after a push, in stretches: started when the user asks ("盯 PR"), run round by round with the built-in `/loop`, stopped when only the user can act, then started again. It never merges, resolves a thread, comments on GitHub or pushes without the user's word.

- **`watch <owner/repo> <pr> --repo-dir <clone> [--start | --stop] [--fixture <dir>] [--now <iso>]`** runs `ready`'s queries, judges the round and writes the state file `<clone>/.claude/pr-watch.<pr>.local.json` (add `*.local.json` to `.gitignore`). Exit 0 goes on, 8 stops (`watch.stop.reason`), 7 is a usage error or a refusal before judging (`not-started`, `stopped` — a round on a watch that has stopped —, `too-soon` — under 30 s since the last round of an active watch —, `wrong-branch`, a state file it did not write), with the state file untouched. `--stop` only writes `"active": false` and exits 0.
- **Stop reasons**, checked in this order: `not-open`, `fork`, `head-not-allowed` (the PR head is not an ancestor of the local HEAD), `query-failed` (three in a row), `limit` (24 h or 60 rounds), `ready`, `needs-user`, `no-progress` (two settled rounds without change). A head is never judged `ready` or `needs-user` in the round it is first seen, and a missing required check counts as still running.
- **`watch-ack <owner/repo> <pr> --repo-dir <clone> --comment <key>...`** marks comments as handled. A key is `<endpoint>:<id>:<16 hex of the body's sha256>`, so an edited comment or review is new again.
- **New comments** from anyone go to `/review-pr <pr> --triage-only <ids>` (code-audit-rigor 2.4.0), which classifies and stops; nothing is fixed before the user confirms the table.
- **`hooks/pr-watch-guard.sh`** denies, while a watch is active, Bash commands that write to GitHub (`gh pr|issue comment|review`, `gh api` with a field, `--input`, a non-GET method or a GraphQL mutation — a field or `--input` passes only when every `gh api` on the line has an unquoted `-X GET` among its own arguments —, curl or wget to github.com, `resolveReviewThread` and kin) and every GitHub MCP tool that is not a read. It is a tripwire for writes made by habit or by following the wrong part of a document, not a boundary against a model set on getting past it: that model could set the state's `active` to false. Stop the watch (`watch … --stop`) to write yourself. Like the merge gate, it blocks the action when it fails itself (see "When the hook itself fails" above).

## Tests

```bash
bash plugins/pr-closeout/tests/pr-closeout.test.sh
bash plugins/pr-closeout/tests/pr-merge-gate.test.sh
```

They need no network: fixtures stand in for GitHub. Each suite ends with mutants, and each mutant must fail on the case written for it.
