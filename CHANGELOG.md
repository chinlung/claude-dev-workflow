# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.10.0] - 2026-08-03

### Added

- **session-reflect 1.0.0** (new plugin) — session-end reflective review. A fail-open bash Stop-hook gate (loop guard via `stop_hook_active`, once-per-session flag file, <10-line substantiveness floor, mid-interaction detection that yields without consuming the session's single trigger) hands off to a two-stage skill: quick triage (routine sessions exit with a one-line "nothing to review"), then a four-lens sweep (out-of-scope findings / pre-existing issues / adjacent optimizations / knowledge gaps). Candidates must survive a verification layer before the user ever sees them: an inline four-filter self-review (anchor actually Read, existing safeguards, deliberate design, observable value) plus one adversarial verifier subagent (main-loop model, never downgraded) framed to refute, not confirm. Up to 5 survivors are offered via a multi-select prompt — chosen ones execute in-session, unchosen ones land in `.claude/reflect-backlog.md` (`[rejected]` entries are kept forever as dedup evidence; the plugin never commits the backlog). Gate covered by 15 fixture assertions wired into CI (`tests/gate.test.sh`). Design: `docs/session-reflect-design-2026-08-03.md`.

### Notes

- Marketplace minor bump 1.9.1 → 1.10.0 (new plugin).

## [1.9.1] - 2026-07-26

### Changed

- **openspec-superpowers-workflow 1.2.2 → 1.3.0** — SKIP clause sharpened from "small bug fixes with no spec impact" to an explicit contract-risk rubric (public API / data contract / schema / migration / backward compatibility / security boundaries / concurrency / cross-module behavior; judge by contract risk, not LOC or file count). Placed in the skill description because that is where the auto-trigger skip decision is made — self-contained for every installer. `PHASE-IDENTIFICATION.md` and the root README synced to the same language.

## [1.9.0] - 2026-07-26

### Changed

- **code-audit-rigor 1.5.0 → 2.0.0** (BREAKING) — `/audit-review-fix` and its whole implementation (workflow script, command, schema, validator, 14 fixtures) retired. It overlapped with the `claude-security` plugin's *suggest-patches* job, which carries a strictly better risk model: patch files you review and apply yourself, versus ~86 sub-agents (~400k tokens) rewriting source in place. `/review-branch`, `/review-pr`, and the rigor skill are retained — they judge by correctness, which the exploitability-focused security tools do not cover. `scripts/validate-fixtures.cjs` updated accordingly; suite green at 125 passed, 0 failed. See that plugin's CHANGELOG [2.0.0] for the migration path.

## [1.8.11] - 2026-07-02

### Changed

- **security-audit 1.0.0 → 1.0.1** — added local drift protection for the vendored validator: a `valid-basic.json` fixture (confirmed + rejected findings) plus single-field mutations wired into `scripts/validate-fixtures.cjs`, so the repo-root suite + CI + PostToolUse hook now guard `validate-findings.cjs` (including its two semantic constraints: trace must start `entrypoint`, end `sink`). Re-vendor drift check recorded: pinned `4de1ac8` vs upstream HEAD `f75f9a0` is a pure directory move, zero content drift. No vendored file was modified.
- **openspec-superpowers-workflow 1.2.1 → 1.2.2** — Phase 1 pre-check path unified to `${CLAUDE_PLUGIN_ROOT}` (was a repo-relative path with a prose "resolve from install root" note), matching the convention used across the other plugins' skills/commands.

### Notes
- Also (non-plugin): added a `security-audit` entry to the personal `~/.claude/CLAUDE.md` plugin-decision tree (active vulnerability hunting → `/security-audit`; diff/PR governance → `code-audit-rigor`), and closed the two dangling Tier-3 judgment calls in `docs/loop-design-review-2026-07-01.md` with explicit won't-do dispositions + re-open triggers. Marketplace patch bump 1.8.10 → 1.8.11.

## [1.8.10] - 2026-07-01

### Changed

- **high-precision-dev 1.4.0 → 1.5.0** — cross-family model assignment to break the shared-base-model correlation floor: `implementer-a`/`adversary`/`verifier` on `opus`, `implementer-b`/`critic`/`disproof-agent` on `sonnet`, so builders and checkers span two model families. The `model` frontmatter is family-level (pairs Opus 4.8 × Sonnet 5; specific past versions not selectable, same-family pairings barely decorrelate); per-agent effort is not frontmatter-configurable and follows the session `/effort`.

### Notes
- Marketplace patch bump 1.8.9 → 1.8.10.

## [1.8.9] - 2026-07-01

### Changed

- **high-precision-dev 1.3.0 → 1.4.0** — honest `p→p⁴` reframe + implementer decorrelation. The multiplicative `p⁴` claim was demoted everywhere it appeared (`plugin.json` / `marketplace.json` / `README` / `start.md` / `ANTI-PATTERNS.md`) from a headline guarantee to an idealized model with an explicit shared-model-correlation-floor caveat (two identically-prompted instances of one base model make correlated errors on systematic misreadings). `implementer-a` and `implementer-b`, previously byte-identical, were given genuinely different approaches (A spec-first / top-down, B test-first / behavior-driven; same completeness bar, different path) so the weakest independence leg actually decorrelates.

### Notes
- Marketplace patch bump 1.8.8 → 1.8.9.

## [1.8.8] - 2026-07-01

### Added

- **high-precision-dev 1.2.1 → 1.3.0** — controller-run environmental test gate before Phase 4 completion. After the verifier merges, the controller itself runs the SPEC test suite and captures the exit code (`WF_TEST_EXIT=$?`), promoting "tests pass" from an agent prose claim to an environmental fact wired into the existing capped fix-loop's exit condition. Deliberately does NOT reintroduce a structured-output contract — it is the one machine gate that satisfies the meta-rule *a gate is justified iff (a) it reads an environmental fact, not an agent assertion, and (b) a downstream consumer acts on it.*

### Notes
- Marketplace patch bump 1.8.7 → 1.8.8.

## [1.8.7] - 2026-07-01

### Changed

- **code-audit-rigor 1.4.0 → 1.5.0** — `/review-branch` gained `--focus <pathspec>` and a Phase 2 confidence field (0-100, <67% flagged borderline); `/review-pr` Phase 3 regression check hardened to the baseline + exit-code-sentinel discipline already audited in `/audit-review-fix` (capture pre-fix baseline, count new-vs-preexisting failures, trust `WF_TEST_EXIT=0`, a build newly broken counts as regression, unparseable → fail closed).
- **openspec-superpowers-workflow 1.2.0 → 1.2.1** — Phase 1 gained an optional lenient local pre-check that runs the bundled `.cjs` before the authoritative `openspec validate --strict` (surfaces the plugin's own CI-only validator in the live workflow).
- **high-precision-dev 1.2.0 → 1.2.1** — removed the never-implemented `--phase N` arg hint from `start.md`; investigated the `disproof-agent` non-registration and confirmed it was not a defect (identical frontmatter to registering siblings; an under-versioned-PR-#4 reload artifact resolved by the 1.2.0 bump + reload).

### Notes
- Follow-on items from the loop-design review. Marketplace patch bump 1.8.6 → 1.8.7.

## [1.8.6] - 2026-07-01

### Changed

- **Selective L2 consolidation** (from `docs/loop-design-review-2026-07-01.md`) — the PR #4 uniform "schema + validator on all four plugins" was reduced to only where a machine consumer actually reads the contract, rather than reverted wholesale (a full revert would also have discarded code-audit-rigor's *working* live validators, CI, hook, and STEEL_MANNING).
  - **multi-agent-debate 1.1.0 → 1.2.0** — completed L2: `/debate` Phase 6 now emits `debate-output.json` and runs `validate-debate-output.cjs` as a live structural gate; added cross-field referential integrity (`selectedProposal`/`agreedProposals` must point at real `proposals[].id`) and a required, machine-checked `coverage` field; reconciled Phase 4 convergence criteria (≥8 score gap) with `orchestrator.md`.
  - **high-precision-dev 1.1.0 → 1.2.0** — removed dead L2: all six agents emit prose reports, so the schema validated a JSON shape nothing produces. Deleted `schema/`, validators, fixtures + runner wiring; cleaned dangling refs in `README`/`start.md`.
- Removed a stray `t.json` (a prior-debate test artifact committed to repo root in PR #4).

### Notes
- Suite went 148 → 133 checks (−21 removed high-precision checks, +6 new debate mutations). Marketplace patch bump 1.8.5 → 1.8.6.

## [1.8.5] - 2026-07-01

### Fixed

- **Backfilled version bumps + changelogs for PR #4** (commit `893821c`), which had landed a uniform "structured output + zero-dependency validator + fixtures + CI + PostToolUse hook" L2 layer across four plugins **without** any version bump — leaving each `plugin.json` at its pre-merge number both before and after a functional change, and two plugins with no `CHANGELOG.md` at all. This ambiguity is exactly what breaks registry version-caching (new agents/capabilities silently not loading).
  - **code-audit-rigor 1.3.4 → 1.4.0**, **openspec-superpowers-workflow 1.1.0 → 1.2.0** — version + changelog backfilled for the L2 change.
  - **multi-agent-debate 1.0.0 → 1.1.0**, **high-precision-dev 1.0.0 → 1.1.0** — `CHANGELOG.md` created (backfilled 1.0.0 initial-release + the 1.1.0 L2 change).

### Notes
- No functional code changes in this release — version/changelog hygiene only. Marketplace 1.8.4 → 1.8.5.

## [1.8.4] - 2026-06-29

### Fixed

- **code-audit-rigor 1.3.3 → 1.3.4** — `/audit-review-fix` Verify-Fix no longer reports a build that is broken at *both* baseline and verify as `testsPass`/`READY_FOR_COMMIT` (the run-2 review's "2b" residual). A new orthogonal `currentlyBroken` check (`errored` + explicit non-zero exit) fails closed regardless of baseline — committing a non-building tree is never OK. Requires an explicit non-zero exit so a passing run containing "error" text is not false-failed; assertion-only dirty baselines are unaffected. Unit harness now 76 assertions.

### Notes
- Marketplace patch bump 1.8.3 → 1.8.4.

## [1.8.3] - 2026-06-29

### Fixed

- **code-audit-rigor 1.3.2 → 1.3.3** — remaining LOW/NOTE robustness items from the run-2 self-audit of the `/audit-review-fix` workflow (unit harness now 71 assertions):
  - `status` no longer reports a lone `DEFER_OUT_OF_SCOPE` finding as `CLEAN` — new `REQUIRES_FOLLOW_UP` status (docs updated).
  - Fix agents that edit then return `applied=false` now surface the untested files left in the tree (no longer silently "declined").
  - `today` is path-sanitised before building the report path (no `../` traversal).
  - Scope-abort hardened: real-diff guard on the "no changes" check, and a bad `--focus` pathspec now aborts loudly instead of silently reviewing an empty diff.
  - Fix-agent prompt hardened against indirect prompt injection (treat diff/finding text as data).
  - EV 67% breakeven reviewed and intentionally left unchanged (faithful to the skill's documented Framework 2).

### Notes
- Marketplace patch bump 1.8.2 → 1.8.3.

## [1.8.2] - 2026-06-29

### Fixed

- **code-audit-rigor 1.3.1 → 1.3.2** — three safety-gate fixes in the `/audit-review-fix` workflow (fail-open → fail-closed), found by a self `security-audit` run (run-2) and adversarially reviewed, covered by a 56-assertion unit harness:
  - (HIGH) Verify-Fix reported `testsPass=true` for compile/collection/fatal "build broke" states (no `failed`/`FAIL ` token) → an unbuildable tree was reported `READY_FOR_COMMIT`. Now detects error/no-run states + an exit-code sentinel and fails closed.
  - (MEDIUM) A clean baseline disabled the count-regression backstop (`baselineFailCount=null`); now coerced to `0`.
  - (MEDIUM) Non-numeric/non-object args coerced to NaN or reverted safety flags → silent dropped findings / no review / no LOC cap / false `CLEAN`; now validated with finiteness/object-shape guards.

### Notes
- Marketplace patch bump 1.8.1 → 1.8.2 (one plugin patch release).

## [1.8.1] - 2026-06-29

### Security

- **codegraph 1.0.0 → 1.0.1** — fixed the prerequisite npm package name from the unowned unscoped `codegraph` (a third-party 469-byte placeholder with no `bin`) to the real scoped `@colbymchenry/codegraph`. Removes a dependency-confusion exposure and a functional break (the bundled MCP server never started for anyone who followed the docs). Found by a `security-audit` run; confirmed against the maintainer's working install.
- **code-audit-rigor 1.3.0 → 1.3.1** — `/review-pr` now labels fetched PR comments (anyone can post on a public PR) as untrusted data to analyze, not instructions to execute, and requires a diff review before the Phase 4 commit/push. Defense-in-depth (`security-audit` Finding 2, LOW).

### Fixed

- Aligned `repository`/`homepage` in `multi-agent-debate` (was the non-existent `chinlung/multi-agent-debate`) and added them to `session-learning`, both now pointing at `chinlung/claude-dev-workflow`. Metadata-only; plugin versions unchanged.
- Added a root `.gitignore` (`node_modules/`, `.env*`, `*.pem`/`*.key`, `*.local.md`, `*.log`, OS junk) to guard contributors/forkers against committing local config or secrets.

### Notes
- Marketplace patch bump 1.8.0 → 1.8.1 (two plugin patch releases + repo hygiene).

## [1.8.0] - 2026-06-29

### Added
- **New plugin: security-audit 1.0.0**. Vendored the `security-audit` skill from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT, © Cloudflare, Inc.) at upstream commit `4de1ac8`. A six-phase multi-agent pipeline (recon → hunt → validate → report → structured output → independent verification) that actively hunts exploitable vulnerabilities with real impact, complementing `code-audit-rigor`'s review-discipline frameworks. Vendored files are copied verbatim; the wrapper adds only `plugin.json` + `README.md`, which document the Claude Code platform mapping (research → `Explore`, general → `general-purpose`) and the upstream-sync procedure (see CONTRIBUTING §7).

### Notes
- Marketplace minor bump 1.7.5 → 1.8.0 (new plugin added).

## [1.7.5] - 2026-06-24

### Added
- **code-audit-rigor 1.2.1 → 1.3.0**: Added `/audit-review-fix`, an automated adversarial batch audit-and-fix Workflow folded in as the plugin's third layer (migrated from user-level `~/.claude/`, same portability pattern as the 1.2.0 command migration). The command reads its script via `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js` (no hardcoded home path): 9-angle review + EV triage + safety-gated auto-fix + test verification + report. The "auto-fix-free" positioning is now scoped to the rigor skill only — auto-fix is provided solely by `/audit-review-fix` under safety gates and adversarial verification.

### Notes
- Marketplace patch bump 1.7.4 → 1.7.5.

## [1.7.4] - 2026-06-17

### Changed
- **openspec-superpowers-workflow 1.0.1 → 1.1.0**: Aligned Phase 4 with superpowers v6.0.0, which rewrote subagent-driven-development's per-task review. The two-stage review (separate spec + quality reviewers) became a single `task-reviewer` returning both verdicts at once, plus one end-of-branch whole-branch review using the strongest model. Documented the v6 worktree relocation: the global `~/.config/superpowers/worktrees/` was removed in favor of an in-project `.worktrees/` root (must be git-ignored). Added a reviewer-integrity rule (no suppressing findings, no defaulting severity) and a dependency note: superpowers >= 6.0.0.

### Notes
- Marketplace patch bump 1.7.3 → 1.7.4.

## [1.7.3] - 2026-06-08

### Changed
- **code-audit-rigor 1.2.0 → 1.2.1**: Codegraph-aware call-chain tracing. Review sub-agents follow dispatch prompts literally, and those prompts hardcoded "use Grep" — so codegraph indexes were never used even when present, missing dynamic-dispatch call sites. `/review-branch` Phase 2 and `SKILL.md` Principle 3 now prefer `codegraph_callers`/`codegraph_impact` when `.codegraph/` exists, with Grep fallback. Quoted-code anchoring deliberately stays on Grep (literal string matching, not structural). No hard dependency — graceful degradation without codegraph.

### Notes
- Marketplace patch bump 1.7.2 → 1.7.3.

## [1.7.2] - 2026-06-08

### Changed
- **code-audit-rigor 1.1.0 → 1.2.0**: Migrated `/review-branch` and `/review-pr` from user-level `~/.claude/commands/` into the plugin. Motivation: `/review-branch`'s built-in rules layer previously fell back to a hardcoded absolute path that only resolved on one machine; inside the plugin it now uses `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json`, which is machine-independent and ships with every install. Plugin scope widened to "review & audit toolkit" (routine commands + rigor skill sharing the same rule packs).

### Notes
- Marketplace patch bump 1.7.1 → 1.7.2.

## [1.7.1] - 2026-06-07

### Changed
- **code-audit-rigor 1.0.1 → 1.1.0**: Added three deterministic engineering guarantees adapted from [alibaba/open-code-review](https://github.com/alibaba/open-code-review)'s "deterministic engineering + LLM" hybrid design (Apache-2.0). Gap analysis: the skill was strong on depth rigor (EV math, steel-manning, STRIDE+CWE) but coverage, rule specificity, and reference accuracy relied on LLM self-discipline — exactly the three things OCR solves with engineering.
  - **Phase 1b path-matched rule packs**: new `rules/manifest.json` (glob → doc, first-match) + 8 `rule_docs/*.md` (TS/JS/React, PHP/Laravel, Python, Go, SQL/mapper, YAML/IaC/Dockerfile, package.json, default), each with a Review-focus hunt list and a file-type-scoped "Do NOT report" suppression list. Layered overrides: project `.reviewrules/` → user `~/.claude/review-rules/` → plugin built-in.
  - **Mechanical scope + coverage reconciliation**: Phase 1 scope must come from `git diff --name-only` / `git show` / Glob output; Phase 5 reconciles every scope file into Read or Skipped with a mandatory `Unaccounted` row that invalidates the audit if non-empty.
  - **Quoted-code reference anchoring**: Framework 4 crossReferences now require a verbatim `quotedCode` field; Phase 4 Step 1 greps it mechanically before steel-manning (found at claimed lines ±10 → anchored; elsewhere → re-locate; absent → `UNVERIFIED_REFERENCE`, confidence −30).
  - Deliberate exclusions documented: no three-zone memory compression (harness compacts natively); suppression lists are file-type-scoped, not the global hard-exclusion lists the skill rejects.

### Notes
- Marketplace patch bump 1.7.0 → 1.7.1 reflects the existing-plugin content change.

## [1.7.0] - 2026-05-30

### Added
- **CodeGraph Plugin** (1.0.0): Single-skill plugin teaching structural-code-intelligence-before-grep discipline for projects with a `.codegraph/` index.
  - **Bundled MCP server** (`.mcp.json` → `codegraph serve --mcp`): install once and the MCP tools are available in every project — a new project then needs only `codegraph init -i`, no per-project `codegraph install` or `.mcp.json`. Plugin-provided tools are prefixed `mcp__plugin_codegraph_codegraph__<tool>`; requires the `codegraph` CLI on `PATH` globally.
  - **Entry-point split**: documents the non-obvious fact that `codegraph serve --mcp` exposes only `trace`/`node`/`explore`/`search`/`context` as `codegraph_*` MCP tools, while `impact`/`callers`/`callees`/`affected`/`status`/`files` are Bash-CLI only (verified on codegraph 0.9.7). Neither surface is a superset — calling `codegraph_impact` as an MCP tool fails.
  - **Proactive triggers** tied to actions (edit/rename/remove → `impact`; change a method → `callers`/`node`; unfamiliar code → `context`; flow → `trace`) rather than only phrased questions.
  - **Reliability fallback**: when a capability isn't an MCP tool, use the CLI — never silently degrade to a half-grep that misses dynamic-dispatch call sites.
  - Progressive-disclosure `reference.md`: 4-step new-project setup, read-only `settings.json` allowlist, and known gotchas (tool-managed `CODEGRAPH_START/END` block overwrites on re-sync, that block's table over-promising CLI commands as MCP tools, `daemon.pid` absent from the default gitignore).

### Notes
- Marketplace minor bump 1.6.1 → 1.7.0 for the new plugin.

## [1.6.1] - 2026-05-09

### Changed
- **code-audit-rigor 1.0.0 → 1.0.1**: Add Phase 5b zero-findings handling guidance to `SKILL.md`. Surfaced during first real-world test on `bin/tg-fallback-send.sh` where 8 candidates → 0 confirmed exposed the absence of explicit instructions for clean-audit reports. New Phase 5b mandates: (1) full report production even with zero confirmed findings, (2) executive-summary phrasing that explicitly states the negative result as valuable, (3) dismissed-findings body with original-vs-re-evaluated confidence and steel-manning rationale, (4) total dismissed prior score sanity check, (5) encouraged skill self-evaluation paragraph. Added explicit "save to disk" requirement to Phase 5 (no chat-only output for audits) and one new anti-pattern.

### Notes
- Marketplace patch bump 1.6.0 → 1.6.1 reflects the SKILL.md content change. Users on 1.6.0 still have the four quantitative frameworks but lack guidance on the most common outcome (zero confirmed findings) — they should update.

## [1.6.0] - 2026-05-09

### Added
- **Code Audit Rigor Plugin**: Single-skill plugin providing quantitative review discipline for high-stakes audits where intuition is insufficient (security-critical, crypto, payment, IaC, untrusted-input parsers).
  - **Five core review-discipline principles**: (1) Read first / score later, (2) "Have I actually read this, or am I guessing?" self-check, (3) Verify the source (not the diff), (4) Multi-agent consensus is not verification, (5) Wrongful dismissal costs 2× the score
  - **Four quantitative frameworks**:
    1. Score-based calibration (+10 / +5 / +3 / +1 vs −3 false-positive penalty)
    2. Expected-Value (EV) decision threshold: `EV = confidence% × points − (100 − confidence%) × 2 × points`, ≥67% confidence breakeven
    3. STRIDE + CWE classification with 16-CWE quick-reference table
    4. Mandatory cross-reference contract (every finding includes `file:line` evidence; empty array rejected)
  - **End-to-end audit workflow**: 5 phases (scope, literal pass, findings draft, adversarial sweep, aggregate report) with explicit Phase 4 corrective steel-manning to defuse multi-agent false-confidence amplification
  - **Self-contained**: All rules and reference tables ship in `SKILL.md`; works on any machine without depending on host project's CLAUDE.md
  - **Inspired by** `codexstar69/bug-hunter` adversarial Hunter / Skeptic / Referee flow, but **deliberately excludes** auto-fix with canary rollout (too aggressive for production code), hard-exclusion lists for "settled false-positive classes" (creates blind spots), and LLM-readable instruction files outside `SKILL.md` (minimizes prompt-injection surface area)
- Updated marketplace version to 1.6.0

## [1.5.1] - 2026-04-10

### Changed
- **openspec-superpowers-workflow 1.0.0 → 1.0.1**: Strengthen auto-trigger. Rewrite `SKILL.md` frontmatter `description` with imperative "MUST use" wording, expanded trigger list (now matches `openspec` CLI commands and the presence of `openspec/changes/<name>/` folders), and explicit forbidden-behaviour enumeration. Add "Activation reminder" note at the top of `SKILL.md` body anchoring non-negotiable rules before any action. Removes the need for users to maintain a separate "must call this skill" reminder in their own `~/.claude/CLAUDE.md` — the same meta-instruction now ships with the plugin. `phases.md` unchanged.

### Fixed
- **dev-workflow 1.0.1 → 1.0.2**: Correct `plugin.json` description from "6 specialized agents" to "7 specialized agents: ..., quality assurance, and documentation". The mismatch was a leftover from the 2026-03-12 `35c0a9c` refactor commit that reverted the version string to match `CHANGELOG [1.0.1]` but also reverted the description text to the 1.0.0-era wording, even though the `documentation-specialist` agent file was never removed. No behavioural or file changes — metadata fix only.

### Documentation
- `README.md` / `README.zh-TW.md`: Add `Session Learning Plugin` table row, install command, and full plugin section (previously missing despite shipping since 1.4.0).
- `CHANGELOG.zh-TW.md`: Translate `[1.5.0]` and `[1.4.0]` entries from the English changelog (Chinese changelog previously stopped at `[1.3.0]`).
- `marketplace.json`: Bump `dev-workflow` entry version to `1.0.1` then `1.0.2` to match `plugins/dev-workflow/plugin.json` (leftover drift from the earlier version-alignment refactor).

### Notes
- Marketplace version bump from 1.5.0 → 1.5.1 reflects that `HEAD` contains multiple plugin-content changes beyond the initial 1.5.0 commit. Users on 1.5.0 who do not update will miss the stronger auto-trigger and the dev-workflow description fix.

## [1.5.0] - 2026-04-10

### Added
- **OpenSpec + Superpowers Workflow Plugin**: Six-phase feature development workflow enforcing strict role separation between OpenSpec (spec lifecycle, WHAT) and Superpowers (dev discipline, HOW)
  - Single skill with progressive disclosure: `SKILL.md` (58 lines, always loaded) + `phases.md` (290+ lines, loaded on demand)
  - **Phase 1 — Spec Definition** (OpenSpec leads): propose + specs as user-reviewed artifacts; design/tasks as placeholder drafts
  - **Phase 2 — Design Refinement** (Superpowers `brainstorming` → overwrites `design.md` in place)
  - **Phase 3 — Task Planning** (Superpowers `writing-plans` → overwrites `tasks.md` in place)
  - **Phase 4 — Implementation** (Superpowers `subagent-driven-development` + mandatory TDD)
  - **Phase 5 — Review & Feedback**: `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag taxonomy with Y/N classification, recorded in `review-notes.md`; spec files are never modified during review
  - **Phase 6 — Reconcile & Archive** (OpenSpec): clean-rewrite discipline (not incremental patches), `tasks.md` frozen as execution history, `[CONSTITUTION]` items routed to `openspec/config.yaml` instead of feature spec
  - Prerequisites section documenting OpenSpec CLI vs `/opsx:*` slash-command alternatives and the `openspec init .` (no `--here` flag) gotcha
  - Validator strictness gotcha: every `### Requirement:` block must have `SHALL`/`MUST` in the first paragraph
  - Archive folder date-prefix behaviour: `openspec/changes/archive/<YYYY-MM-DD>-<name>/`
  - Decision quick-reference table (13 situations) and 8-item anti-patterns list
- Updated marketplace version to 1.5.0

## [1.4.0] - 2026-03-12

### Added
- **Session Learning Plugin**: 經驗學習系統，漸進式保存對話模式
  - `/save-session` 命令：分析對話並保存有價值的模式為 memory 或 skill
    - 5 Phase 分析流程：掃描 → 層級判斷 → 去重合併 → 執行 → 報告
    - 自動區分全域 vs 專案層級保存位置
    - 更新優先於新建，避免記憶膨脹
    - 每次最多 1-2 項變更，精簡克制
  - Stop hook：在實質工作階段結束時輕量提醒執行 `/save-session`
    - Command 類型（非 prompt），不觸發額外 LLM 呼叫
    - Flag file 機制防止同一 session 重複提醒
    - 自動跳過短工作階段（< 10 行 transcript）
- Updated marketplace version to 1.4.0

## [1.3.0] - 2026-03-06

### Added
- **High-Precision Dev Plugin**: Multi-agent development mode for safety-critical code
  - `/high-precision-dev:init` command to scaffold SPEC.md and CONSENSUS.md
  - `/high-precision-dev:start` command to run the 4-phase verification workflow
  - 5 specialized agents:
    - Implementer A/B: Independent defensive implementation in isolated worktrees
    - Critic: Systematic bug finding with severity 1-5 scale
    - Adversary: 3-round red team attack (boundary, semantic, assumption)
    - Verifier: Final integration with SPEC.md coverage verification
  - Error rate compression from p to p^4 through epistemic division of labor
  - Phase 3 fix cycle limit (max 3 iterations) with adversary re-attack
  - Verifier Step Zero: checks CRITIQUE.md/ATTACKS.md before integration
  - Three-level intensity spectrum documentation (single agent → /debate → /start)
- Updated marketplace version to 1.1.0
- Updated README with High-Precision Dev plugin documentation (EN + zh-TW)

## [1.2.0] - 2025-12-19

### Added
- **Multi-Agent Debate Plugin**: A dialectical system for multi-perspective decision making
  - `/debate` command for initiating debates
  - 5 specialized agents:
    - Orchestrator: Analyzes requirements and configures perspectives
    - Perspective A/B/C: Proposes solutions from different angles
    - Critic: Reviews proposals and provides quantitative scoring
  - Smart perspective configuration based on requirement type
  - Quantitative scoring system (30-point scale)
  - Consensus-driven decision making (≥2 agents must agree)
  - Iterative refinement through multiple debate rounds
  - User participation at key decision points
- Updated README to document both plugins in the collection
- Traditional Chinese documentation for multi-agent-debate

## [1.1.0] - 2025-12-11

### Added
- **Documentation Specialist** agent (step 7): Handles documentation updates, CHANGELOG maintenance, and PR description generation
- **handoff.md mechanism**: Central state management document for seamless context transfer between agents
- Language agnostic design: works with any programming language
- Traditional Chinese documentation (README.zh-TW.md, CHANGELOG.zh-TW.md)

### Changed
- Generalized all agents to be language/framework agnostic
- Improved Implementation Specialist with better code pattern recognition
- Enhanced Quality Assurance with more comprehensive checks
- Updated Solution Architect with broader technology considerations
- Refined Test Engineer for multi-language test frameworks

### Fixed
- Repository field format in package.json (should be string not object)
- Corrected GitHub repository URL

### Documentation
- Added tutorial video link by Pahud Hsieh
- Added contributor credits
- Renumbered development workflow documents for sequence consistency

## [1.0.0] - 2024-12-11

### Added
- Initial release of dev-workflow plugin
- 6 specialized agents:
  - Issue Analyst: Requirements analysis and user stories
  - Code Archaeologist: Codebase exploration and pattern identification
  - Solution Architect: Architecture design and solution comparison
  - Implementation Specialist: Code implementation following best practices
  - Test Engineer: Test planning and execution
  - Quality Assurance: Code quality verification and build validation
- Main command `/dev-workflow` with support for:
  - Full workflow execution
  - Single step execution (`--step`)
  - Resume from checkpoint (`--resume`)
- Progress tracking with TodoWrite
- Pause point after architecture design for user confirmation
- Comprehensive documentation output in `docs/task-{timestamp}/` directory
