# scope-ledger — design (2026-09-23)

## Problem

Layered review (self-review before commit, cross-vendor review, security review before push, PR gate, CI review, periodic security audit) is deliberate: a missed real bug costs far more than a false positive. But every layer is also a **finding generator**, and nothing sits between "a reviewer produced a finding" and "that finding became work". Findings become fixes, fixes trigger the next review, the next review produces more findings. The original request is never marked done, and after a context compaction it is not even in the transcript any more.

Evidence gathered from the author's own session history before designing (details kept in a private note; only aggregates here):

- Across every recorded session, the built-in todo tool had been called **0 times**; the newer task tool 20 times, all in two sessions. Almost no session had a machine-tracked list of what it was supposed to do.
- One 4-day session started from a single notification bug, ran **23 security reviews**, opened **17 PRs**, and ended with finding IDs in the fifties. The user's messages near the end were "list what is still unfinished" and "what are D12, D42, D43 … about" — the person driving the session could no longer see the list either. A sibling of the original bug sat in memory as "not handled" until the user asked for it by name.
- Another 4-day session used the task tool (20 tasks, all completed) and the user still asked **five separate times** "what is left undone?" — the audit's F-xx backlog lived outside the task list, so the task list did not represent the real scope.

Root causes, in order:

1. **No baseline artifact.** The original request and the in-scope list are not written anywhere that survives compaction. The native task tools are feature-gated, in-memory, not readable by hooks, and cannot enumerate open items from a Stop hook.
2. **No triage boundary between finding and work.** Reviews are unbounded generators; findings are acted on directly.
3. **No completion check.** Nothing asks "is the original goal done?" — the user does, by hand.
4. The existing spec workflow (`openspec-superpowers-workflow`) freezes `tasks.md` and logs review outcomes, but only for spec'd features. Bug fixes, audit follow-ups and PR wrap-up chains happen outside it.

## Prior art (skills.sh, 2026-09-23)

No hook-enforced mechanism exists. The closest match, `coleam00/skills/piv-fix-review-findings`, has the right policy — *a review is input, not a work order*; each finding is fix-now / defer / needs-human / noise — but it is prose only and bound to its own suite. `scope-check` compares a plan document with the current state but hard-codes another project layout; `compact-guard` is a pre-compaction checklist; `conductor-*` is a full planning framework that overlaps the spec workflow. This plugin borrows the triage taxonomy and adds machine enforcement.

Rejected alternatives:

- **A. A rule in CLAUDE.md / a prose skill.** The sessions above had the rules and still expanded — prose does not survive compaction or a four-day session.
- **B. Native task tool + `TaskCreated`/`TaskCompleted` hooks.** Gated by model/env, in-memory, single-event hooks cannot list what is still open, and the second session shows the backlog living outside the task list anyway.
- **C. The built-in `/goal`.** It drives *continuation until a judge says done* — the opposite direction.

## Design

### The artifact: `<worktree>/.claude/scope-ledger.local.md` — one per goal

