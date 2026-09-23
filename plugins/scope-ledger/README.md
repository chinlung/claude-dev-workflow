# scope-ledger

> A per-goal **scope ledger**, a per-repository **follow-ups backlog**, and six fail-open hooks that keep review-driven work from expanding past the original request — without letting a real bug or an exploitable security finding be skipped. The goal is written down before the first write, every review finding is triaged into the ledger before it becomes work, deferring is scheduling rather than dismissal, a session cannot end quietly with in-scope items open, and the ledger comes back after a context compaction.

## The problem it fixes

Layered review (self-review before commit, cross-vendor review, security review before push, PR gate, CI review, periodic audits) is a good thing — a missed real bug costs far more than a false positive. But every layer is also a finding generator, and nothing sits between "a reviewer produced a finding" and "that finding became work". Findings become fixes, fixes trigger the next review, the next review produces more findings. The original request is never marked done, and after a compaction it is not even in the transcript any more.

The opposite failure is just as real: a scope rule applied naively turns "not this change" into "not my problem", and a real defect goes into a list nobody reads. This plugin is built to fail neither way.

Measured before designing it (aggregates only): across every recorded session the built-in todo tool had been called zero times; one four-day session started from a single bug, ran 23 security reviews across 17 PRs and ended with the user asking "what are D12, D42, D43 … about"; another used the task tool for every batch and the user still asked five separate times what was left undone, because the audit's backlog lived outside the task list; nine of thirteen long sessions switch branches three or more times under one goal; about a quarter of sessions start from an audit-type request; hundreds of source files were written through `sed -i`, `perl -pi` and heredoc redirects rather than the Edit tool.

## Quick start

```bash
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install scope-ledger@scl-claude-plugins
```

Then, in any git project, the first time Claude writes a source file the gate asks for a ledger:

```
/scope-ledger:scope init "fix the notification that is not sent when a roster is uploaded"
```

That is the whole ceremony. Everything else is the hooks reminding, counting and blocking at the right moments.

Add `*.local.md` to the project's `.gitignore` if it is not there yet — `init` checks with `git check-ignore`, names the exact line to add, and repeats the reminder on every `status` until it is done, but never edits `.gitignore` itself.

## How it works

```
first source write (Edit/Write, or sed -i / perl -pi /    first prompt of the session
  > / tee / cp / mv / patch in Bash)                        └─ scope-prompt-reminder.sh (UserPromptSubmit)
  └─ scope-gate.sh / scope-gate-bash.sh (PreToolUse)             no ledger? one non-blocking line: init, plus
       main thread, project has no ledger?                        open follow-ups count (HIGH first); once per session
       → deny ONCE, ask for `scope init`
       (retry passes; the two gates share one flag;          review-entry Skill call | Codex companion | review Agent
        subagents, .claude/, openspec/, $TMPDIR,               └─ scope-review-triage.sh (PostToolUse)
        outside-project paths exempt)                              Skill: review_rounds += 1 and inject the mode's policy
                                                                   companion / Agent: inject only
Stop                                                               converge: warn from round 3 · harvest: check-in every 5
  └─ scope-stop-check.sh
       In scope still has "- [ ]" items?                     SessionStart (startup/resume/compact/clear)
       → block ONCE per distinct state, ask for a              └─ scope-session-start.sh
         per-item status; whether work continues is               ledger → frontmatter + whole In scope + counts
         the user's last instruction, not the hook's              follow-ups → open count, HIGH items listed
```

Every hook exits 0 on any unexpected condition (missing `jq`, unreadable ledger, not a git repo). They force the judgement to happen and be written down; they do not evaluate it.

**A git-tracked ledger is ignored by every hook.** A repository can commit a `.claude/scope-ledger.local.md`, and its text would otherwise be replayed into the agent's context at every session start and quoted into Stop-hook messages — a prompt-injection channel for anyone who can commit. So each hook checks first: a tracked ledger is never replayed, quoted or written; SessionStart prints one fixed line telling you to `git rm --cached` it and ignore `*.local.md`. The check looks at the path, not only at the index: a committed `.claude` symlink or a `.claude` submodule puts a real file at the ledger path after a plain clone with no index entry at that name (the pre-push security review reproduced both), so a symlinked `.claude`, a symlinked ledger file and a `.claude` index entry of mode `120000`/`160000` are all treated as repository-controlled, and the only function that writes refuses symlinked paths outright. The same applies to the follow-ups file.

