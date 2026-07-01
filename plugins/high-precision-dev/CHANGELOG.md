# Changelog

All notable changes to the `high-precision-dev` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-07-01

### Changed

- **Honest reframe of the error-rate claim.** The `p→p⁴` figure is demoted from a headline guarantee to an idealized model with an explicit correlation caveat, everywhere it appeared (`plugin.json`, `marketplace.json`, `README`, `commands/start.md`, `references/ANTI-PATTERNS.md`). A `/debate` re-examination (`docs/loop-design-review-2026-07-01.md` §8) source-verified that the four "independent" channels share one base model plus the same `SPEC.md` / `CONSENSUS.md`, so their errors are correlated exactly where it matters (systematic misreadings). The real, unquantified value is role-diverse adversarial review, bounded below by a shared-model correlation floor.
- **`implementer-a` and `implementer-b` given genuinely different approaches** — they were previously byte-identical except the A/B label, which made the a-vs-b leg the weakest form of independence (identical prompts + same model = correlated systematic errors; worktree isolation stops plagiarism, not correlated independent error). A now works **spec-first / top-down** (enumerate every SPEC requirement + boundary, structure code around the spec, defensive checks first); B works **test-first / behavior-driven** (write failing tests from the SPEC's scenarios, then minimal code to pass). Same completeness bar (every requirement + boundary), different path — so Phase 3/4 disagreements carry decorrelated information instead of shared blind spots. `ANTI-PATTERNS.md` AP-1 updated accordingly.

## [1.3.0] - 2026-07-01

### Added

- **Controller-run environmental test gate before Phase 4 completes.** `commands/start.md` Phase 4 now has the controller actually run the SPEC test suite and capture its exact exit code (`WF_TEST_EXIT=$?`) after the verifier produces the merged implementation — turning "tests pass" from an agent prose *claim* into an environmental *fact*. A non-zero exit routes into the existing capped fix-loop as an additional exit condition (same 3-iteration cap → `AskUserQuestion`); unparseable output fails closed. `agents/verifier.md` now requires the unit tests to be actually runnable and records the exit code in VERIFICATION.md.
- Deliberately a **controller-assembled environmental check** (reads an exit code): it does **not** reintroduce a structured-output contract or the removed L2/L3 framework. It is the single gate satisfying the rule "a gate is justified iff (a) it reads an environmental fact (not an agent assertion) **and** (b) a downstream consumer acts on it" — here (a) the test exit code, (b) the capped fix-loop's exit condition. Outcome of a `/debate` re-examination of the 1.2.0 L2 removal; see `docs/loop-design-review-2026-07-01.md`.

## [1.2.1] - 2026-07-01

### Fixed

- **`/start` no longer advertises a `--phase N` argument it never implemented.** `commands/start.md`'s `argument-hint` listed `[--phase N]`, but the body only ever reads `$ARGUMENTS` as the SPEC.md path. Removed the misleading hint (resume-from-phase can be added later; until then the hint no longer promises a non-feature).

### Notes

- Investigated (no code change needed) `disproof-agent` not appearing in a session's registered agent types: `agents/disproof-agent.md` is structurally identical to the sibling agents that do register (same frontmatter shape, name derived from filename), so it is not a file defect — it was added in PR #4 (`893821c`) without a version bump, so a registry keyed off version/reload did not re-scan it. The 1.2.0 bump plus a reinstall/reload resolves it.

## [1.2.0] - 2026-07-01

### Removed

- **The 1.1.0 machine-checkable output contract (`schema/findings.schema.json`, `schema/coverage.schema.json`, `validators/validate-high-precision-output.cjs`, and its fixtures) is removed.** A same-day design review (`docs/loop-design-review-2026-07-01.md`) found it was never wired into the live `/start` flow — the six agents emit prose reports (`IMPL_A_REPORT.md`, `CRITIQUE.md`, `ATTACKS.md`, `DISPROOF.md`, `VERIFICATION.md`), so the validator only ever checked a JSON shape that no agent produced (validated against fixtures in CI, never against real output). This plugin's rigor comes from its epistemic division of labor — two worktree-isolated independent implementers, plus critic / adversary / disproof / verifier with a capped fix loop — not from a structural JSON contract. Rather than complete a high-effort producer step for near-zero marginal rigor, the dead contract is removed. `agents/disproof-agent.md` (also added in 1.1.0) is unaffected and stays.

### Notes

- Selective-consolidation decision: `code-audit-rigor`'s live validators are kept (they gate the routine review commands and check a real coverage invariant), `openspec` and `multi-agent-debate` contracts are kept/completed, and this plugin's unwired contract is removed. Rationale and per-plugin gap analysis in `docs/loop-design-review-2026-07-01.md`.

## [1.1.0] - 2026-07-01

### Added

- **Durable, machine-checkable output contract for `/start`.** New `schema/findings.schema.json` + `schema/coverage.schema.json` and a zero-dependency validator (`validators/validate-high-precision-output.cjs`) — the 4-agent verify pass (implementer-a/b, critic, adversary, verifier) now produces a structured, schema-validated result instead of relying on prompt discipline alone, enforced repo-wide via GitHub Actions CI and a PostToolUse hook.
- `agents/disproof-agent.md` — a new adversarial agent role for the verify phase.

### Notes

- This release was previously merged (commit `893821c`, PR #4) without a corresponding version bump on `plugin.json` / `marketplace.json` or a changelog entry — the plugin had no `CHANGELOG.md` at all until now. This entry backfills the version and changelog for that change; no further code changes were made.

## [1.0.0] - 2026-03-06

### Added

- Initial release: high-precision multi-agent development mode, compressing single-agent error rate from `p` to `p^4` through epistemic division of labor.
- `/init` — initialize `SPEC.md` / `CONSENSUS.md` templates in a project.
- `/start` — 4-phase workflow: independent implementer-a/b → critic → adversary → verifier reconciliation against `SPEC.md`.
- `references/ANTI-PATTERNS.md`, `references/ATTACK-CLASSES.md` — supporting guidance for the critic/adversary roles.
