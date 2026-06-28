# Changelog

All notable changes to the `security-audit` plugin will be documented in this file.

## [1.0.0] - 2026-06-29

### Added

- **Initial release.** Vendored the `security-audit` skill from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT, © Cloudflare, Inc.) at upstream commit `4de1ac80123057dd73c586cd3862a6c85a2b8a5e`.
  - Six-phase audit pipeline (recon → hunt → validate → report → structured output → independent verification) driven by parallel sub-agents, finding exploitable vulnerabilities with real impact.
  - Bundled assets under `skills/security-audit/`: `SKILL.md`, methodology references (`RECONNAISSANCE.md`, `HUNTING.md`, `ATTACK-CLASSES.md`, `VALIDATION-AND-REPORTING.md`), `report-schema.json`, the zero-dependency `validate-findings.cjs` validator, and the upstream `LICENSE`.
  - Vendored files are copied verbatim; the wrapper adds only `plugin.json` and `README.md`, which documents the Claude Code platform mapping (research → `Explore`, general → `general-purpose`) and how this plugin complements `code-audit-rigor`.
