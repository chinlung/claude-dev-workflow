# OpenSpec + Superpowers Integration Workflow

## Overview

This project uses **two complementary tools** with strict role separation:
- **OpenSpec** = Spec lifecycle management (WHAT to build, source of truth)
- **Superpowers** = Development discipline (HOW to build, quality enforcement)

They NEVER overlap. Follow the phase sequence below for every feature.

---

## Prerequisites & Conventions

### Tool availability — CLI vs slash command

Two interfaces to OpenSpec exist, and the project may have either, both, or neither:

- **`openspec` CLI** — installed globally via npm (`@fission-ai/openspec`). Commands: `openspec new change <name>`, `openspec status --change <name> --json`, `openspec instructions <artifact> --change <name> --json`, `openspec validate`, `openspec archive <name>`, `openspec list`.
- **`/opsx:*` slash commands** — project-local prompt expansions at `.claude/commands/opsx/*.md`. These are NOT built in; they ship with an OpenSpec init for Claude Code and wrap the CLI with a scripted workflow. Typical members: `/opsx:propose`, `/opsx:apply`, `/opsx:archive`.

**How to tell which is available**:
```bash
which openspec                        # CLI present?
ls .claude/commands/opsx/ 2>/dev/null  # slash commands present?
ls openspec/ 2>/dev/null               # project initialized?
```

If the project is not initialized, run `openspec init .` first (note: no `--here` flag — use `.` or an explicit path).

**Command substitution table** — when `/opsx:*` is unavailable, use the CLI equivalents:

| Slash command | CLI equivalent |
|---|---|
| `/opsx:propose <name>` | `openspec new change <name>` then loop through `openspec instructions <artifact-id> --change <name> --json` to fill each artifact |
| `/opsx:apply` (or start implementation) | no direct CLI equivalent — proceed to Phase 4 manually |
| `/opsx:archive <name>` | `openspec archive <name> --yes` |

### Path convention

After `openspec init`, the working directory is `openspec/`, not the project root. **All "changes/..." paths in this document are shorthand for `openspec/changes/...`**. Concretely:

- Active change folder: `openspec/changes/<feature-name>/`
- Archived change folder: `openspec/changes/archive/<YYYY-MM-DD>-<feature-name>/` (archive auto-prefixes with the archive date)
- Canonical spec source of truth: `openspec/specs/<capability>/spec.md` (populated when a change is archived)
- Project config / constitution: `openspec/config.yaml`

### Spec writing gotcha (learned from real runs)

The OpenSpec validator enforces that **every `### Requirement:` block MUST contain the word `SHALL` or `MUST` in its first paragraph** (the paragraph immediately after the header, before any bullet list or sub-heading). Putting normative keywords in a later paragraph or bullet will make `openspec validate --strict` reject the requirement with `ADDED "<name>" must contain SHALL or MUST`. When writing or rewriting specs in Phase 1 / 2 / 6, always lead each requirement with a MUST/SHALL sentence, then follow with bullets or details.

---

## Phase 1: Spec Definition (OpenSpec leads)

**Trigger**: User says "new feature", "propose", "add feature", or runs `/opsx:propose`

**Actions**:
1. Run `/opsx:propose <feature-name>` (or `openspec new change <feature-name>` if the slash command is not installed — see Prerequisites) to create `openspec/changes/<feature-name>/`
2. Using `openspec instructions <artifact-id> --change <feature-name> --json`, generate each artifact in dependency order:
   - `proposal.md` — the "why" and capability list (**primary user-reviewed artifact**)
   - `specs/<capability>/spec.md` — requirements with SHALL/MUST + scenarios (**primary user-reviewed artifact**, one file per capability listed in proposal)
   - `design.md` — **placeholder draft only**; Phase 2 will overwrite it entirely. Write a minimal stub noting it is a draft
   - `tasks.md` — **placeholder draft only**; Phase 3 will overwrite it entirely. Write a minimal stub noting it is a draft
3. Create empty `review-notes.md` in the same folder for Phase 5 to populate later (OpenSpec does not generate this — do it with `Write`)
4. Run `openspec validate <feature-name>` to catch SHALL/MUST violations and scenario-format errors (see Prerequisites → Spec writing gotcha)

**Quality gate**: User reviews and approves `proposal.md` and `specs/<capability>/spec.md` only.
`design.md` and `tasks.md` are initial drafts — they WILL be overwritten in Phase 2-3. Do NOT ask the user to review them in Phase 1.

**Do NOT proceed to Phase 2 until user explicitly approves requirements.**

---

## Phase 2: Design Refinement (Superpowers leads → sync back to OpenSpec)

**Trigger**: User approves Phase 1 requirements, or says "brainstorm", "refine design"

**Actions**:
1. Activate Superpowers `/brainstorming` skill
2. Use `openspec/changes/<feature-name>/proposal.md` and `specs/` as input context
3. Conduct Socratic questioning to refine:
   - Boundary conditions and error handling
   - Impact on existing system
   - Performance and scalability concerns
   - Security considerations
