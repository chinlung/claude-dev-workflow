# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
