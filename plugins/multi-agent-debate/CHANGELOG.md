# Changelog

All notable changes to the `multi-agent-debate` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
