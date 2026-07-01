# Changelog

All notable changes to the `high-precision-dev` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
