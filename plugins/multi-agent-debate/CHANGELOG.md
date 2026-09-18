# Changelog

All notable changes to the `multi-agent-debate` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] - 2026-09-18

### Added

- **`/debate` machine-checks that `debate-output.json` is git-ignored.** The same three-state step `code-audit-rigor` 2.0.4 gained, added in the same pass: `git check-ignore -q -- <artifact>; echo "check-ignore rc=$?"` — `0` ignored → continue; `1` not ignored → ask `git ls-files --error-unmatch` whether it is already tracked (then `git rm --cached` first) before telling the user to add the line; `128` → skip. The `rc` must be echoed: `-q` prints nothing and a trailing `; RC=$?` assignment exits 0 itself, collapsing all three states into one indistinguishable "exit 0, no output". `prior-debate.json` is deliberately outside this check — it is the next run's input, not a throwaway artifact, so whether it is version-controlled is the project's call.

  **Why:** this artifact is the evidence that "each project just adds one line" does not happen on its own — the plugin's own repo never ignored it, while the sibling `/review-branch` artifact got its line only on 2026-09-18. Fixing just the sibling would have left the demonstrated gap open, so both commands were changed together.

## [1.2.0] - 2026-07-01

### Added

- **The 1.1.0 output contract is now wired into the live `/debate` flow.** A same-day design review (`docs/loop-design-review-2026-07-01.md`) found the schema/validator was fixture-tested in CI but never invoked during an actual debate — Phase 5.5 only read the validator *agent's* prose verdict. `commands/debate.md` Phase 6 now has a **6a structural gate**: assemble `debate-output.json` and run `validate-debate-output.cjs` before the final Markdown output, complementing Phase 5.5's semantic verdict. A structural failure routes back to Phase 2 (same as a Phase 5.5 `rejected`); tool-unavailability must be surfaced, never silently skipped.
- **Cross-field referential integrity in `validate-debate-output.cjs`.** The validator now checks that `finalDecision.selectedProposal` and every `consensus.agreedProposals` entry point at a real `proposals[].id` — catching a decision that names a proposal which was never made (an id typo, or a stale id after rounds renumbered proposals), a class of error no per-field check can catch. Two new mutation cases cover both branches.
- **Coverage declaration schematized and machine-checked.** `debate-output.json` gains a required `coverage` field (`covered[{aspect, summary}]` / `notCovered[{aspect, reason}]`, mirroring `prior-debate`'s shape). The validator enforces it, so a debate can no longer silently drop its coverage account and every uncovered aspect must carry a `reason`; `commands/debate.md` Phase 6's Coverage Declaration table now derives from this field. Four new mutation cases.

### Changed

- **Convergence criteria reconciled between `commands/debate.md` and `agents/orchestrator.md`.** `orchestrator.md` maintained a third convergence heuristic (a single proposal leading by ≥8 points) that Phase 4 in `debate.md` never listed. Phase 4 now states all convergence conditions with explicit precedence (≥2-agent consensus **or** ≥8-point score gap → converge), so the routing table matches what the orchestrator actually maintains.

## [1.1.0] - 2026-07-01

### Added

- **Durable, machine-checkable output contracts for `/debate`.** New `schema/debate-output.schema.json` and `schema/prior-debate.schema.json`, each with a zero-dependency validator (`validators/validate-debate-output.cjs`, `validators/validate-prior-debate.cjs`) — the orchestrator/perspective/critic/validator pipeline now produces a structured, schema-validated result instead of relying on prompt discipline alone. `prior-debate` (loading an earlier debate's context) is promoted from an ad-hoc convention to a fully validated contract. Enforced repo-wide via GitHub Actions CI and a PostToolUse hook.

### Notes

- This release was previously merged (commit `893821c`, PR #4) without a corresponding version bump on `plugin.json` / `marketplace.json` or a changelog entry — the plugin had no `CHANGELOG.md` at all until now. This entry backfills the version and changelog for that change; no further code changes were made.

## [1.0.0] - 2025-12-19

### Added

- Initial release: multi-agent debate system for exploring a decision from multiple perspectives before converging on a recommendation.
- `/debate` — orchestrator analyzes the question and assigns three distinct perspectives (perspective-a/b/c), a critic challenges each proposal, and a validator synthesizes the final recommendation.
- `references/ANTI-PATTERNS.md`, `references/CRITIQUE-METHODOLOGY.md` — supporting guidance for the critic role.
