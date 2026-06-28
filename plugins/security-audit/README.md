# security-audit

> A skill that turns the agent into a security auditor. It runs a six-phase pipeline — recon → hunt → validate → report → structured output → independent verification — using parallel sub-agents to find **exploitable vulnerabilities with real impact**, not checklist deviations.

## What it does

The skill activates automatically when you ask for a security audit ("security audit this codebase", "find vulnerabilities in ./src", "pen-test the code"). It then runs:

1. **Recon** — parallel research agents map architecture, trust boundaries, and input surfaces → `architecture.md`
2. **Hunt** — parallel general agents attack from different angles (injection, access control, business logic, crypto, feature abuse, chained attacks, wildcard); each can spawn sub-agents
3. **Validate** — separate agents try to *disprove* each finding; adversarial review kills false positives
4. **Report** — `REPORT.md` (human-readable) + `FINDINGS-DETAIL.md` (traces for MEDIUM+ findings)
5. **Structured output** — `findings.json` conforming to `report-schema.json`, validated by `validate-findings.cjs`
6. **Independent verification** — fresh agents verify every factual claim against the source

Multiple runs against the same repo are additive: each run reads prior `findings.json` to skip known issues and target gaps. Output defaults to `~/security-audit-skill/<repo-name>/run-<N>`.

## Claude Code platform mapping

The vendored `SKILL.md` is written agent-neutral. In Claude Code the neutral terms map as follows:

| Skill term | Claude Code equivalent |
|---|---|
| **Task tool** | the `Agent` tool (sub-agent dispatch) |
| **`research` agent** (`subagent_type`) | `Explore` agent — read-only, focused codebase exploration and factual verification |
| **`general` agent** (`subagent_type`) | `general-purpose` agent — broad investigation, can spawn focused sub-agents |
| parallel sub-agents | multiple `Agent` calls in one message (or a `Workflow` fan-out for larger sweeps) |

The skill preserves the specified roles, parallelism, and independence boundaries regardless of the underlying mechanism — the validator of a finding is never the agent that found it.

## When to use this vs `code-audit-rigor`

The two security plugins are complementary, not redundant:

| | `security-audit` (this plugin) | `code-audit-rigor` |
|---|---|---|
| Posture | **Active hunting** — find new exploitable bugs in a whole codebase | **Review discipline** — judge a known change (PR/branch) rigorously |
| Trigger | "audit / pen-test / find vulnerabilities" | "review this PR/branch", high-stakes finding triage |
| Method | 6-phase multi-agent pipeline, adversarial disproof, structured `findings.json` | quantitative frameworks (EV, score calibration, STRIDE+CWE, cross-reference contract) + two-round review commands |
| Output | exploit report with concrete attack scenarios | per-finding verdicts, coverage reconciliation |

Use `security-audit` to attack a codebase and surface unknown vulnerabilities; use `code-audit-rigor` to govern the review of a specific diff.

## Requirements

- A model with tool use and parallel sub-agents (any current Claude model in Claude Code qualifies)
- Node.js — for `validate-findings.cjs` schema validation in Phase 5

## Attribution

This plugin **vendors** the skill from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT License, © 2025-2026 Cloudflare, Inc.).

- **Upstream commit:** `4de1ac80123057dd73c586cd3862a6c85a2b8a5e`
- The skill content under `skills/security-audit/` (SKILL.md, the four methodology references, `report-schema.json`, `validate-findings.cjs`, `LICENSE`) is copied verbatim from upstream. The Cloudflare `LICENSE` is preserved alongside it.
- This README and the plugin manifest are the only additions; the vendored files are unmodified to keep upstream sync a clean `diff`.

**Updating from upstream:** re-clone the upstream repo, `diff` it against `skills/security-audit/`, copy over changes, update the upstream-commit SHA above, and bump this plugin's version (per `CONTRIBUTING.md` §7 — maintaining wrapper/vendored upstream dependencies).

Background on the methodology: Cloudflare's [Build your own vulnerability harness](https://blog.cloudflare.com/build-your-own-vulnerability-harness).

## License

MIT — this plugin's wrapper files and the vendored skill are both MIT-licensed. See [`skills/security-audit/LICENSE`](skills/security-audit/LICENSE) for the upstream Cloudflare copyright.
