# OpenSpec + Superpowers Integration Workflow

## Overview

This project uses **two complementary tools** with strict role separation:
- **OpenSpec** = Spec lifecycle management (WHAT to build, source of truth)
- **Superpowers** = Development discipline (HOW to build, quality enforcement)

They NEVER overlap. Follow the phase sequence below for every feature.

---

## Prerequisites & Conventions

### Tool availability — CLI vs skills

Two interfaces to OpenSpec exist, and the project may have either, both, or neither:

- **`openspec` CLI** — installed globally via npm (`@fission-ai/openspec`). Commands: `openspec new change <name>`, `openspec status --change <name> --json`, `openspec instructions <artifact> --change <name> --json`, `openspec instructions apply --change <name> --json` (state, progress and task list of the implementation phase), `openspec validate`, `openspec archive <name>`, `openspec list`.
- **OpenSpec skills (`/openspec-*`)** — project-local skills that `openspec init` installs in `.agents/skills/openspec-*/` (OpenSpec 2.0); Claude Code reads them through the links in `.claude/skills/`. They are NOT built in; each wraps the CLI with a scripted workflow and is invoked by name (`/openspec-propose`) or by asking for the work. Which ones exist depends on the profile chosen at `openspec init`: `core` ships `/openspec-propose`, `/openspec-explore`, `/openspec-apply-change`, `/openspec-update-change`, `/openspec-sync-specs`, `/openspec-archive-change`; a custom profile can add `/openspec-new-change`, `/openspec-continue-change`, `/openspec-ff-change`, `/openspec-verify-change`, `/openspec-bulk-archive-change`, `/openspec-onboard`. The section "OpenSpec skills by phase" below says in which phase each may be used.
- **Left over from OpenSpec 1.x** — a project set up before 2.0 may still have `.claude/commands/opsx/` (the `/opsx:*` commands, which 2.0 removed; each became the skill of the same workflow). Run `openspec update` there: it installs the skills and removes the old command files it generated (ones someone edited are kept and listed). Commit the result.

**How to tell which is available**:
```bash
which openspec && openspec --version                # CLI present? 2.x?
ls .claude/skills/ 2>/dev/null | grep '^openspec-'  # skills present?
ls .claude/commands/opsx/ 2>/dev/null               # 1.x commands left? then openspec update
ls openspec/ 2>/dev/null                            # project initialized?
```

If the project is not initialized, run `openspec init .` first (note: no `--here` flag — use `.` or an explicit path).

**Skill substitution table** — when the skills are unavailable, use the CLI equivalents:

| Skill | CLI equivalent |
|---|---|
| `/openspec-propose <name>` | `openspec new change <name>` then loop through `openspec instructions <artifact-id> --change <name> --json` to fill each artifact |
| `/openspec-apply-change` (or start implementation) | `openspec instructions apply --change <name> --json` returns `state` (`blocked` / `ready` / `all_done`), `progress` and the task list; then implement the tasks yourself (Phase 4) |
| `/openspec-archive-change <name>` | `openspec archive <name> --yes` |

### OpenSpec skills by phase

OpenSpec's skills are actions on a change, not phases. Use each one only in the phase shown:

| Skill | Phase | Rule |
|---|---|---|
| `/openspec-propose`, `/openspec-new-change`, `/openspec-continue-change`, `/openspec-ff-change` | 1 | Creates proposal, specs, design and tasks. `ff` writes all four at once; treat design.md and tasks.md as drafts that Phases 2 and 3 overwrite |
| `/openspec-update-change` | 1–3 | Patches existing planning artifacts in place. Not from Phase 4 on: tasks.md is then the execution record, Phase 5 forbids spec edits and Phase 6a is a clean rewrite |
| `/openspec-explore` | 0–2 | Thinking before and during design. From Phase 4 on it must not edit any spec file |
| `/openspec-apply-change` | 4 | Works through tasks.md and ticks boxes, consistent with the Phase 4 rules |
| `/openspec-verify-change` | 5 entry, 6 input | Its findings go into review-notes.md with a tag. It lists unchecked tasks as CRITICAL; for lines that carry a `skip:` reason that is expected |
| `/openspec-sync-specs` | 6, after 6b5 | Merges delta specs into the main specs. Archiving already does this, so it is rarely needed. Never before Phase 6 |
| `/openspec-archive-change`, `/openspec-bulk-archive-change` | 6c | The archive gate applies. In a bulk run every change needs a fresh `reconcile-check.cjs` pass (this plugin's `verify`, not `/openspec-verify-change`) |
| `/openspec-onboard` | none | A tutorial, not part of the workflow |

### Path convention

After `openspec init`, the working directory is `openspec/`, not the project root. **All "changes/..." paths in this document are shorthand for `openspec/changes/...`**. Concretely:

- Active change folder: `openspec/changes/<feature-name>/`
- Archived change folder: `openspec/changes/archive/<YYYY-MM-DD>-<feature-name>/` (archive auto-prefixes with the archive date)
- Canonical spec source of truth: `openspec/specs/<capability>/spec.md` (populated when a change is archived)
- Project config / constitution: `openspec/config.yaml`

### Spec writing gotcha (learned from real runs)

The OpenSpec validator enforces that **every `### Requirement:` block MUST contain the word `SHALL` or `MUST` in its first paragraph** (the paragraph immediately after the header, before any bullet list or sub-heading). Putting normative keywords in a later paragraph or bullet will make `openspec validate --strict` reject the requirement with `ADDED "<name>" must contain SHALL or MUST`. When writing or rewriting specs in Phase 1 / 2 / 6, always lead each requirement with a MUST/SHALL sentence, then follow with bullets or details.

---

## Gates: when the workflow stops for the user

This section is the one place the gate rules live; the phases below only say which gate to run.

A gate stops only when a fact says the user is needed. `gate-check.cjs` reads the change and the project settings and answers with its exit code. Run it at each of the four gates:

```bash
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/gate-check.cjs p1 openspec/changes/<feature-name>    # end of Phase 1
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/gate-check.cjs p2 openspec/changes/<feature-name>    # end of Phase 2
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/gate-check.cjs p3 openspec/changes/<feature-name>    # Phase 3 → 4
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/gate-check.cjs p6b openspec/changes/<feature-name>   # Step 6b
```

- **exit 0 (`proceed`)**: list the defaults you took (every `[default]` item) and why, then carry on to the next phase in the same turn. The user can interrupt at any time, and the defaults stay in the artifact for them to overrule later.
- **exit 10 (`stop`)**: at P1 and P2, first dispatch an independent reviewer (subagent, `model: "opus"`; this is a judgement, never a cheaper model) and fold its result into the artifact. At P1, then run `gate-check p1` once more, so its record matches the version you present (P2 compares against that record). Then present its findings together with every `- <reason>` line gate-check printed, and **wait for the user's approval**. Do not decide on your own that a stop can be skipped.
- **exit 1 (error)**: something you can fix — a wrong path or argument, or (p3 only) a tasks.md that breaks the format rule below; the reason is on stderr. Fix it and run again; if it fails again, treat it as a stop.
- **No shell to run it**: apply the rules below by hand, reading the same files, and act on the result as if gate-check had printed it. There is no P1 record then, so at P2 compare the change's structural facts with what was shown to the user at P1 instead, and stop only for one they were not shown.
- **P2 finds no P1 record** (`no-p1-record`) and the user already approved P1 — in an earlier session, or for a change started before 3.1: run `gate-check p1` once to create the record, then check each reason it prints against what the user approved at P1 (the approval in the conversation, or the proposal and specs they reviewed). A reason they approved does not stop the workflow a second time; a reason they were not shown, or one you cannot confirm they were, is a stop. Then run `p2` again. Without that earlier approval, `no-p1-record` is a stop like any other.

What stops each gate:
- **every gate**: `gates: supervised`, or settings that cannot be read (including an unknown `gates` value);
- **P1**: no `## Decisions` section in proposal.md, a `[needs user]` marker anywhere in proposal.md, a `BREAKING` marker, a spec delta with `MODIFIED`, `REMOVED` or `RENAMED Requirements`, an `## Impact` path matching `high_risk_paths`, no `specs/**/spec.md` at all (unless the change's `.openspec.yaml` sets `skip_specs: true`), or a spec file that cannot be read;
- **P2**: design.md missing or unreadable, a `[needs user]` marker anywhere in it, a structural fact P1 did not see (a `BREAKING` marker, a delta kind or a `high_risk_paths` hit that is new since P1, whether the proposal, the specs or the `high_risk_paths` settings changed; rewriting a glob counts as new), or no readable record of the P1 run. Every `p1` run writes that record to `.claude/openspec-gate.<feature-name>.local.json`;
- **P3, P6b**: nothing else — only the two rules for every gate. P3 first checks the tasks.md format (every `### Task N` section holds exactly one checkbox, none outside them) and exits 1 when it is broken.

Text inside HTML comments and code fences does not count. Matching is deliberately generous (a `[needs user]` marker counts in any bullet or heading form; `BREAKING` in capitals counts even in a negation; delta headings and `Impact` paths are read the way OpenSpec and a human would write them): doubt resolves toward stopping.

**Settings** (both optional; front matter only; `.claude/` here is the project root's, the directory that holds `openspec/`):
- `.claude/openspec-workflow.md` (committed — it describes the project): `high_risk_paths:` followed by `- <glob>` lines, indented or not; blank lines and `#` comments are fine (`**` crosses directories, `*` does not; a glob without `/` matches a root-level file such as `Dockerfile`). An inline value (`high_risk_paths: [a, b]`), a key other than `gates` and `high_risk_paths` (a misspelling would otherwise be ignored silently) and a repeated `gates:` all count as unreadable settings.
- `.claude/openspec-workflow.local.md` (gitignored — personal): `gates: supervised` stops at every gate (the 2.x behaviour); `gates: risk-based` is the default. Its `gates` wins over the committed file; its `high_risk_paths` adds to the committed list and cannot remove from it.

**`[needs user]` vs `[default]`**: `[needs user]` is a decision that changes *what* gets built and needs a value or risk trade-off only the user can make; `[default]` is a choice you made and can defend. When in doubt, mark `[needs user]`: these markers are reminders you write yourself, and gate-check cannot tell whether they are honest. An item you or the reviewer marked `[needs user]` is never downgraded to `[default]` — with one exception: the user has delegated the call in their own words ("skip the questions", "跳過提問", "you decide"). Then mark it `[default]`, say in the reply that it was delegated, and let the gate rules above decide as usual.

---

## Phase 1: Spec Definition (OpenSpec leads)

**Trigger**: User says "new feature", "propose", "add feature", or invokes `/openspec-propose`

**Actions**:
1. Run `/openspec-propose <feature-name>` (or `openspec new change <feature-name>` if the skill is not installed — see Prerequisites) to create `openspec/changes/<feature-name>/`
2. Using `openspec instructions <artifact-id> --change <feature-name> --json`, generate each artifact in dependency order:
   - `proposal.md` — the "why" and capability list (**primary user-reviewed artifact**)
   - `specs/<capability>/spec.md` — requirements with SHALL/MUST + scenarios (**primary user-reviewed artifact**, one file per capability listed in proposal)
   - `design.md` — **placeholder draft only**; Phase 2 will overwrite it entirely. Write a minimal stub noting it is a draft
   - `tasks.md` — **placeholder draft only**; Phase 3 will overwrite it entirely. Write a minimal stub noting it is a draft
3. Create `review-notes.md` in the same folder for Phase 5 to populate later (OpenSpec does not generate this — do it with `Write`). **Not an empty file**: seed it with exactly this header so the tag / Y-N semantics are pinned for whoever writes Phase 5 entries later (possibly a different session — projects that started from an empty file drifted into "Y = already handled" and mis-tagged every `[CODE]` fix as Y):
   ```markdown
   # Review Notes — <feature-name>

   <!-- Phase 5 log. One line per review comment, appended under a `## Round N - [Review Type] (YYYY-MM-DD)` heading:
        - [REQUIREMENT|DESIGN|CODE|CONSTITUTION] Y/N - description
        Y/N answers ONE question: "must an OpenSpec artifact be updated in Phase 6?" — it does NOT mean "handled / fixed".
          [CODE] is therefore always N, even when the fix is already committed.
          [CONSTITUTION] Y = a NEW cross-feature rule to add to the project constitution; do not log "existing rules were followed".
        Tag by the artifact the fix lands in (spec → REQUIREMENT, design.md → DESIGN, code only → CODE), not by the nature of the problem.
        Never edit proposal.md / specs/ / design.md / tasks.md during review — record here, reconcile in Phase 6.
        Add `final` to the last Round heading only after the user says review has converged — the archive gate checks it. -->
   ```
4. **Fast local pre-check (optional, lenient)**: run this plugin's bundled validator on the change folder to catch a missing artifact (any of `proposal.md` / `design.md` / `tasks.md` / `review-notes.md`, or no `specs/**/spec.md`) or an empty SHALL/MUST first paragraph *before* the authoritative CLI — it is fast and needs no OpenSpec install:
   ```bash
   node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs openspec/changes/<feature-name>
   ```
   (`${CLAUDE_PLUGIN_ROOT}` resolves to this plugin's install root — same convention used across the other plugins' skills/commands.) This is a **lenient pre-check, not a substitute** for step 5's strict validation.
5. Run `openspec validate <feature-name>` to catch SHALL/MUST violations and scenario-format errors (see Prerequisites → Spec writing gotcha)

6. Add a `## Decisions` section to `proposal.md`, after `## Impact`. List every decision about *what* gets built that the proposal settles or leaves open, one per line, marked `[needs user]` or `[default]` (see "Gates" above), each with your recommendation and one line of reasoning. If there is none, write `- none`. The section is required: without it gate-check stops.
   ```markdown
   ## Decisions
   - [needs user] Who may export: (a) admins only (b) any staff with the report permission; I recommend (a) because …
   - [default] A failed export is not retried; it logs a warning
   ```

**Quality gate (P1)**: run `gate-check.cjs p1` (see "Gates"). Only `proposal.md` and `specs/<capability>/spec.md` are the user's to review; `design.md` and `tasks.md` are initial drafts that Phases 2-3 overwrite — do NOT ask the user to review them in Phase 1. On a stop, the independent reviewer reads proposal.md, the spec deltas and the related `openspec/specs/` in full, and answers three questions: which decisions about what gets built does the proposal make without saying so; what do common industry and tool practices (Claude Code included) offer that the proposal does not list; and what contradicts an existing spec. Add what it finds to `## Decisions` before presenting.

---

## Phase 2: Design Refinement (Superpowers leads → sync back to OpenSpec)

**Trigger**: `gate-check.cjs p1` exits 0, or the user approves Phase 1 requirements, or says "brainstorm", "refine design"

**Before starting**: Read `SUPERPOWERS-HANDOFF.md` for the sync-back template and sidecar-file anti-patterns.

**Actions**:
1. Activate Superpowers `/brainstorming` skill
2. Use `openspec/changes/<feature-name>/proposal.md` and `specs/` as input context
3. **Question budget** (it covers the whole phase and overrides the brainstorming skill's default pacing):
   - Classify before you ask. Anything you can find out by reading code, running a command or looking at output is a fact, not a question: go and look.
   - Ask at most **2** questions in total, and only ones whose answer changes *what* gets built (scope, behavior, who is affected), not *how*. Write `design.md` in the same reply anyway, taking your recommended answer to each question as the assumption, and put the questions at the end of the reply. Do not hold the file back until they are answered. Each such question goes under `## Open Questions` marked `[needs user]`, which makes `gate-check.cjs p2` stop.
   - Everything else is an assumption: write it into `design.md` under `## Open Questions` marked `[default]`, each with the default you chose.
   - If the user says to skip the questions (any wording, e.g. "skip the questions", "跳過提問", "just write design.md"), ask nothing and write `design.md` now. They have delegated these calls, so every open question is `[default]` (see "Gates"). A conflict you notice (for example between the spec and the design) goes into the reply as a statement with the default you chose, not as a question.
   - If a fork can be settled by trying it, build a throwaway prototype in `$TMPDIR` or a scratch directory outside `openspec/`, and write the decision plus the evidence (one line) into `design.md`. A prototype is a disposable experiment, not a second design file, so it does not break the sidecar rule below.
4. Work through the areas a design must cover — boundary conditions and error handling, impact on the existing system, performance and scalability, security — and end each as a decision or an assumption in `design.md`, not as a question.
5. Before overwriting `design.md`, read `DESIGN-RED-FLAGS.md` and check the draft against it. Write each flag that applies, and what you did about it, under `## Trade-offs`.
6. Produce the refined design document

**Sync back (CRITICAL)**:
After brainstorming completes, OVERWRITE `openspec/changes/<feature-name>/design.md` with the refined design.
- Keep OpenSpec's file structure and location
- Replace content with Superpowers brainstorming output
- Preserve any OpenSpec-specific metadata/headers if present

**Do NOT create a separate Superpowers design file. The design lives in OpenSpec's structure.**

**Quality gate (P2)**: run `gate-check.cjs p2` (see "Gates"). On a stop, the independent reviewer reads design.md against `DESIGN-RED-FLAGS.md` and the spec; present its findings with the `[needs user]` questions.

---

## Phase 3: Task Planning (Superpowers leads → write to OpenSpec location)

**Trigger**: `gate-check.cjs p2` exits 0, or the user approves Phase 2 design, or says "plan tasks", "break down work"

**Before starting**: Read `SUPERPOWERS-HANDOFF.md` for the `tasks.md` location requirements and sidecar-file anti-patterns.

**Actions**:
1. Activate Superpowers `/writing-plans` skill
2. Use the updated `openspec/changes/<feature-name>/design.md` as input
3. Break work into 2-5 minute granularity tasks with:
   - Exact file paths
   - Complete implementation details
   - Verification steps per task
4. OVERWRITE `openspec/changes/<feature-name>/tasks.md` with the Superpowers plan

**Do NOT create a separate plan file. Tasks live in OpenSpec's tasks.md.**

**tasks.md format: one checkbox per Task.** OpenSpec counts every checkbox bullet as a task (`-`, `*`, `+` or a numbered bullet, at any depth and with any text; only `[x]` / `[X]` is done, so `[~]` or `[]` is an unfinished task), and Superpowers' `task-brief` cuts a task out of the plan by its `### Task N` heading. So write each Task as a heading with exactly one checkbox line under it, and turn the step list that `writing-plans` produces into a plain numbered list with no checkboxes:

```markdown
## 1. <group>
### Task 1: <title>
- [ ] 1.1 <the deliverable in one line, with its test>
1. Write the failing test…
2. Implement…
```

A checkbox on every step makes progress count several times too large and "tick it when done" a chore nobody does. That is how tasks.md ended up as a plan that nothing updated.

**Gate (P3)**: once `tasks.md` is written, run the bundled validator, then `gate-check.cjs p3` (see "Gates"; it is the check that tasks.md has one checkbox under each `### Task N`). When both pass, go on to Phase 4 in the same turn and name the execution method you chose (rule in Phase 4 step 1); the user does not review the task breakdown.
```bash
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs openspec/changes/<feature-name>
```

---

## Phase 4: Implementation (Superpowers leads exclusively)

**Trigger**: Phase 3's gate passes (or the user approves after a stop), or the user says "implement", "start coding", "execute"

**Actions**:
1. Activate `/executing-plans`. Use `/subagent-driven-development` instead only when the tasks are independent of each other and each can be written as a self-contained brief; tasks that share files or depend on one another cannot
2. Create a git worktree for isolated development. Superpowers >= 6.0.0 keeps worktrees in the project under a local worktree *root* — it reuses an existing `.worktrees/` or `worktrees/` if present, otherwise defaults to a `.worktrees/` root at the project top level. Each worktree is created under that root at `<root>/<branch>` (e.g. `.worktrees/<branch>/`), not at the root itself. The legacy global `~/.config/superpowers/worktrees/` was removed; ensure the root is git-ignored.
3. For each task:
   - Write test first (RED)
   - Implement to pass test (GREEN)
   - Refactor (REFACTOR)
4. Review per task (Superpowers >= 6.0.0 flow): a single task-reviewer reads the task's diff once and returns BOTH a spec-compliance verdict and a quality verdict, so one fix pass clears both. A "can't verify from the diff" verdict flags requirements that live in untouched code, for you to check directly. One broad whole-branch review runs once at the end on the most capable model — not task-by-task.

**Rules**:
- TDD is mandatory. Never write implementation before tests.
- If a task fails its reviewer (spec or quality verdict), fix it before moving to the next task.
- Never suppress reviewer findings or pre-rate severity. A defect the plan itself mandates is reported for you to decide on, not waved through.
- Do NOT modify any spec files during implementation.
- **tasks.md is the execution record.** When a task passes its completion contract (executing-plans `task-done`, or the SDD review), change that task's `- [ ]` to `- [x]` in the same turn as its commit. Do not rewrite the task description.
- A task you decide not to do stays unchecked and gets ` — skip: <reason>` at the end of its line. The reason needs a letter or digit; a bare `skip:` does not count, and neither does a `skip:` without the dash and the spaces around it (the check reads only that suffix, so a task that mentions a `skip:` flag is not excused by it).
- **Phase 4 exit check:** `openspec instructions apply --change <feature-name> --json` reports `progress.remaining` of 0, or every remaining line carries a skip reason. If Phase 5 later shows a task was not really finished, record it as a `[CODE] N` entry; it is settled in the step before the Phase 6 snapshot.

---

## Phase 5: Review & Feedback (Tool-neutral — human-driven)

**Trigger**: Implementation complete, PR submitted, code review begins

**Rules — STRICTLY ENFORCED**:

### What to do with review feedback:
- Fix the code as requested by reviewers
- Record ALL feedback in `openspec/changes/<feature-name>/review-notes.md`
- **NEVER modify spec files** (proposal.md, specs/, design.md, tasks.md) during review
- **When a reviewer or the user explicitly asks you to edit a spec file *now*, decline out loud.** Your reply must say, in plain words, that the spec is not being changed during review, why (Phase 6 does a clean rewrite from the Y items, so an in-review patch would be overwritten and would blur original intent from after-the-fact edits), and that the request is recorded as a `[REQUIREMENT]`/`[DESIGN]` Y entry. Silently rerouting the request — recording it correctly but never telling the person their instruction was not followed — is a violation: they will believe the spec was edited.
- **If an existing `review-notes.md` header or earlier rounds define Y/N differently** (e.g. "Y = handled this round"), do not adopt that convention. Write your entries with the semantics below and add one line noting the discrepancy; leave earlier rounds' text as-is.

### review-notes.md format:
```markdown
## Round N - [Review Type] (YYYY-MM-DD)
- [TAG] Y/N - Description of change
```

### Tags:
- `[REQUIREMENT]` — Missing requirement, wrong behavior, unhandled edge case
  → Mark Y (needs spec update)
- `[DESIGN]` — Architecture change, API change, data model change
  → Mark Y (needs spec update)
- `[CODE]` — Style fix, naming, refactor, performance optimization, bug fix
  → Mark N (code-only, no spec update needed). **`[CODE] Y` does not exist**: Y means "an OpenSpec artifact must change in Phase 6", never "this was fixed" — a finished code fix is still `[CODE] N`
- `[CONSTITUTION]` — Cross-cutting concern that applies to ALL features
  → Mark Y (needs constitution update, NOT this feature's spec). Only for a **new** rule to add; "the change complies with existing rule X" is not an entry at all

**Tag by the artifact the fix lands in, not by the nature of the problem.**
The reconciliation gate (RECONCILIATION-CRITERIA C1) routes strictly by tag:
`[REQUIREMENT]` may only update `proposal.md` / `specs/`, and `[DESIGN]` may
only update `design.md`. A "design decision" that contradicts the spec's
literal wording is therefore `[REQUIREMENT]` — the spec is the file that must
change. Deciding by problem-nature instead of fix-landing-point is the known
mis-tagging trap: the tag is written in Phase 4/5 but consumed in Phase 6,
possibly by a different session, so it must be routable without re-deriving
context.

### Example:
```markdown
## Round 1 - PR Review (2026-03-30)
- [CODE] N - Rename $data to $exportData for clarity
- [CODE] N - Add try-catch around CSV generation
- [DESIGN] Y - Change from sync to queue job for large exports
- [REQUIREMENT] Y - Add export progress notification support

## Round 2 - Security Review (2026-03-31)
- [CODE] N - Fix SQL injection in export filter
- [CONSTITUTION] Y - All export features must have rate limiting
- [DESIGN] Y - Export files must be encrypted, expire after 24hrs
```

**Repeat Phase 5 until all reviews pass.**

**Marking review as converged.** When the user says review has converged (no further rounds), add `final` to the last `## Round` heading, e.g. `## Round 3 - Security Review (2026-11-09, final)`. Only the user can make this call: never add `final` on your own judgment. The archive gate (Phase 6) refuses to archive a change whose last round is not marked `final`.

**Suggesting convergence.** Do not wait to be asked. When all three hold, say so with the evidence and ask one question — converge now, or run which further (costly) review or scan first:
1. the last round of every review layer you ran found no new `Y` entry;
2. no `[CODE]` finding is still unfixed;
3. every review layer has run at least once since the last fix landed.

The answer is still the user's: suggesting convergence is not declaring it.

---

## Phase 6: Reconcile & Archive (OpenSpec leads)

**Trigger**: All reviews passed, all code fixes merged, user says "reconcile" or "archive"

**Entry check (before 6a).** Read the last `## Round` heading of `review-notes.md`. If it does not carry `final`, the user has not declared review converged: do not start 6a and do not rewrite any artifact. Tell the user which open items that last round lists, and ask whether review has converged. Add `final` only after they say so. A merged PR or an instruction to archive is not that statement.

### Step 6a: Reconcile specs

**First**, settle `tasks.md`: tick every task that is done and add ` — skip: <reason>` to every one that is not (only the box and the skip suffix, never the task description). If nothing needs settling, do not open or rewrite the file. Then record it, so the archive gate can prove it was not touched during reconciliation (C3). `snapshot` refuses (exit 1, no state file) while any unchecked task has no skip reason:

```bash
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/reconcile-check.cjs snapshot openspec/changes/<feature-name>
```

Then read `openspec/changes/<feature-name>/review-notes.md` and process only items marked **Y**:

1. **[REQUIREMENT] Y items** → Update `proposal.md` and `specs/`
2. **[DESIGN] Y items** → Update `design.md`
3. **[CONSTITUTION] Y items** → List separately for user to add to project constitution
   (Do NOT put these in the feature's spec files)

Whatever the Y items, also rewrite **`## Decisions` in proposal.md** as the decisions finally taken, one per line (`- Admins only may export: …reason`). Drop the `[needs user]` / `[default]` markers and any reviewer note.

**CRITICAL RULE**: Do NOT patch incrementally. REWRITE clean versions as if you knew
all this information from the start. The goal is a spec that reads as a coherent document,
not a changelog with amendments.

**tasks.md is NEVER modified during reconciliation** (after the snapshot above). It is execution history.

### Step 6b: Summarize the reconciled specs

Run `gate-check.cjs p6b` (see "Gates"); on a stop the user confirms the rewritten specs first. Otherwise write a short summary of the rewrite — for each `Y` entry, the file it landed in — into the reply and into the description of the PR that carries the archive, then go straight on to Step 6b5. The user reviews the rewrite when they merge that PR; reconcile-check (6b5) is the gate here.

### Step 6b5: Reconciliation Criteria Gate（歸檔前核查）

改寫完成（Step 6b 的摘要寫好）之後、執行歸檔命令之前，**必須**執行：

```bash
node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/reconcile-check.cjs check openspec/changes/<feature-name>
```

1. 腳本機械檢查 R1–R8（`RECONCILIATION-CRITERIA.md` 列出每個 C 項對應的 R 編號）。`fail` 一律修正後重跑；`warn` 逐項說明怎麼處理。
2. `manual` 項（C1、C2、C5）需要你判斷：照 `RECONCILIATION-CRITERIA.md` 核查，在回覆中輸出核查結果表格與裁決。
3. 讀 `OUTPUT-CONTRACTS.md` 的 Phase 6 覆蓋定義，確認四個面向均已核查。
4. 腳本 exit 0 時會記下一份綁定各檔雜湊的 pass verdict；之後再改任何一個被核查的檔，verdict 就失效，必須重跑 `check`。

**路由規則（依裁決結果）：**

| 裁決 | 後續動作 |
|------|---------|
| `verified` | 繼續執行 Step 6c 歸檔 |
| `corrected` | 修正問題後**重新執行** Step 6b5 所有核查；不得直接進入歸檔 |
| `rejected` | 不得歸檔；向使用者報告具體問題並等待處置指示 |
| `needs_user_decision` | 停止歸檔流程，向使用者提出具體問題並等待裁決 |

**此 gate 不可跳過。** 未取得 `verified` 裁決，不得執行 `/openspec-archive-change`。歸檔閘門 hook 會在歸檔命令前執行 `reconcile-check.cjs verify`，沒有新鮮的 pass verdict 就擋下。

### Step 6c: Archive

Run `/openspec-archive-change <feature-name>` (or `openspec archive <feature-name> --yes` if the skill is not installed) to:
- Merge final requirements into `openspec/specs/<capability>/spec.md` (OpenSpec source of truth)
- Move the change folder to `openspec/changes/archive/<YYYY-MM-DD>-<feature-name>/` — the archive command auto-prefixes with the archive date, so the folder name is NOT just the feature name
- `review-notes.md` is preserved inside the archive for historical reference
- Note: archive warns when tasks.md has unchecked items (`Warning: N incomplete task(s) found`; it prints the count only, not the lines). After the snapshot every unchecked item carries a `skip:` reason, so the warning is expected; whether a line lacks a reason is decided by R6 in Step 6b5 and by the archive gate, not by this warning. When any `skip:` line is present, a non-interactive `openspec archive` exits 1 without `--yes` (it cannot read the confirmation), which is why the CLI fallback keeps `--yes`
- The archive gate hook runs before both `openspec archive` and the `mkdir` + `mv` into `changes/archive/` that the `/openspec-archive-change` and `/openspec-bulk-archive-change` skills run, and denies either one without a fresh pass verdict from Step 6b5. Prefix the command with `OPENSPEC_ARCHIVE_OK=1` to bypass it, and only when the user explicitly asks

### Step 6d: Constitution updates (if any)

If there were `[CONSTITUTION]` items, remind user and offer to update the project's constitution.

**Where the constitution lives**: OpenSpec's native location is `openspec/config.yaml`, specifically the `context:` field (shown to AI during every future `openspec instructions` call, i.e. every future Phase 1) and the `rules:` map (per-artifact rules applied during artifact generation). Prefer this over a standalone `openspec/specs/project-constitution/spec.md` file, because `config.yaml` content is auto-injected into future artifact generation without requiring the workflow skill to read it explicitly.

Template to propose to the user:

```yaml
schema: spec-driven

context: |
  # Existing project context lines stay above
  
  Project constitution (cross-cutting rules — apply to EVERY change):
  
  1. <rule one — what it requires + origin reference e.g. "from 2026-04-10 review of <feature>">
  2. <rule two>

rules:
  proposal:
    - <per-artifact rule if applicable>
  design:
    - <per-artifact rule>
  tasks:
    - <per-artifact rule>
```

Then ask:
```
The following cross-cutting rules were identified during review
and should be added to openspec/config.yaml:
- [list items with proposed wording]

Would you like me to update config.yaml now?
```

If the user declines or the project has a different constitution location (e.g. a separate CLAUDE.md or CONTRIBUTING.md), honour that — the point is that constitution rules are tracked SOMEWHERE persistent, not that the location is rigid.

### Step 6e: Cross-project extraction (if applicable)

If user maintains a shared-specs repository, ask:
```
This feature's final spec may be useful for other projects.
Should I extract the reusable portions to shared-specs?
```

---

## Decision Quick Reference

| Situation | Tool | Action |
|-----------|------|--------|
| Project not initialized | OpenSpec | `openspec init .` (no `--here` flag) |
| New feature/change | OpenSpec | `/openspec-propose <name>` or `openspec new change <name>` |
| Refine requirements | OpenSpec | Edit `openspec/changes/<name>/proposal.md` and `specs/<capability>/spec.md` |
| Deep design thinking | Superpowers | `/brainstorming` → OVERWRITE `openspec/changes/<name>/design.md` |
| Task breakdown | Superpowers | `/writing-plans` → OVERWRITE `openspec/changes/<name>/tasks.md` |
| Write code | Superpowers | `/executing-plans` with TDD (`/subagent-driven-development` when the tasks are independent) |
| Code review feedback | Neither | Record in `openspec/changes/<name>/review-notes.md`, fix code only |
| Before archive | OpenSpec | Reconcile specs (clean rewrite — NOT incremental patches) |
| Validate during authoring | OpenSpec | `openspec validate <name> --strict` |
| Archive completed work | OpenSpec | `/openspec-archive-change <name>` or `openspec archive <name> --yes` |
| Cross-cutting constitution rules | OpenSpec | Update `openspec/config.yaml` `context:` / `rules:` (NOT the feature spec) |
| Bug fix (small, no spec impact) | Superpowers | Direct fix with TDD, skip OpenSpec entirely |
| Bug fix (behavioural, spec impact) | OpenSpec | `openspec new change <bugfix-name>`, then Superpowers for fix |

## Anti-Patterns (NEVER do these)

- ❌ Run Superpowers brainstorming WITHOUT feeding OpenSpec's proposal as context
- ❌ Let Superpowers create its own design file separate from OpenSpec's design.md
- ❌ Modify spec files during code review (Phase 5)
- ❌ Patch specs incrementally instead of clean rewrite during reconciliation
- ❌ Archive without reconciling review-notes.md first
- ❌ Put [CONSTITUTION] items into the feature's spec files
- ❌ Skip Phase 2 brainstorming and go straight to implementation
- ❌ Modify tasks.md during reconciliation (it's execution history)
- ❌ Carry on past a gate-check `stop` (exit 10, or exit 1 twice) without the user's approval
- ❌ Downgrade a `[needs user]` item to `[default]` so that gate-check proceeds (only the user's own delegation does that)
