---
name: openspec-superpowers-workflow
description: MUST use whenever the user proposes / adds / refines a feature, runs any /opsx:* or openspec CLI command, mentions OpenSpec changes, asks to brainstorm design / plan tasks / implement a spec'd feature, handles PR review feedback on a spec'd feature, or asks to reconcile / archive a completed change — also trigger whenever an `openspec/changes/<name>/` folder is present in the current conversation. SKIP this skill only when the change is single-module with clear acceptance criteria and touches none of: public API / data contract / schema / migration / backward compatibility / security or permission boundaries / concurrency or consistency / cross-module behavior — use bare superpowers skills there; judge by contract risk, not LOC or file count. A SKIP decision is valid only when the reply enumerates all eight surfaces with per-surface verdicts — an unstated skip is a workflow violation; behavior already covered by `openspec/specs/` almost always has spec impact (the skip-gate hook denies the first code edit once to force this check). Enforces strict role separation between OpenSpec (spec lifecycle, the WHAT) and Superpowers (dev discipline, the HOW) across six phases. Forbids modifying spec files during code review (Phase 5), forbids Superpowers creating sidecar design/plan files outside OpenSpec's location, forbids incremental spec patching (Phase 6 must be a clean rewrite), and forbids putting [CONSTITUTION] items into a feature's spec. Read phases.md for the full phase-by-phase playbook before acting.
---

# OpenSpec + Superpowers Integration

> **Activation reminder (for Claude):** if you are reading this file, you have already identified a feature-development task that falls under this skill's trigger. Follow the Phase identification and the six non-negotiable rules below before taking any action. Do NOT fall back to "default" behaviour — the whole point of this skill is that OpenSpec and Superpowers have distinct, non-overlapping responsibilities, and mixing them silently is the failure mode this skill exists to prevent.

Two tools, **never overlapping**:
- **OpenSpec** = spec lifecycle (WHAT to build, source of truth)
- **Superpowers** = dev discipline (HOW to build, quality enforcement)

## When this skill applies

Trigger on any of:
- "new feature", "propose", "add feature", `/opsx:propose`, `/opsx:archive`, `openspec new change`, `openspec archive`
- "brainstorm", "refine design", "plan tasks", "break down work"
- "implement", "start coding", "execute" — when an `openspec/changes/<name>/` folder exists
- PR review feedback on a feature that has an `openspec/changes/<name>/` folder
- "reconcile", "archive" for a completed change

If none of these apply (e.g. a one-off bug fix with no spec impact), this skill does NOT apply — just fix with TDD directly.

## Prerequisites

Before acting, verify OpenSpec availability and project state:
- `which openspec` — is the CLI installed?
- `ls .claude/commands/opsx/ 2>/dev/null` — are the `/opsx:*` slash commands installed?
- `ls openspec/ 2>/dev/null` — is the project initialized?

If the project is not initialized, run `openspec init .` (note: use `.` for the current directory — no `--here` flag exists). See `phases.md` → "Prerequisites & Conventions" for the CLI ↔ slash-command substitution table.

## Phase map (quick reference)

| Phase | Lead | Output |
|---|---|---|
| 1. Spec definition | OpenSpec | `proposal.md`, `specs/` (user approves) |
| 2. Design refinement | Superpowers `brainstorming` | OVERWRITES `design.md` |
| 3. Task planning | Superpowers `writing-plans` | OVERWRITES `tasks.md` |
| 4. Implementation | Superpowers `subagent-driven-development` / `executing-plans` + TDD | code |
| 5. Review & fix | neither — record in `review-notes.md`, fix code only | `review-notes.md` entries |
| 6. Reconcile & archive | OpenSpec | clean-rewritten specs, reconciliation criteria gate, `/opsx:archive` |

## Non-negotiable rules

1. **Never modify spec files during Phase 5 code review.** All feedback → `review-notes.md` with `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag + Y/N.
2. **Never create separate Superpowers design/plan files.** Outputs OVERWRITE OpenSpec's `design.md` / `tasks.md` in place.
3. **Phase 6 reconciliation = clean rewrite**, not incremental patches. Goal: specs read as if you knew everything from the start.
4. **`tasks.md` is never modified during reconciliation** — it's execution history.
5. **`[CONSTITUTION]` items never go into the feature's spec** — they go to the project constitution separately.
6. **TDD in Phase 4 is mandatory.** Tests before implementation, always.

## How to use this skill

1. Identify which phase the user is in — read `PHASE-IDENTIFICATION.md` when this is a new OpenSpec workflow, the request may span multiple phases, an `openspec/changes/<name>/` folder exists but status is unclear, or the phase is ambiguous.
2. Read `phases.md` for the detailed playbook of that phase — includes exact actions, sync-back rules, review-notes.md format, and anti-patterns.
3. For Phase 2/3/4 handoffs where Superpowers produces design/tasks/code, read `SUPERPOWERS-HANDOFF.md` before syncing back to OpenSpec.
4. Follow it exactly. If switching phases mid-conversation, re-read the relevant section.

See `phases.md` for: full Phase 1-6 actions, `review-notes.md` tag semantics and examples, decision quick-reference table, and the anti-patterns list. See `RECONCILIATION-CRITERIA.md` for the Phase 6 pre-archive gate checklist. See `PHASE-IDENTIFICATION.md` for the phase decision tree. See `SUPERPOWERS-HANDOFF.md` for sync-back templates and sidecar-file anti-patterns. See `OUTPUT-CONTRACTS.md` for the durable output contract per phase, coverage definitions, valid/invalid requirement-writing examples, and the deferred-item convention.
