# security-audit

> A skill that turns the agent into a security auditor. It finds vulnerabilities that cross a real trust boundary and backs each one with source evidence — through reconnaissance, coverage-led hunting, candidate validation, structured output, independent record verification, and target-neutral reporting — not checklist deviations.

## What it does

The skill has two operating modes:

- **Guidance mode** (the default) — security questions, focused reviews, triage, or investigating a specific finding. The skill uses only the parts that apply, writes no audit artifacts, and does not run the full workflow.
- **Full audit mode** — when you explicitly ask to audit or pen-test a codebase, ask for a full / comprehensive / end-to-end security review, or ask for report artifacts. If the request could mean either, the skill asks one question before creating any files.

A full audit runs six phases in order:

1. **Reconnaissance** — `research` agents map architecture, trust boundaries, input surfaces, local build paths, and prior evidence; the parent writes `architecture.md` and seeds a deterministic `coverage-ledger.json`
2. **Coverage-led hunting** — isolated `general` hunters take ledger units in waves (core attack classes plus the selected domain companions); a `research` coverage critic after each wave looks for gaps
3. **Candidate validation** — every unique candidate goes to a fresh `general` verifier that did not hunt it and tries to disprove it
4. **Structured output** — `findings.json` holds `confirmed`, `needs_validation`, and `rejected` records, checked by `validate-findings.cjs`; `validate-coverage-ledger.cjs` checks the coverage claim
5. **Independent record verification** — fresh `research` verifiers re-check every final `confirmed` and `needs_validation` record against the source
6. **Target-neutral report** — `REPORT.md`, `FINDINGS-DETAIL.md`, and `NEEDS-VALIDATION.md` are derived from the verified records

The three verdicts mean different things: `confirmed` has a complete source trace and a bounded observed result and is the only verdict with a severity (capped at the demonstrated impact); `needs_validation` names the exact unresolved fact that blocks confirmation; `rejected` records a disproved candidate. A run ends either with every artifact written and both validators passing, or with `run_status: "incomplete"` and the gap stated in the report.

Runs take a profile — `quick`, `standard` (default), or `deep` — and an optional budget counted in agent invocations. Multiple runs against the same repo are additive: the skill reads prior ledgers and findings, revalidates anything whose source changed, and never counts stale or unresolved work as covered. Output defaults to `~/security-audit-skill/<repo-name>/run-<N>`, outside the target repository.

Ten domain companions extend the core attack classes: AI/LLM, web protocol and auth, client-side, memory safety and binary, cloud and deployment, data isolation and lifecycle, desktop/mobile/local IPC, protocols/RPC/messaging, resource exhaustion, and supply chain and release.

## Claude Code platform mapping

The vendored `SKILL.md` is written agent-neutral. In Claude Code the neutral terms map as follows:

| Skill term | Claude Code equivalent |
|---|---|
| **Task tool** | the `Agent` tool (sub-agent dispatch) |
| **`research` agent** — reconnaissance | `Explore` agent — read-only fact gathering |
| **`research` agent** — coverage critic (Phase 2) and record verifier (Phase 5) | `general-purpose` agent told to stay read-only — these roles judge whether coverage is complete and whether a record holds; `Explore` is built to locate code and reads excerpts, not to audit |
| **`general` agent** — hunter (Phase 2) and candidate verifier (Phase 3) | `general-purpose` agent |
| parallel sub-agents | multiple `Agent` calls in one message (or a `Workflow` fan-out for larger sweeps) |

The skill preserves the specified roles, write isolation, and independence boundaries regardless of the underlying mechanism — the verifier of a candidate is never the agent that found it.

### Running target code

The skill runs target-controlled builds, tests, or fixtures only inside an OS-enforced sandbox with no external network, an empty allowlisted environment, a read-only target, scratch-only writes, and CPU / memory / process / disk / wall-clock limits. If any control is missing, it does not execute target code and keeps the lead as `needs_validation`. Claude Code's Bash sandbox lets commands write the working directory and starts them from your shell environment, so it does not meet these controls on its own; expect execution-dependent leads to come back as `needs_validation` unless you provide a sandbox that does.

The default output directory is under your home directory, which Claude Code's sandbox does not let commands write; approve those writes or name another output directory outside the target.

Hunters look for secrets committed to the target (including in git history). A secret found that way can end up quoted in `findings.json` or the reports, so treat a run's output directory as sensitive.

## When to use this vs `code-audit-rigor`

The two security plugins are complementary, not redundant:

| | `security-audit` (this plugin) | `code-audit-rigor` |
|---|---|---|
| Posture | **Active hunting** — find new exploitable bugs in a whole codebase | **Review discipline** — judge a known change (PR/branch) rigorously |
| Trigger | "audit / pen-test / find vulnerabilities" | "review this PR/branch", high-stakes finding triage |
| Method | six-phase multi-agent workflow with a coverage ledger, adversarial disproof, structured `findings.json` | quantitative frameworks (EV, score calibration, STRIDE+CWE, cross-reference contract) + two-round review commands |
| Output | confirmed findings with source trace and bounded result, plus `needs_validation` leads | per-finding verdicts, coverage reconciliation |

Use `security-audit` to attack a codebase and surface unknown vulnerabilities; use `code-audit-rigor` to govern the review of a specific diff.

## Requirements

- A model with tool use and parallel sub-agents (any current Claude model in Claude Code qualifies)
- Node.js — for the zero-dependency `validate-findings.cjs` and `validate-coverage-ledger.cjs`

## Attribution

This plugin **vendors** the skill from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT License, © 2025-2026 Cloudflare, Inc.).

- **Upstream commit:** `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8`
- Everything under `skills/security-audit/` except `LICENSE` is copied verbatim from upstream's `skills/security-audit/`: `SKILL.md`, the four methodology references, the ten domain companions, `report-schema.json`, both validators, and their test suites. `LICENSE` is upstream's root `LICENSE`, byte-identical.
- This README, the plugin manifest, `CHANGELOG.md`, and `tests/` are the only additions; the vendored files are unmodified to keep upstream sync a clean `diff`.

**Tests:** `tests/upstream.test.sh` runs upstream's two test suites (`node --test`); `scripts/validate-fixtures.cjs` at the repo root runs `tests/fixtures/security-audit/valid-basic.json` (one record of each verdict) plus single-field mutations against the vendored validator. Both run in CI and in the repo's PostToolUse hook.

**Updating from upstream:** clone the upstream repo, `diff -r` its `skills/security-audit/` against ours, copy the changes over verbatim, run both test entry points above, update the upstream-commit SHA here, and bump this plugin's version (per `CONTRIBUTING.md` §7 — maintaining wrapper/vendored upstream dependencies). The repo's sandbox `denyWrite` covers all of `plugins/`, so the copy has to run outside the sandbox.

Background on the methodology: Cloudflare's [Build your own vulnerability harness](https://blog.cloudflare.com/build-your-own-vulnerability-harness).

## License

MIT — this plugin's wrapper files and the vendored skill are both MIT-licensed. See [`skills/security-audit/LICENSE`](skills/security-audit/LICENSE) for the upstream Cloudflare copyright.
