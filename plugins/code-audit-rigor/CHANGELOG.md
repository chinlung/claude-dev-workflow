# Changelog

All notable changes to the `code-audit-rigor` plugin will be documented in this file.

## [1.2.1] - 2026-06-08

### Changed

- **Codegraph-aware call-chain tracing.** Review flows previously hardcoded "use Grep" for caller tracing — sub-agents follow the dispatch prompt literally, so they never reached for the codegraph index even when one existed, missing dynamic-dispatch call sites (callbacks, DI, event handlers). Now:
  - `/review-branch` Phase 2 step 3: prefer `codegraph_callers` / `codegraph_impact` when the project has a `.codegraph/` index; fall back to Grep otherwise
  - `SKILL.md` Principle 3: tool-selection note — codegraph for *structural* queries (callers/impact/explore), Grep stays correct for *literal-text* work (Phase 4 quoted-code anchoring is verbatim string matching, deliberately unchanged)
- Graceful degradation: projects without codegraph behave exactly as before. No dependency added — codegraph plugin is optional.

## [1.2.0] - 2026-06-08

### Added

- **Two routine review commands migrated from user-level `~/.claude/commands/`** so they version, sync across machines, and resolve the rule packs portably:
  - `/review-branch [base-branch]` — two-round branch review (Phase 1 suggestions → Phase 2 per-suggestion sub-agent verification with quotedCode grep anchoring → Phase 3 report with mandatory coverage reconciliation table). The built-in rules layer now references `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json` — machine-independent, replacing the previous hardcoded local marketplace-repo path that only worked on one machine.
  - `/review-pr <PR号>` — fetches all three GitHub comment endpoints (`pulls/comments`, `pulls/reviews`, `issues/comments`), classifies, fixes security/logic issues with verification tests, commits and replies.
- Rule resolution layering in `/review-branch` is now: project `.reviewrules/` → user `~/.claude/review-rules/` → `${CLAUDE_PLUGIN_ROOT}/rules/` (was: plugin-cache glob with a hardcoded absolute fallback).

### Changed

- Plugin scope widened from "high-stakes audit skill" to "review & audit toolkit": routine commands and the rigor skill share the same rule packs. `plugin.json` description updated accordingly.
- Version bumped 1.1.0 → 1.2.0 (minor — new commands, no breaking change).

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
