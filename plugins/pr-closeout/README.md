# pr-closeout

[繁體中文](README.zh-TW.md)

PR closeout as facts instead of hand-typed queries:

- **`ready` before the merge.** It reads a PR's merge readiness from GitHub and returns a fail-closed, exit-coded verdict.
- **`landed` after the merge.** It proves the merge happened as reviewed and that the branch is gone.
- **A merge gate.** A PreToolUse hook runs `ready` before any merge Claude attempts.

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

**Fail-closed.** An unknown enum value, a missing field, a failed query or a list of 100 or more entries is exit 7, never ready. All queries share one 20 s deadline (`PR_CLOSEOUT_DEADLINE_MS`), so `ready` ends before the merge gate hook's 30 s timeout.

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

- **A required check that never ran** (paths-ignore, a skipped workflow) is exit 4.
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
- **What it does not find.** The hook reads the command text with a small scanner of its own, not with bash. It is there for a merge an agent types by mistake, not for a command built to get past it: a merge behind a variable or an alias, in a script file, in a script fed to a shell on stdin (`bash <<EOF`, `… | bash`), or in a `$( )` that itself holds quotes inside double quotes can go unseen. Branch protection is what stops a merge that must not happen.
- **What it does.** It runs `ready` for that PR; only exit 0 lets the merge through. The deny message lists what `ready` found.
- **When it denies.** A merge it cannot pin to a PR is denied, a GraphQL `mergePullRequest` among them. So is a missing jq, node or script. So is a `--match-head-commit` (or the MCP tool's `sha`) that is not a literal 40-hex sha: the hook reads the command text, where a variable or `$( )` is not expanded.
- **Time.** All `ready` runs of one command share a 25 s budget (`PR_MERGE_GATE_BUDGET`) under the hook's 30 s timeout; when too little is left the merge is denied rather than left to a timed-out hook.
- **Bypass.** Put `PR_CLOSEOUT_OK=1` in the command to bypass once. The MCP tool has no bypass; use `gh`.
- **Cost for other commands.** A command that is not a merge leaves at a builtin `case` on the input, after one `cat` to read it: no jq, perl or node starts.

## Tests

```bash
bash plugins/pr-closeout/tests/pr-closeout.test.sh
bash plugins/pr-closeout/tests/pr-merge-gate.test.sh
```

They need no network: fixtures stand in for GitHub. Each suite ends with mutants, and each mutant must fail on the case written for it.
