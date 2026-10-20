# Changelog

All notable changes to the `security-audit` plugin will be documented in this file.

## [2.0.0] - 2026-10-20

### Changed (BREAKING)

- **Re-vendored from upstream `f75f9a0` to `c1c8a8c` (`c1c8a8c1471069fb0e188eeaff69b8e8db6564a8`, 2026-09-14).** Every file under `skills/security-audit/` except `LICENSE` is byte-identical to upstream (`diff -r` clean). Upstream changes in that range:
  - **`findings.json` contract.** Records now have three verdicts — `confirmed`, `needs_validation`, `rejected` — and every record needs a `fingerprint`, a `trace`, and `evidence`. `execution.expected_result` became `execution.observed_result`, only `confirmed` records carry a severity, and overall severity cannot exceed the demonstrated impact. A `findings.json` written by 1.0.x fails the new validator (the old fixture here failed with 13 errors).
  - **Operating modes.** The skill is guidance by default; the full workflow (and any file creation) runs only on an explicit audit / pen-test request, a request for a full review, or a request for report artifacts. 1.0.x ran the full pipeline on any matching request.
  - **Workflow.** Phases are now reconnaissance → coverage-led hunting → candidate validation → structured output → independent record verification → target-neutral report (structured output moved ahead of the report). A deterministic `coverage-ledger.json`, checked by the new `validate-coverage-ledger.cjs`, records what was covered; runs take a `quick` / `standard` / `deep` profile and an optional agent-invocation budget, and end either complete with both validators passing or as `run_status: "incomplete"` with the reason.
  - **Execution safety.** Target code runs only inside an OS-enforced sandbox with no external network, an allowlisted empty environment, a read-only target, scratch-only writes, and resource limits; otherwise the lead stays `needs_validation`.
  - **Ten domain companions** added: AI/LLM, web protocol and auth, client-side, memory safety and binary, cloud and deployment, data isolation and lifecycle, desktop/mobile/local IPC, protocols/RPC/messaging, resource exhaustion, supply chain and release.
  - **Validators** hardened (input size and depth limits, no-follow reads, fatal UTF-8, sanitized error output) and shipped with test suites (65 tests). Both validators require only `fs`, `path`, and `util`; they make no network calls, spawn no processes, and write no files.

### Added

- **`tests/upstream.test.sh`** runs upstream's two test suites with `node --test`, and fails if either test file is missing. It runs in CI (`validate.yml`) and in the repo's PostToolUse hook. Verified to go red when a test file is deleted and when `validateDocument` accepts everything (15 of 65 tests fail).

### Changed

- **Fixture and mutations moved to the new contract.** `tests/fixtures/security-audit/valid-basic.json` now holds one record of each verdict. The mutations in `scripts/validate-fixtures.cjs` look records up by verdict instead of by index: the new fixture puts a `needs_validation` record at index 1, so the old `delete o[1].reason` deleted nothing and the suite flagged it. Added mutations for the new constraints — missing `fingerprint` / `evidence`, the old `expected_result` shape, severity above demonstrated impact, an unsafe evidence path, a severity on `needs_validation`, missing `blockers`, and a duplicate fingerprint. Each mutation now names the validator error it must produce (`expect`), so one that lands on the wrong record or trips a different rule fails instead of passing on any non-zero exit. `expect` cannot catch a mutation that trips its own rule and a second one: review found the first duplicate-fingerprint mutation also broke the sort order, so it would have stayed red with duplicate detection removed; it now gives the duplicate to the record next to the confirmed one, which keeps the order valid.
- **README.** Phase list, operating modes, verdicts, profiles, and companions follow upstream. The platform mapping now splits the `research` role: reconnaissance maps to `Explore`, while the coverage critic and the Phase 5 record verifier — which judge rather than locate — map to a read-only `general-purpose` agent. New notes: Claude Code's Bash sandbox does not meet the skill's execution controls on its own, the default output directory is outside what that sandbox lets commands write, and a run's output can quote secrets found in the target.

## [1.0.1] - 2026-07-02

### Added

- **Local drift protection for the vendored validator.** `tests/fixtures/security-audit/valid-basic.json` (a confirmed + a rejected finding, exercising both `oneOf` branches) plus single-field mutations wired into `scripts/validate-fixtures.cjs` — including the two semantic constraints unique to this validator (trace must start `entrypoint`, end `sink`). The repo-root suite + CI + PostToolUse hook now guard the vendored `validate-findings.cjs` against Node-behavior or local-edit drift. No vendored file was modified.

### Verified

- Re-vendor drift check: compared the pinned `4de1ac8` against upstream HEAD `f75f9a0` via `gh api .../compare` — the only intervening change is PR #2 (`75be8dd`), a pure directory move (`renamed … +0/-0`) with **zero content drift**. The vendored bytes remain identical to upstream. Next re-vendor check starts from `f75f9a0`.

## [1.0.0] - 2026-06-29

### Added

- **Initial release.** Vendored the `security-audit` skill from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT, © Cloudflare, Inc.) at upstream commit `4de1ac80123057dd73c586cd3862a6c85a2b8a5e`.
  - Six-phase audit pipeline (recon → hunt → validate → report → structured output → independent verification) driven by parallel sub-agents, finding exploitable vulnerabilities with real impact.
  - Bundled assets under `skills/security-audit/`: `SKILL.md`, methodology references (`RECONNAISSANCE.md`, `HUNTING.md`, `ATTACK-CLASSES.md`, `VALIDATION-AND-REPORTING.md`), `report-schema.json`, the zero-dependency `validate-findings.cjs` validator, and the upstream `LICENSE`.
  - Vendored files are copied verbatim; the wrapper adds only `plugin.json` and `README.md`, which documents the Claude Code platform mapping (research → `Explore`, general → `general-purpose`) and how this plugin complements `code-audit-rigor`.
