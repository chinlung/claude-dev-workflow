# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