**Which Skill calls count as a review round** is an explicit allowlist, not a keyword match: `review-branch`, `review-pr` (bare and plugin-prefixed), `security-review`, `claude-security`, `security-audit`, `code-review`, `simplify`, `debate`, `high-precision-dev:start`, `engineering:code-review`. Keyword matching was tried first and counted `verification-before-completion`, `security-ci-setup` and `codex:setup` as reviews. The Codex companion pass (`codex-review-bg`, `codex:review`, `codex:adversarial-review`) accompanies `/review-branch` as the same self-review, so it injects the policy without counting. To add your own entry points, put one extended regex per line in `~/.claude/scope-ledger-review-patterns` (blank lines and `#` comments ignored), e.g. `^acme:audit-all$`.

## The ledger — one per goal

`<worktree>/.claude/scope-ledger.local.md`:

```markdown
---
goal: <the user's original request, verbatim, one sentence>
mode: converge | harvest
opened: 2026-09-23
opened_on: feature/x          ← a record; the ledger is NOT bound to a branch
review_rounds: 0
---
## In scope
- [ ] item ← source: user
- [x] item ← source: review-branch@r1
## Deferred
- item ← source: security-review@r2 | severity: HIGH | why: pre-existing, not introduced here | where: issue #123
## Log
- 2026-09-23 10:00 review-branch r1: 5 findings → 2 adopted / 3 deferred / 0 noise
- 2026-09-23 PR #42 opened on feature/x
```

Three rules: `goal` is the user's words, not a paraphrase; every In scope line ends with its source; every Deferred line has a severity, a reason and a destination (issue, next goal, follow-ups, review-notes, won't-fix). A deferral without a destination is just forgetting with extra steps.

The unit is the goal. Switching branches for a hotfix, a Dependabot batch or the next PR of the same job never touches the ledger; each PR gets a Log line. When an OpenSpec change is active, In scope holds the three phase-level items (finish `tasks.md`, Phase 5 review-notes, Phase 6 archive) instead of duplicating the task list.

`mode` decides what a review finding is:

- **converge** (default) — the goal is a fix, a feature, a refactor. Findings are input; the triage table below applies.
- **harvest** — the goal *is* to find or fix a set of findings: a security audit, a dependency-vulnerability batch, a round of CI review comments, hardening follow-ups. Findings are the work: all into In scope, batched HIGH → MEDIUM → LOW, one PR per batch; LOW or uncertain ones may be deferred with a destination, never dropped; false positives still need counter-evidence in the Log. The hook asks for a status check-in every fifth round instead of a convergence warning.

## The follow-ups backlog

`<worktree>/.claude/scope-followups.local.md`, one line per item:

```markdown
# scope-ledger follow-ups
- [ ] 2026-09-23 HIGH admin import has the same early return ← from: fix roster notification ｜ source: security-review@r2 ｜ where: issue #12
```

