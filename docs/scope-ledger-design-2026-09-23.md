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

### The artifact: `<worktree>/.claude/scope-ledger.local.md`

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

A file, not a native task: it survives compaction, hooks can read it with `awk`, a person can read it, one per worktree maps naturally onto one branch / PR, and `.local.md` is the established pattern for plugin state (already git-ignored in projects that follow it). When an OpenSpec change is active, "In scope" holds the three phase-level items (finish `tasks.md`, Phase 5 review-notes, Phase 6 archive) rather than duplicating the task list.

### Four fail-open hooks

Every hook exits 0 on any unexpected condition; a missing `jq` means the hook does nothing. The deny-once pattern, the 5-second batch window and the session flag file are the same as `openspec-superpowers-workflow`'s `skip-gate.sh`.

**A git-tracked ledger is repository-controlled content.** Anyone who can commit to a repository could commit a `.claude/scope-ledger.local.md` whose lines the SessionStart hook would replay verbatim into the agent's context on every startup, and whose items the Stop hook would quote into its block reason. So every hook checks `git ls-files --error-unmatch` first and treats a tracked ledger as absent: nothing replayed, nothing quoted, nothing written; SessionStart prints one fixed line saying so. (Raised by the cross-vendor Codex pass on the first draft.)

`review_rounds` is bumped under a `mkdir` lock so two review hooks finishing in the same batch cannot both read N and write N+1.

| Hook | Event / matcher | Behaviour |
|---|---|---|
| `scope-gate.sh` | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` | First edit of a **source file** (code, shell, SQL, IaC, CI workflow — not Markdown/JSON) inside a git worktree by the **main thread**, when the ledger is missing or bound to a different branch → deny **once**, asking for `/scope-ledger:scope init "<goal>"`. The retry passes. Subagent edits (hook input carries `agent_id`) pass without touching the session flag: a subagent has no user request to write a goal from, and consuming the flag would leave the main thread ungated. Exempt: `.claude/`, `openspec/`, paths outside the project, non-git directories, a git-tracked ledger. |
| `scope-review-triage.sh` | PostToolUse `Skill\|Agent` | A **Skill** call whose name is on the review-entry allowlist (`review-branch`, `review-pr`, `security-review`, `codex-review-bg`, `codex:review`, `claude-security`, `security-audit`, `code-review`, `simplify`, `debate`, `high-precision-dev:start`; one ERE per line in `~/.claude/scope-ledger-review-patterns` extends it) increments `review_rounds` and injects the triage policy. An **Agent** dispatch whose subagent type looks review-like injects the policy only — review commands fan out into N parallel subagents, so counting dispatches would fire the round-3 warning inside the first review. Stem matching was tried first and counted `verification-before-completion`, `security-ci-setup` and `codex:setup` as reviews. Policy: findings are input, not a work order; each goes into the ledger first (adopt → In scope with source; later → Deferred with reason and destination; noise → one Log line); nothing is fixed before it is in the ledger; until the goal's In scope items are all ticked, only findings that belong to *this* change and are must-fix are adopted. From round 3 it adds a convergence warning asking for the remaining / deferred lists before another round. With no usable ledger it says so and points at `init`. |
| `scope-stop-check.sh` | Stop | Ledger present and In scope has unticked items → block **once** with the list and three options (continue; move to Deferred with reason and destination; state the points that need the user's decision). `stop_hook_active` → allow. The unticked list's checksum is remembered per session, so the same state bounces only once — a conversation mid-work is not nagged every turn. |
| `scope-session-start.sh` | SessionStart `startup\|resume\|compact\|clear` | Ledger present → print it (first 60 lines) with the open-item and round counts into the new context. This is what brings the original goal back after compaction. |

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