```markdown
---
goal: <the user's original request, verbatim, one sentence>
mode: converge | harvest
opened: 2026-09-23
opened_on: feature/x          ← record only; the ledger is not bound to a branch
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

A file, not a native task: it survives compaction, hooks can read it with `awk`, a person can read it, and `.local.md` is the established pattern for plugin state (already git-ignored in projects that follow it). The unit of scope is the **goal**, not the branch: the first version bound a ledger to a branch and denied edits on any other branch, and the author's history shows 9 of 13 long sessions switching branches three or more times (one session 31 times) — hotfixes, PR chains, Dependabot batches — all under one goal. Seventeen PRs spawned by one goal is exactly the expansion this plugin exists to make visible, so they belong in one ledger's Log. When an OpenSpec change is active, "In scope" holds the three phase-level items (finish `tasks.md`, Phase 5 review-notes, Phase 6 archive) rather than duplicating the task list.

`mode` decides what a review finding is. **converge** (default): findings are input; only what belongs to this change is adopted, plus four explicit exceptions (below). **harvest**: the goal itself is to find or fix a set of findings — a security audit, a dependency-vulnerability batch, a round of CI review comments — so findings *are* the work, batched by severity. The first version had only the convergence rule, and about a quarter of the author's sessions start from an audit-type request; on those it would have pushed every finding into Deferred, which is precisely the "the ledger made me skip the fix" failure the plugin must not produce.

### The backlog: `<worktree>/.claude/scope-followups.local.md`

Deferring is scheduling, not dismissal, and a deferred item needs somewhere to live that is looked at. The first version wrote Deferred items into project memory on `done`; memory is where the author's own follow-ups had already been forgotten once (a prioritised list of five unfinished items sat in memory while the user asked five times what was left). So `done` now moves Deferred items into a per-repository follow-ups file, one line each with date, severity, origin goal and destination. SessionStart, the first-prompt reminder and `status` all announce the open count (HIGH first); `init` offers to pull items into a new goal; a HIGH security item cannot be deferred to "follow-ups" alone — it needs an issue number or the next goal before `done` accepts it.

### Triage policy (converge mode)

| Class | Test (any one suffices for adoption) | Ledger action |
|---|---|---|
| Adopt now | Introduced by or directly related to this change; **or** an exploitable security finding (attacker / action / gain can be named) whose fix lies in the code this change touches; **or** another instance of the same defect (sibling — fix the class, not one occurrence); **or** a project MUST rule; **or** boy-scout (<10 lines, zero behavioural risk, real improvement) | In scope, with source tag |
| Defer | Real but not this change; pre-existing without an exception above | Deferred, with severity, reason and destination; HIGH security → issue or next goal only |
| Needs the user | Business decision, trade-off, scope question | In scope "needs decision", named in the reply |
| Noise / won't-fix | False positive, deliberate design (with a record), no attack surface | One Log line **with a counter-evidence anchor** — dismissal needs proof exactly like adoption |

Until the goal's In scope items are all ticked, anything not in the first row goes to the second: a review round must not turn into a new goal.

### Six fail-open hooks

Every hook exits 0 on any unexpected condition; a missing `jq` means the hook does nothing. The deny-once pattern, the 5-second batch window and the session flag file are the same as `openspec-superpowers-workflow`'s `skip-gate.sh`.

| Hook | Event / matcher | Behaviour |
|---|---|---|
| `scope-gate-bash.sh` | PreToolUse `Bash` | The harness's auto mode steers the model toward `sed -i`, `perl -pi` and heredoc redirects, which the Edit gate never sees — the author's history has hundreds of such writes. This hook strips heredoc bodies and single-quoted strings, collects the command's write targets (the token after `>`/`>>`, `tee`, the file operands of `sed -i`/`perl -pi`, the last operand of `cp`/`mv`, `git apply`/`patch`) and hands each to the same verdict as the Edit gate. Reads, `$TMPDIR`, `/tmp`, `.claude/` and paths outside the project never trigger it. The two gates share one session flag, so a session gets one deny whichever tool makes the first write. |
| `scope-prompt-reminder.sh` | UserPromptSubmit | Once per session, on the first prompt a person types (harness wake-ups skipped): if the project has no usable ledger, one non-blocking line of context says so and points at `init`, and reports the open follow-ups count (HIGH first). Catches sessions whose edits take neither gate path (formatters, scaffolders). |

**A git-tracked ledger is repository-controlled content.** Anyone who can commit to a repository could commit a `.claude/scope-ledger.local.md` whose lines the SessionStart hook would replay verbatim into the agent's context on every startup, and whose items the Stop hook would quote into its block reason. So every hook checks first and treats a repository-controlled ledger as absent: nothing replayed, nothing quoted, nothing written; SessionStart prints one fixed line saying so. (Raised by the cross-vendor Codex pass on the first draft.) "Repository-controlled" is a property of the path, not only of an index entry: the pre-push security review reproduced two committed layouts — `.claude` as a symlink to a tracked directory, and `.claude` as a submodule — that put a real file at the ledger path after a plain clone while `git ls-files -- .claude/scope-ledger.local.md` finds nothing, so the first version of the check let both through and the triage hook wrote into tracked content through the symlink. The check now also refuses a symlinked `.claude`, a symlinked ledger file, and a `.claude` index entry of mode `120000` or `160000`; the one function that writes refuses symlinked paths outright.

`review_rounds` is bumped under a `mkdir` lock so two review hooks finishing in the same batch cannot both read N and write N+1.

| Hook | Event / matcher | Behaviour |
|---|---|---|
| `scope-gate.sh` | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` | First edit of a **source file** (code, shell, SQL, IaC, CI workflow — not Markdown/JSON) inside the project's git worktree by the **main thread**, when the project has no ledger → deny **once**, asking for `/scope-ledger:scope init "<goal>"`. The retry passes. The branch is irrelevant. Subagent edits (hook input carries `agent_id`) pass without touching the session flag: a subagent has no user request to write a goal from, and consuming the flag would leave the main thread ungated. Exempt: `.claude/`, `openspec/`, paths outside the project, non-git directories. |
| `scope-review-triage.sh` | PostToolUse `Skill\|Agent` | A **Skill** call whose name is on the review-entry allowlist (`review-branch`, `review-pr`, `security-review`, `claude-security`, `security-audit`, `code-review`, `simplify`, `debate`, `high-precision-dev:start`; one ERE per line in `~/.claude/scope-ledger-review-patterns` extends it) increments `review_rounds` and injects the mode's triage policy. The Codex companion pass (`codex-review-bg`, `codex:review`) runs alongside `/review-branch` as the same self-review round, so it injects without counting. An **Agent** dispatch whose subagent type looks review-like injects only — review commands fan out into N parallel subagents, so counting dispatches would fire the round-3 warning inside the first review. Stem matching was tried first and counted `verification-before-completion`, `security-ci-setup` and `codex:setup` as reviews. In converge mode a warning from round 3 asks for the remaining / deferred lists before another round; in harvest mode every fifth round asks for a status check-in instead. If the repository has open HIGH follow-ups, the message says how many. With no usable ledger it says so and points at `init`. |
| `scope-stop-check.sh` | Stop | Ledger present and In scope has unticked items → block **once** with the list and a request for a per-item status. The message does not ask the model to keep working: whether work continues is the user's last instruction (an authorised autonomous run continues; a paused or conversational session only reports). The first wording offered "continue" as the first option, and the author had once told a session to pause all agents — a Stop-hook directive must not override that. `stop_hook_active` → allow. The unticked list's checksum is remembered per session, so the same state bounces only once. |
| `scope-session-start.sh` | SessionStart `startup\|resume\|compact\|clear` | Ledger present → print the frontmatter and the **whole** In scope section (never truncated — that list is the point), the Deferred and Log counts and the first ten Deferred lines, then the open follow-ups count with the HIGH items. Open follow-ups are announced even when no ledger exists. This is what brings the original goal back after compaction and keeps deferred work visible at the start of the next job. |

