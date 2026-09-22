# scope-ledger

> A per-worktree **scope ledger** plus four fail-open hooks that keep review-driven work from expanding past the original request: the goal is written down before the first edit, every review finding is triaged into the ledger before it becomes work, a session cannot end quietly with in-scope items open, and the ledger comes back after a context compaction.

## The problem it fixes

Layered review (self-review before commit, cross-vendor review, security review before push, PR gate, CI review, periodic audits) is a good thing — a missed real bug costs far more than a false positive. But every layer is also a finding generator, and nothing sits between "a reviewer produced a finding" and "that finding became work". Findings become fixes, fixes trigger the next review, the next review produces more findings. The original request is never marked done, and after a compaction it is not even in the transcript any more.

Measured before designing this (aggregates only): across every recorded session the built-in todo tool had been called zero times; one four-day session started from a single bug, ran 23 security reviews across 17 PRs and ended with the user asking "what are D12, D42, D43 … about"; another used the task tool for every batch and the user still asked five separate times what was left undone, because the audit's backlog lived outside the task list.

## Quick start

```bash
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install scope-ledger@scl-claude-plugins
```

Then, in any git project, the first time Claude edits a source file the gate asks for a ledger:

```
/scope-ledger:scope init "fix the notification that is not sent when a roster is uploaded"
```

That is the whole ceremony. Everything else is the hooks reminding, counting and blocking at the right moments.

Add `*.local.md` to the project's `.gitignore` if it is not there yet — `init` checks with `git check-ignore` and tells you, but never edits `.gitignore` itself.

## How it works

```
first Edit/Write of a source file           review / scan / audit skill or agent
  └─ scope-gate.sh (PreToolUse)               └─ scope-review-triage.sh (PostToolUse)
       no ledger for this branch?                   review_rounds += 1
       → deny ONCE, ask for `scope init`            inject: findings are input, not a work
       (retry passes; .claude/ and                  order — triage into the ledger first;
        openspec/ paths exempt)                     round ≥ 3 → convergence warning

Stop                                         SessionStart (startup/resume/compact/clear)
  └─ scope-stop-check.sh                       └─ scope-session-start.sh
       In scope still has "- [ ]" items?            ledger present → print it into context
       → block ONCE per distinct state              (goal, open count, round count)
       with the list and three ways out
```

Every hook exits 0 on any unexpected condition (missing `jq`, unreadable ledger, not a git repo). They force the judgement to happen and be written down; they do not evaluate it.

## The ledger

`<worktree>/.claude/scope-ledger.local.md`:

```markdown
---
goal: <the user's original request, verbatim, one sentence>
branch: feature/x
opened: 2026-09-23
review_rounds: 0
---
## In scope
- [ ] item ← source: user
- [x] item ← source: review-branch@r1
## Deferred
- item ← source: security-review@r2 | why: pre-existing, not introduced here | where: issue #123
## Log
- 2026-09-23 10:00 review-branch r1: 5 findings → 2 adopted / 3 deferred
```

Three rules: `goal` is the user's words, not a paraphrase; every In scope line ends with its source; every Deferred line has a reason and a destination (issue, project memory, review-notes, won't-fix). A deferral without a destination is just forgetting with extra steps.

When an OpenSpec change is active, In scope holds the three phase-level items (finish `tasks.md`, Phase 5 review-notes, Phase 6 archive) instead of duplicating the task list.

## The skill: `/scope-ledger:scope`

| Verb | What it does |
|---|---|
| `init "<goal>"` | Writes the ledger for the current branch; refuses if one exists for another branch (finish it with `done` first); reports git-ignore status (`check-ignore` rc 0 / 1 / 128 all handled) |
| `status` (default) | Prints the ledger and `open N | deferred M | round R` |
| `defer "<item>" --why <reason> --to <destination>` | Moves an In scope item to Deferred; both flags mandatory |
| `done` | Only when no item is open and every Deferred line has a destination: writes project memory, deletes the ledger |

### Triage policy (what the PostToolUse hook injects)

A review's output is **input, not a work order**. Each finding goes into one of four boxes before anything is edited:

| Box | Ledger action |
|---|---|
| Adopt (fix now) — belongs to this change, real consequence if skipped | In scope + source tag |
| Defer — real but not this change, or pre-existing | Deferred + reason + destination |
| Needs the user — business decision, trade-off, scope question | In scope "needs decision: …", named in the reply |
| Noise / won't-fix — false positive, deliberate design, no attack surface | One Log line |

Until the goal's In scope items are all ticked, only findings that belong to this change **and** are must-fix are adopted. From the third review round on, the hook asks for the remaining and deferred lists before another round is opened.

## What it deliberately does not do

- Edit `.gitignore` (it reports; the project decides).
- Judge the triage. The gate makes sure a judgement is written down; the judgement is yours.
- Replace OpenSpec's `tasks.md`.
- Count reviews run through a raw CLI in Bash — the PostToolUse hook only sees `Skill` and `Agent` tool calls (skill name or subagent type matching `review|security|audit|codex|simplify|critic|adversar|verif|debate`).

## Limits worth knowing

- The gate fires on source extensions only (code, shell, SQL, Terraform, Dockerfile, CI workflows). Markdown / JSON / plain YAML edits never trigger it, so a documentation session needs no ledger.
- Two sessions on one worktree share one ledger; the plugin does not arbitrate writes (single-writer discipline applies, as with any shared worktree state).
- The Stop hook remembers the open-item list's checksum per session in `$TMPDIR`; the reminder repeats only when that list changes.

## Testing

```bash
bash plugins/scope-ledger/tests/scope-hooks.test.sh
```

91 assertions feed JSON to each hook and check stdout, exit code and flag / state files, with at least two inputs per branch; green under bash 5 and macOS `/bin/bash` 3.2. CI runs it on every push (`.github/workflows/validate.yml`), and the repo's local PostToolUse hook runs it after any edit under `plugins/`. Before 1.0.0 shipped, three mutations of a copy each turned it red: emptying `ledger_unchecked` (10 failures), skipping the gate's ledger lookup (6), raising the warning threshold to 99 (2).

One portability note baked into the scripts: under `set -u`, bash treats a full-width character glued to a bare variable name (`$ledger：`, `「$lb」`) as part of the name and aborts with "unbound variable". Every interpolation next to non-ASCII text is written as `${var}`.
