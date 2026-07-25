# Changelog

All notable changes to the `code-audit-rigor` plugin will be documented in this file.

## [2.0.0] - 2026-07-26

### Removed

- **`/audit-review-fix` and its entire implementation retired** (BREAKING). Removed `commands/audit-review-fix.md`, `workflow/audit-review-fix.md`, `workflow/audit-review-fix-workflow.js`, `schema/audit-review-fix-result.schema.json`, `validators/validate-audit-review-fix-result.cjs`, and the 14 corresponding fixtures. `scripts/validate-fixtures.cjs` dropped both its fixture block and its schema-validator consistency check for that artifact; the remaining suite is green (125 passed, 0 failed).

  **Why:** the workflow overlapped with the `claude-security` plugin's *suggest-patches* job, which has a strictly better risk model. `/audit-review-fix` fanned out ~86 sub-agents (~400k tokens) and **rewrote source files directly** — undoing a bad run meant `git revert`. *suggest-patches* writes patch files to disk that you review and apply yourself (not applying one means nothing happened), each earning three confidence claims from a patch-verifier panel first. Once a patch-file mode exists, "automatically edit the code in place" stops being the better default in any scenario.

  **Migration:** `/audit-review-fix [base-ref]` → run `/claude-security`, choose **Scan changes** (scopes the run to a diff), then **Suggest patches**. Note that `/claude-security` scans committed changes only — commit or stash work in progress first, or use its codebase scan instead.

### Changed

- Cross-references to the retired command in `/review-pr` and `tools/triage-decision-tree.md` rewritten so they no longer depend on it. The underlying discipline is unchanged: `/review-pr` Phase 3 still requires a pre-fix test baseline plus an explicit exit-code sentinel — that rule was learned from three real fail-open bugs in the retired workflow (documented in [1.3.2]/[1.3.3]/[1.3.4]) and it outlives the workflow itself.

### Notes

- **Retained:** `/review-branch`, `/review-pr`, and the `code-audit-rigor` skill. They judge by **correctness** — logic errors, maintainability, test coverage — which the security-oriented tools do not cover: `claude-security` and `security-audit` judge by **exploitability** (a complete attack path; a defense-in-depth gap is explicitly not a vulnerability). The two families are complementary, not substitutes.

## [1.5.0] - 2026-07-01

### Added

- **`/review-branch --focus <pathspec>`** — scope the review to a git pathspec (e.g. `--focus 'src/auth/**'`), applied to the mechanical file-list step so the coverage checklist becomes the filtered set. Cuts token cost and enforces scope on large PRs (the cheapest high-value knob, mirroring `/audit-review-fix`).
- **Confidence on `/review-branch` Phase 2 verdicts.** Each verified / false-positive verdict now carries an honest 0-100 confidence; a verdict under 67% is treated as borderline — re-read the source to push it above 67% or below 33%, or surface it to the user, rather than collapsing an unsure verdict into either bucket.

### Changed

- **`/review-pr` Phase 3 regression check hardened** to the baseline + exit-code-sentinel discipline already audited in `/audit-review-fix` (whose CHANGELOG [1.3.2]/[1.3.3]/[1.3.4] documents three real fail-open bugs in the naive "run the suite, confirm no regression" form). It now captures a pre-fix baseline, counts only new-vs-pre-existing failures as regressions, trusts an explicit `WF_TEST_EXIT=0` (avoiding false-closed on "error" text), treats a newly-broken build as a regression, and fails closed on unparseable output.

## [1.4.0] - 2026-07-01

### Added