4. Produce a refined design document

**Sync back (CRITICAL)**:
After brainstorming completes, OVERWRITE `openspec/changes/<feature-name>/design.md` with the refined design.
- Keep OpenSpec's file structure and location
- Replace content with Superpowers brainstorming output
- Preserve any OpenSpec-specific metadata/headers if present

**Do NOT create a separate Superpowers design file. The design lives in OpenSpec's structure.**

---

## Phase 3: Task Planning (Superpowers leads → write to OpenSpec location)

**Trigger**: User approves Phase 2 design, or says "plan tasks", "break down work"

**Actions**:
1. Activate Superpowers `/writing-plans` skill
2. Use the updated `openspec/changes/<feature-name>/design.md` as input
3. Break work into 2-5 minute granularity tasks with:
   - Exact file paths
   - Complete implementation details
   - Verification steps per task
4. OVERWRITE `openspec/changes/<feature-name>/tasks.md` with the Superpowers plan

**Do NOT create a separate plan file. Tasks live in OpenSpec's tasks.md.**

**Quality gate**: User reviews task breakdown before proceeding to implementation.

---

## Phase 4: Implementation (Superpowers leads exclusively)

**Trigger**: User approves Phase 3 tasks, or says "implement", "start coding", "execute"

**Actions**:
1. Activate `/subagent-driven-development` or `/executing-plans`
2. Create git worktree for isolated development
3. For each task:
   - Write test first (RED)
   - Implement to pass test (GREEN)
   - Refactor (REFACTOR)
4. Two-stage review per task:
   - Stage 1: Spec compliance — does it match design.md?
   - Stage 2: Code quality — is it well-written?

**Rules**:
- TDD is mandatory. Never write implementation before tests.
- If a task fails two-stage review, fix it before moving to the next task.
- Do NOT modify any spec files during implementation.

---

## Phase 5: Review & Feedback (Tool-neutral — human-driven)

**Trigger**: Implementation complete, PR submitted, code review begins

**Rules — STRICTLY ENFORCED**:

### What to do with review feedback:
- Fix the code as requested by reviewers
- Record ALL feedback in `openspec/changes/<feature-name>/review-notes.md`
- **NEVER modify spec files** (proposal.md, specs/, design.md, tasks.md) during review

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
  → Mark N (code-only, no spec update needed)
- `[CONSTITUTION]` — Cross-cutting concern that applies to ALL features
  → Mark Y (needs constitution update, NOT this feature's spec)

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

---

## Phase 6: Reconcile & Archive (OpenSpec leads)

**Trigger**: All reviews passed, all code fixes merged, user says "reconcile" or "archive"

### Step 6a: Reconcile specs

Read `openspec/changes/<feature-name>/review-notes.md` and process only items marked **Y**:

1. **[REQUIREMENT] Y items** → Update `proposal.md` and `specs/`
2. **[DESIGN] Y items** → Update `design.md`
3. **[CONSTITUTION] Y items** → List separately for user to add to project constitution
   (Do NOT put these in the feature's spec files)

**CRITICAL RULE**: Do NOT patch incrementally. REWRITE clean versions as if you knew
all this information from the start. The goal is a spec that reads as a coherent document,
not a changelog with amendments.

**tasks.md is NEVER modified during reconciliation.** It is execution history.

### Step 6b: User confirms reconciled specs

Present the rewritten spec files for user review before archiving.

### Step 6c: Archive

Run `/opsx:archive <feature-name>` (or `openspec archive <feature-name> --yes` if the slash command is not installed) to:
- Merge final requirements into `openspec/specs/<capability>/spec.md` (OpenSpec source of truth)
- Move the change folder to `openspec/changes/archive/<YYYY-MM-DD>-<feature-name>/` — the archive command auto-prefixes with the archive date, so the folder name is NOT just the feature name
- `review-notes.md` is preserved inside the archive for historical reference
- Note: archive will warn if tasks.md has incomplete items (`Warning: N incomplete task(s) found`); this is expected when Phase 4 was partially skipped or done out-of-band — use `--yes` to proceed

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
| New feature/change | OpenSpec | `/opsx:propose <name>` or `openspec new change <name>` |
| Refine requirements | OpenSpec | Edit `openspec/changes/<name>/proposal.md` and `specs/<capability>/spec.md` |
| Deep design thinking | Superpowers | `/brainstorming` → OVERWRITE `openspec/changes/<name>/design.md` |
| Task breakdown | Superpowers | `/writing-plans` → OVERWRITE `openspec/changes/<name>/tasks.md` |
| Write code | Superpowers | `/subagent-driven-development` with TDD |
| Code review feedback | Neither | Record in `openspec/changes/<name>/review-notes.md`, fix code only |
| Before archive | OpenSpec | Reconcile specs (clean rewrite — NOT incremental patches) |
| Validate during authoring | OpenSpec | `openspec validate <name> --strict` |
| Archive completed work | OpenSpec | `/opsx:archive <name>` or `openspec archive <name> --yes` |
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