### The `scope` skill (`/scope-ledger:scope`)

- `init "<goal>"` — writes the ledger (goal verbatim, current branch, `review_rounds: 0`), links the active OpenSpec change when there is one, and reports whether the file is git-ignored (`git check-ignore`, all three exit codes handled; it never edits `.gitignore`).
- `status` (default) — prints the ledger and the counts.
- `defer <item> --why <reason> --to <destination>` — moves an In scope item to Deferred; destination is mandatory (issue, project memory, review-notes, won't-fix).
- `done` — allowed only when every In scope item is ticked and every Deferred item has a destination; writes the goal and the Deferred summary into project memory (the existing PR wrap-up SOP already has a "update project memory" step) and removes the ledger.
- Carries the triage policy: the four-way taxonomy crossed with the over-correction filter already used in review (pre-existing? already guarded? deliberate asymmetry? real attack surface?) — those four questions are what goes in a Deferred item's `why`.

### Out of scope (deliberately)

- Editing `.gitignore` for the user (the project's own setting; the skill reports, the user decides).
- Enforcing *what* is triaged. The gates force the judgement to happen and to be written down; they do not evaluate it — same stance as the skip-gate.
- Replacing `tasks.md` in the spec workflow.

### Testing

`tests/scope-hooks.test.sh` feeds JSON to each hook and asserts on stdout, exit code and flag/state files, with at least two inputs per branch. Mutation check before shipping: make `ledger_unchecked` print nothing — the Stop-hook cases must go red; make the gate skip the ledger lookup — the "ledger present → allow" cases must go red.

### Portability

Hooks run under macOS `/bin/bash` 3.2 as well as CI's bash 5: no `mapfile`, no associative arrays, no `${var,,}`. `stat` is called the skip-gate way (`-c %Y` then `-f %m`, non-numeric output degrades to allow). `cksum` is used for the state signature because BSD and GNU agree on its first field.