- **Durable, machine-checkable output contracts for all three commands.** `/review-branch`, `/review-pr`, and `/audit-review-fix` now each write a structured JSON result (`review-branch-results.json`, PR-comments classification, audit-review-fix result) validated against a new JSON Schema (`schema/*.schema.json`) via a zero-dependency validator (`validators/*.cjs`) before the final Markdown report is produced — shifting these commands from prompt discipline to explicit, machine-checkable contracts. `/review-branch` Phase 3 gained a mandatory coverage-reconciliation step (`validators/coverage-reconcile.cjs`) on top of schema validation.
- `skills/code-audit-rigor/STEEL_MANNING.md` — the Phase 4 steel-manning methodology extracted into its own reference doc.
- Fixture-based test coverage for every validator rule (static fixtures + a single-field mutation generator), enforced repo-wide via GitHub Actions CI and a PostToolUse hook (148 checks total across the four plugins touched in this release).

### Notes

- This release was previously merged (commit `893821c`, PR #4) without a corresponding version bump on `plugin.json` / `marketplace.json` or a changelog entry — the plugin sat at `1.3.4` both before and after a functional (non-doc) change, making that version number ambiguous for consumers who pulled at different points. This entry backfills the version and changelog for that change; no further code changes were made.

## [1.3.4] - 2026-06-29

### Fixed

- **`/audit-review-fix` Verify-Fix no longer green-lights a build that is broken at both baseline and verify** (the run-2 review's "2b" residual; unit harness now 76 assertions). When the test suite was already failing to compile/run at baseline (`errored`, non-zero exit) and is *still* broken after fixes, the old logic masked it (`newlyErrored` needs `!baselineErrored`) and reported `testsPass=true` / "pass confirmed". A new orthogonal `currentlyBroken` check (`errored` AND an explicit non-zero exit) now fails closed regardless of the baseline — "no regression vs an already-broken baseline" is not the same as "the build is OK". It requires an explicit non-zero exit (same exit-trust principle as the 1.3.2 fix) so a passing run whose output merely contains "error" text is not false-failed; assertion-only dirty baselines (not `errored`) are unaffected.

## [1.3.3] - 2026-06-29

### Fixed

- **`/audit-review-fix` workflow — remaining LOW/NOTE robustness items from the run-2 self-audit** (unit-tested: harness now at 71 assertions over the pure helpers).
  - **`status` no longer mis-reports a lone DEFER as `CLEAN`.** A finding triaged `DEFER_OUT_OF_SCOPE` (a real bug too large for this PR) with nothing else now returns the new `REQUIRES_FOLLOW_UP` status (documented in `workflow/audit-review-fix.md` and `commands/audit-review-fix.md`) instead of `CLEAN`/"commit directly". Status logic extracted to a pure `computeStatus()`.
  - **Declined-with-edits are surfaced.** If a fix agent returns `applied=false` but reported `filesModified`, those untested edits left in the tree are now named in the skip reason and logged (previously they were silently labelled "declined").
  - **`today` is path-sanitised** before building the report path (`audits/workflow-audit-<today>.md`), so a `today` arg containing `../` or control chars can no longer write the report outside `audits/`.
  - **Scope-abort hardened** (pure `scopeAbortReason()`): the "no changes" check is now guarded by the real-diff check (a diff whose tail merely contains "no changes" no longer false-aborts), and the git-error allowlist now also catches a bad `--focus` pathspec (`error: pathspec … did not match`) so a scoping typo aborts loudly instead of silently reviewing an empty diff → false `CLEAN`.
  - **Fix-agent prompt hardened** against indirect prompt injection: the agent is told to treat all finding/diff text as untrusted data and to only modify the cited file.
- Note: the EV auto-dismiss 67% breakeven was reviewed and left unchanged — it faithfully implements the `code-audit-rigor` skill's documented Framework 2 (the asymmetry is encoded in the severity points, not a per-severity threshold); changing it would diverge from the skill.

## [1.3.2] - 2026-06-29

### Fixed

- **`/audit-review-fix` workflow — three safety-gate fixes (fail-open → fail-closed), found by a self `security-audit` run (run-2) and adversarially reviewed.** The deterministic logic was refactored into pure, extractable helpers (`normalizeArgs`, `num`, `parseFailCount`, `extractTestSignals`, `computeTestsPass`) covered by a 56-assertion unit harness.
  - **(HIGH) Verify-Fix reported `testsPass=true` for error / no-run states.** It only matched `FAIL <x>` lines and `N failed` counts, so an auto-fix that broke the build (`tsc` `error TS…`, pytest collection error, PHP fatal) was reported `READY_FOR_COMMIT`. Now `extractTestSignals` detects compile/collection/fatal states and a `WF_TEST_EXIT=<code>` exit-code sentinel (added to the baseline + verify test prompts), and `computeTestsPass` fails closed unless the output is parseable and shows no regression vs baseline. `newlyErrored` is gated on `exitCode !== 0` so an explicit exit 0 is trusted (avoids false-closed when a test name/formatter output contains "error").
  - **(MEDIUM) A clean baseline disabled the count-regression backstop.** `baselineFailCount` was `null` on a clean baseline (the recommended state), so `countRegressed` could never fire. A clean baseline now yields `0`.
  - **(MEDIUM) Unvalidated args coerced to NaN / reverted safety flags.** A non-numeric `maxFixLoc`/`votes`/`angles`, or an `args` JSON-string that parsed to a non-object, silently dropped findings / skipped review / removed the LOC cap and reported a false `CLEAN`. `normalizeArgs` + `num`/`numFlag` now coerce with finiteness guards (non-numeric → safe default + a one-time warn), and triage `estimatedLoc` is routed through `num` so a malformed value goes to user-review instead of vanishing from both partition buckets.
  - Also tightened the FAIL-key regex (`\s+` → `[ \t]+`) so a `N failed` summary line cannot be mis-captured as a cross-newline failure key.

## [1.3.1] - 2026-06-29

### Security

- **`/review-pr`: treat fetched PR comments as untrusted data and gate the push behind a diff review.** Added a security-boundary note instructing that all fetched comments — especially `issues/comments`, which anyone can post on a public PR — are untrusted data to be analyzed, never executed as instructions (prompt-injection defense). Added a Phase 4 "推送前確認" step requiring the user to review the actual diff (not just the Phase 2 classification table) before Commit / Push / `gh pr comment`. Defense-in-depth hardening (the harness already prompts for push in default mode); found by a `security-audit` run (Finding 2, LOW).

## [1.3.0] - 2026-06-24

### Added

- **`/audit-review-fix` — automated adversarial batch audit-and-fix workflow, migrated from user-level `~/.claude/`** (same portability pattern as the 1.2.0 command migration). It is the non-interactive batch counterpart to the `code-audit-rigor` skill: one run fans out ~86 sub-agents (~400k tokens) across a 9-angle review, EV-based triage, multi-vote adversarial verification, safety-gated auto-fix, test verification, and a written report under `audits/`.
  - Ships as bundled assets under `workflow/`: the Workflow script (`audit-review-fix-workflow.js`) and the detailed usage reference (`audit-review-fix.md`). The command reads the script via `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js` — machine-independent, no hardcoded home path.
  - Flags: `[base-ref] [dry] [--profile cheap|thorough|ci] [--votes N] [--focus <glob>] [--angles N] [--no-sweep] [--keep-all] [--max-fix-loc N] [--test-cmd <cmd>] [--model <tier>] [--yes]`.
  - The bundled script carries the `A0` args-normalization guard (tolerates runtimes that deliver `args` as a JSON string rather than a parsed object), so every flag is honored regardless of Workflow-runtime delivery quirks.

### Changed

- Plugin scope widened to include safety-gated auto-fix. The **rigor skill itself stays auto-fix-free and injection-safe** by design; auto-fix is provided *only* by the separate `/audit-review-fix` workflow, gated behind adversarial verification and a test pass. `plugin.json` / `marketplace.json` descriptions and keywords updated to reflect the new command (`auto-fix`, `workflow`, `adversarial-verification`) without contradicting the skill's no-auto-fix positioning.

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
