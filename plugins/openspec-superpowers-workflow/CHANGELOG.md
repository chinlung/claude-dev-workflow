# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-08-13

### Added

- **skip-gate PreToolUse hook — the implicit SKIP decision is machine-forced into an explicit, auditable procedure** (new enforcement surface, hence minor bump). A real session skipped the whole workflow by eyeballing a one-line CLAUDE.md summary ("no contract surfaces → bare superpowers") while the change actually touched cross-module behavior documented in the canonical spec, in an already-spec'd capability domain — the 1.3.0 rubric was in context and still lost to rationalization, because skipping happens by *not acting* and leaves no artifact to check. The hook closes the gap at the moment of the mistake: on the session's first Edit/Write in a project that has `openspec/` but no active change under `openspec/changes/` (`archive/` doesn't count), it denies the edit once and demands a per-surface verdict on all eight contract surfaces before retrying. Scope guards: paths under `openspec/` and `.claude/` are exempt (writing proposals/specs IS workflow work), as are paths outside the project; fully fail-open (missing jq, malformed input, unknown tool shapes all allow) — the gate forces the judgment to happen and leave a trace, it does not judge contract risk itself. A 5-second batch window keeps sibling edits from the same parallel tool batch behind the gate (cross-vendor review caught that a bare once-per-session flag lets every edit after the first sail through when the session opens with a multi-file batch); path exemptions are evaluated before the window so legitimate same-batch `openspec/` writes are never denied. Ships with a 20-assertion fixture suite (`tests/skip-gate.test.sh`) wired into CI; flag dedupe, archive exclusion, and path exemption are each mutation-verified to break a distinct assertion, and the session_id path-sanitization case doubles as a fail-open regression guard (an unsanitized `/` in the id silently disabled the whole gate via a failed `touch`).

### Changed

- **SKIP clause proceduralized: an unstated skip is now a workflow violation.** The frontmatter description (the site where the auto-trigger skip decision is actually made) now requires the reply to enumerate all eight surfaces with explicit per-surface verdicts, and adds the strongest concrete signal the incident exposed: a behavior change in a capability domain already covered by `openspec/specs/` almost always has spec impact — a checkable environment fact that outranks free-form judgment. `PHASE-IDENTIFICATION.md` Case 3 gains the same SKIP 判定程序, 絕對禁止事項 gains the corresponding ❌, and the README documents the hook and its boundaries. The SKIP block sits ahead of the role-separation elaboration inside the description: the runtime truncates skill descriptions both per-skill (1536-char cap) and under an aggregate listing budget (`skillListingBudgetFraction`), so the load-bearing invariant must not live at the truncatable tail.

## [1.3.1] - 2026-08-08

### Changed

- **Review-notes tagging criterion made explicit: tag by fix-landing artifact, not problem nature.** `phases.md`'s Tags section described `[REQUIREMENT]`/`[DESIGN]` by the *kind* of problem ("wrong behavior" vs "architecture change"), while `RECONCILIATION-CRITERIA.md` C1 routes strictly by *artifact destination* ([DESIGN] may never touch `specs/`). The two axes diverge for one recurring class: a deliberate design decision whose conflicting text lives in a spec scenario's literal wording — by nature it feels like `[DESIGN]`, but the file that must change is the spec, so the correct tag is `[REQUIREMENT]`. Surfaced in a real Phase 6 run where two such items had to be re-tagged at the gate; the silent-failure mode this prevents is worse: honoring a mis-tag by skipping the spec edit archives a spec-vs-implementation divergence into `openspec/specs/` as permanent wrong truth. `phases.md` now states the criterion at the tag-writing site (Phase 4/5, where context is fresh), and C1 gained a 修正路徑 paragraph institutionalizing the re-tag-with-note recovery instead of leaving it to improvisation.

## [1.3.0] - 2026-07-26

### Changed

- **SKIP clause sharpened from vague to contract-risk rubric** (trigger-behavior change, hence minor bump). The frontmatter description's skip criterion was "small bug fixes with no spec impact" — undefined, and "small" invites judging by LOC / file count, which are the wrong proxies. It now enumerates the contract surfaces whose absence permits skipping: public API / data contract / schema / migration / backward compatibility / security or permission boundaries / concurrency or consistency / cross-module behavior — with an explicit "judge by contract risk, not LOC or file count". Single-module changes with clear acceptance criteria and none of those surfaces route to bare superpowers skills. Rationale: this is where the auto-trigger skip decision is actually made, so the rubric belongs in the description (self-contained for every installer) rather than in any one user's global CLAUDE.md.
- `PHASE-IDENTIFICATION.md` Case 3's 判斷標準 now lists the same contract-surface signals alongside the SHALL/MUST test; root README's when-NOT-to-use line synced to the same language.

## [1.2.2] - 2026-07-02

### Changed

- **Phase 1 pre-check path unified to `${CLAUDE_PLUGIN_ROOT}`.** `phases.md` step 4 previously used a repo-relative path (`node skills/openspec-superpowers-workflow/validators/…`) with a prose "resolve it from where the skill is installed" note; it now uses `${CLAUDE_PLUGIN_ROOT}/skills/…`, matching the convention every other plugin's commands/skills use (verified available in the skill bash context). Makes the pre-check runnable as-written regardless of the caller's working directory.

## [1.2.1] - 2026-07-01

### Added

- **Phase 1 gained an optional, lenient local pre-check.** `phases.md` Phase 1 now suggests running the bundled `validate-openspec-workflow.cjs` on the change folder to catch a missing artifact (any of `proposal.md` / `design.md` / `tasks.md` / `review-notes.md`, or no `specs/**/spec.md`) or an empty SHALL/MUST first paragraph *before* the authoritative `openspec validate --strict` — fast and needs no OpenSpec install. Explicitly a pre-check, not a substitute for the strict CLI. From the loop-design review (`docs/loop-design-review-2026-07-01.md`), which noted the plugin's own validator was CI-only and never surfaced in the live workflow.

## [1.2.0] - 2026-07-01

### Added

- **Durable, machine-checkable output contract for the workflow.** New `skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs` (zero-dependency) plus reference docs `OUTPUT-CONTRACTS.md`, `RECONCILIATION-CRITERIA.md`, and `PHASE-IDENTIFICATION.md` — formalizing what was previously prompt-only guidance (Phase 5 reconciliation criteria, Phase 6 archive discipline) into an explicit, testable contract, enforced repo-wide via GitHub Actions CI and a PostToolUse hook.
- `SUPERPOWERS-HANDOFF.md` — documents the Phase 2-4 handoff contract to Superpowers skills (`brainstorming`, `writing-plans`, `subagent-driven-development`).

### Notes

- This release was previously merged (commit `893821c`, PR #4) without a corresponding version bump on `plugin.json` / `marketplace.json` or a changelog entry — the plugin sat at `1.1.0` both before and after a functional (non-doc) change. This entry backfills the version and changelog for that change; no further code changes were made.

## [1.1.0] - 2026-06-17

### Changed
- **Phase 4 playbook realigned to Superpowers 6.0.0.** `phases.md` Phase 4 previously documented a per-task *two-stage* review (Stage 1 spec compliance, Stage 2 code quality). Superpowers 6.0 merged these into a single `task-reviewer` that returns both verdicts in one pass — plus a "can't verify from the diff" verdict — followed by one whole-branch review at the end on the most capable model. The playbook now matches the actual `subagent-driven-development` flow instead of describing the retired two-reviewer design.
- **Worktree location note added to Phase 4.** Superpowers 6.0 removed the legacy global `~/.config/superpowers/worktrees/`; worktrees now live in the project under a local worktree *root* — `.worktrees/` by default (or an existing `.worktrees/`/`worktrees/`), with each worktree created under it at `<root>/<branch>` rather than at the root itself. Phase 4 now reminds you to keep that root git-ignored.
- **Reviewer-integrity rules added to Phase 4.** Findings may not be suppressed and severity may not be pre-rated, mirroring Superpowers 6.0's guard against a controller coaching the reviewer; a plan-mandated defect is surfaced for the human to decide on.

### Notes
- Requires **Superpowers >= 6.0.0** for the Phase 4 behaviour described above. Earlier Superpowers still works but runs the legacy two-reviewer, task-by-task flow.
- No behavioural change to Phases 1-3, 5, 6. This release only realigns documentation with the upstream SDD rewrite.

## [1.0.1] - 2026-04-10

### Changed
- **Stronger auto-trigger guarantees**: `SKILL.md` frontmatter `description` rewritten with imperative "MUST use" wording, expanded trigger list (now also matches `openspec CLI` commands and the presence of `openspec/changes/<name>/` folders), and explicit forbidden-behaviours enumeration (no spec modification in Phase 5, no sidecar design/plan files, no incremental spec patching in Phase 6, no `[CONSTITUTION]` items in feature specs). This removes the need for users to add a separate "must call this skill" reminder in their own `CLAUDE.md`, because the same meta-instruction now ships with the plugin.
- Added an "Activation reminder" note at the top of `SKILL.md` body that anchors Claude on the non-negotiable rules before any action, mirroring the pattern used by `superpowers:using-superpowers`.

### Notes
- No change to `phases.md` — the detailed playbook is unchanged.
- Behavioural intent is unchanged from 1.0.0; this release strengthens the **likelihood** that Claude actually invokes the skill when it should.

## [1.0.0] - 2026-04-10

### Added
- Initial release
- `openspec-superpowers-workflow` skill with progressive disclosure (SKILL.md + phases.md)
- Six-phase feature development workflow:
  - Phase 1: Spec Definition (OpenSpec leads)
  - Phase 2: Design Refinement (Superpowers `brainstorming` → overwrites `design.md`)
  - Phase 3: Task Planning (Superpowers `writing-plans` → overwrites `tasks.md`)
  - Phase 4: Implementation (Superpowers `subagent-driven-development` + TDD)
  - Phase 5: Review & Feedback (records to `review-notes.md`, never modifies spec)
  - Phase 6: Reconcile & Archive (OpenSpec, clean rewrite discipline)
- Six non-negotiable rules enforcing strict role separation between OpenSpec and Superpowers
- `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag taxonomy with Y/N classification for Phase 5 feedback
- Clean-rewrite discipline for Phase 6 reconciliation (no incremental patches)
- `tasks.md` freeze rule during reconciliation (execution history, not current spec)
- Constitution routing to `openspec/config.yaml` `context:` / `rules:` fields (not feature specs)
- Prerequisites section documenting OpenSpec CLI vs `/opsx:*` slash-command alternatives
- `openspec init .` gotcha documented (no `--here` flag)
- Validator strictness gotcha documented (`SHALL`/`MUST` must appear in first paragraph of each `### Requirement:`)
- Archive folder date-prefix behaviour documented (`openspec/changes/archive/<YYYY-MM-DD>-<name>/`)
- Decision quick-reference table covering 13 common situations
- Anti-patterns list (8 items) covering the most frequent mistakes
