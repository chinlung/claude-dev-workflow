# Changelog

All notable changes to the `code-audit-rigor` plugin will be documented in this file.

## [1.1.0] - 2026-06-07

### Added

Three deterministic engineering guarantees adapted from [alibaba/open-code-review](https://github.com/alibaba/open-code-review)'s "deterministic engineering + LLM" hybrid design (Apache-2.0). Motivation: the existing frameworks are strong on *depth rigor* (EV math, steel-manning) but coverage, rule specificity, and reference accuracy previously relied on LLM self-discipline — these were its structural weak points relative to OCR's engineering layer.

- **Phase 1b: Path-matched language rule packs with layered overrides.** New `rules/` directory: `manifest.json` (glob → doc, first-match wins, `**` and `{a,b}` supported) + 8 `rule_docs/*.md` packs (TS/JS/React, PHP/Laravel, Python, Go, SQL/mapper, YAML/IaC/Dockerfile, package.json, generic default). Each pack carries a **Review focus** hunt list and a **Do NOT report** suppression list (file-type-scoped false-positive classes — distinct from the global hard-exclusion lists this skill deliberately rejects; suppressions still pass Phase 4 steel-manning). Resolution layers: project `.reviewrules/` → user `~/.claude/review-rules/` → plugin built-in.
- **Mechanical scope + coverage reconciliation (Phase 1 / Phase 5).** The in-scope file list must come from a mechanical command (`git diff --name-only`, `git show --name-only`, Glob) — never from memory. Phase 5 coverage becomes a checklist reconciliation: every Phase 1 file must land in exactly one of Read / Skipped; a new mandatory `Unaccounted` row makes lost-track files an explicit audit-invalidating gap instead of a silent omission.
- **Quoted-code reference anchoring (Framework 4 / Phase 4).** Every `crossReference` now requires a verbatim `quotedCode` field (diff markers stripped, only directly relevant lines). New Phase 4 Step 1 mechanically Greps each quote before any steel-manning: found at claimed lines ±10 → anchored; found elsewhere → re-locate and re-check; absent → `UNVERIFIED_REFERENCE`, confidence −30, EV recomputed. Catches memory-reconstructed references the Principle 2 self-check misses.

### Changed

- Skill frontmatter description and Inspiration section updated to credit alibaba/open-code-review; explicitly documents what was NOT adopted (three-zone memory compression — the Claude Code harness already compacts context natively) and why rule-pack suppression lists do not violate the "no global hard-exclusion lists" stance.
- Version bumped 1.0.1 → 1.1.0 (minor — new capability, no breaking change to existing audit flow).

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