`done` moves every Deferred item here (won't-fix excepted). SessionStart, the first-prompt reminder and `status` announce the open count with HIGH first; `init` lists them and offers to pull some into the new goal. Deferred work therefore lives in a file that is looked at, not in memory.

## The skill: `/scope-ledger:scope`

| Verb | What it does |
|---|---|
| `init "<goal>"` | Writes the ledger for this goal; decides the mode; refuses if a usable ledger exists (finish it with `done` first); offers open follow-ups for pickup; reports git-ignore status (`check-ignore` rc 0 / 1 / 128 all handled) and names the exact `.gitignore` line without editing it |
| `status` (default) | Prints the ledger, `mode · open N · deferred M · round R`, then the open follow-ups (HIGH first) |
| `defer "<item>" --severity HIGH\|MEDIUM\|LOW --why <reason> --to <destination>` | Moves an In scope item to Deferred; all three flags mandatory; a HIGH security item only to `issue #N` or `next: <goal>` |
| `done` | Only when no item is open and every Deferred line has a severity and a destination (HIGH security: issue or next goal): moves Deferred into the follow-ups file, writes a narrative memory entry, deletes the ledger |

### Triage policy (converge mode; what the PostToolUse hook injects)

A review's output is **input, not a work order**. Each finding goes into one of four boxes before anything is edited. **Deferring is scheduling, not dismissal**: a deferred real problem is still a real problem — it has moved, not vanished — and `done` refuses deferrals without a destination.

| Box | Test (any one suffices) | Ledger action |
|---|---|---|
| Adopt (fix now) | Introduced by or directly related to this change; **or** an exploitable security finding — attacker, action and gain can be named — whose fix lies in the code this change touches; **or** another instance of the same defect (sibling: fix the class, not one occurrence); **or** a project MUST rule; **or** boy-scout — under 10 lines, zero behavioural risk, real improvement | In scope + source tag |
| Defer | Real but not this change; pre-existing without an exception above | Deferred + severity + reason + destination; HIGH security → issue or next goal only |
| Needs the user | Business decision, trade-off, scope question | In scope "needs decision: …", named in the reply |
| Noise / won't-fix | False positive, deliberate design (with a record), no attack surface | One Log line **with a counter-evidence anchor** — dismissal needs proof exactly like adoption |

Until the goal's In scope items are all ticked, anything not in the first row goes to the second: a review round must not turn into a new goal. From the third review round on, the hook asks for the remaining and deferred lists before another round is opened.

## What it deliberately does not do

- Edit `.gitignore` (it reports and names the line; the project decides).
- Judge the triage. The gates make sure a judgement is written down; the judgement is yours.
- Replace OpenSpec's `tasks.md`.
- Decide for you whether a follow-up joins a new goal — `init` lists them and asks.
- Count reviews run through a raw CLI in Bash, or review-type agents dispatched directly without a Skill entry point — the PostToolUse hook counts only allowlisted `Skill` calls; `Agent` dispatches get the policy but never a round.

## Limits worth knowing

- The gates fire on source extensions only (code, shell, SQL, Terraform, Dockerfile, CI workflows). Markdown / JSON / plain YAML edits never trigger them, so a documentation session needs no ledger.
- The Bash gate recognises `>`/`>>`, `tee`, `sed -i`, `perl -pi`/`-i`, `cp`, `mv` (also `git mv`), and `git apply` / `patch` in command position (`npm version patch` and `--grep patch` are not writes). A leading `cd <dir>` in the same command moves the base for the segments after it, so `cd src && cat > a.php` is judged as `src/a.php`. A target containing an unexpanded `$VAR` cannot be resolved and is skipped. A formatter, a scaffolder (`artisan make:…`), `python - <<EOF` writing files, or a `pint` run are not recognised; the first-prompt reminder is the backstop for those sessions.
- "The project" is the session's project directory (`CLAUDE_PROJECT_DIR`, falling back to the hook's `cwd`). Edits to files in *another* repository — a sibling repo reached by absolute path or `--add-dir` — are outside the project and pass the gates untouched, and the ledger, round counter and Stop check all live under the session's project. A parent directory that is itself a git repository with nested repositories beneath it works: the ledger sits at the parent and covers a goal that spans the nested repos. To gate another repository, open the session there.
- Subagent edits pass the gates without consuming the session's one deny (the hook input's `agent_id` tells them apart). The flip side: a session whose main thread never writes a source file itself — every change delegated to implementer subagents — is only reminded by the first-prompt line, never denied. Create the ledger with `init` at the start of such a session.
- Two sessions on one worktree share one ledger; the plugin does not arbitrate writes (single-writer discipline applies, as with any shared worktree state).
- The Stop hook remembers the open-item list's checksum per session in `$TMPDIR`; the reminder repeats only when that list changes.
- A repository's own build or install scripts can write an *untracked* ledger after a clone and get past the tracked-ledger check. Executing repository code already compromises the machine; the prompt-injection channel is the smaller consequence. Accepted residual.

## Testing

```bash
bash plugins/scope-ledger/tests/scope-hooks.test.sh
```

263 assertions feed JSON to each of the six hooks and check stdout, exit code and flag / state files, with at least two inputs per branch; green under bash 5 and macOS `/bin/bash` 3.2. CI runs it on every push (`.github/workflows/validate.yml`), and the repo's local PostToolUse hook runs it after any edit under `plugins/`. Before 1.0.0 shipped, eighteen mutations of a copy each turned it red: emptying `ledger_unchecked`, skipping the gate's ledger lookup, raising the warning threshold, reporting every ledger as untracked, dropping the subagent pass-through, counting Agent dispatches as rounds, removing the bump lock, keeping only the index lookup in the tracked check, letting the bump write through symlinks, collecting no Bash write targets, not stripping heredoc bodies, the prompt reminder forgetting its flag or ignoring an existing ledger, not clearing stale locks, reading harvest as converge, counting the Codex companion, truncating the In scope replay, and reverting the Stop message to "keep working".

One portability note baked into the scripts: under `set -u`, bash treats a full-width character glued to a bare variable name (`$ledger：`, `「$lb」`) as part of the name and aborts with "unbound variable". Every interpolation next to non-ASCII text is written as `${var}`.
