# Changelog

All notable changes to the `code-audit-rigor` plugin will be documented in this file.

## [1.0.1] - 2026-05-09

### Added

- **Phase 5b: Zero-findings handling guidance.** Explicit instructions for what to do when CONFIRMED FINDINGS is empty — the most common outcome after Phase 4 corrective steel-manning, but previously unaddressed in the workflow. Surfaced during first real-world test on `bin/tg-fallback-send.sh` (8 candidates → 0 confirmed) where the absence of guidance forced ad-hoc decisions about whether to write the report.
  - Required executive-summary phrasing that explicitly states the negative result as a valuable outcome
  - Mandatory dismissed-findings body with original-vs-re-evaluated confidence, steel-manning argument, and future-note for re-escalation conditions
  - "Total dismissed prior score" sanity check (would-be cost if every dismissal had been wrong)
  - Encouraged skill self-evaluation paragraph for friction-point feedback

- **Phase 5 explicit save-to-disk requirement.** Audit reports must be written to a project-appropriate path (e.g. `knowledge/audits/<target>-<YYYY-MM-DD>.md`), never produced as chat-only output. Aligns with the global `產生文件或參考資料時，一律存檔到磁碟` discipline and amplifies it for audits where future reviewers (not just the current session) are stakeholders.

- **Anti-pattern: "Treating zero confirmed findings as no audit needed."** Added to the Anti-patterns list to forestall the most likely misuse pattern.

### Changed

- Version bumped 1.0.0 → 1.0.1 (patch).

## [1.0.0] - 2026-05-09

### Added

- Initial release.
- Single skill `code-audit-rigor` with four quantitative review frameworks:
  1. Score-based calibration (+10/+5/+3/+1 vs −3 false-positive penalty)
  2. Expected-Value (EV) decision threshold with 67% confidence breakeven
  3. STRIDE + CWE classification for security findings
  4. Mandatory cross-reference contract (file:line evidence, empty array rejected)
- Distilled from `codexstar69/bug-hunter` adversarial review patterns, deliberately excluding auto-fix, hard-exclusion lists, and LLM-readable instruction files outside `SKILL.md` to minimize prompt-injection surface.
