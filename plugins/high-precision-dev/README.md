# high-precision-dev

> Multi-agent implementation mode for safety-critical code. Reduces the escape rate of systematic errors through epistemic division of labor and role-diverse adversarial review — two independent implementers (with different approaches), a critic, an adversary, a disproof agent, and a verifier.

## Purpose

`high-precision-dev` is a **spec-driven implementation discipline** — not a security audit tool, not a design debate tool. Use it when a bug in the code would be expensive: cryptography, financial calculations, data validation, security-critical logic.

**When to use this vs related plugins:**

| Goal | Use |
|------|-----|
| Implement safety-critical / zero-defect code | `/init` + `/start` (this plugin) |
| Decide *what* to implement (design choices) | `multi-agent-debate` first |
| Review an existing code change rigorously | `code-audit-rigor` |
| Hunt exploitable security bugs in a codebase | `security-audit` skill |

### On the error-rate framing (honest scope)

Earlier releases claimed this "compresses error rate from `p` to `p⁴`." That multiplicative figure is an **idealized model, not a measured guarantee** — it assumes four *independent* channels, but all agents share one base model, the same `SPEC.md` / `CONSENSUS.md`, and the same session, so their errors are correlated exactly where it matters most (systematic misreadings). What genuinely works is **role-diverse adversarial review** (builder vs attacker vs checker surface different blind-spot classes) and the two implementers' **different approaches** (spec-first vs test-first). The improvement over a single optimistic pass is real but **unquantified and bounded below by a shared-model correlation floor** — you cannot get below the base model's systematic error rate on a class it uniformly mishandles. See `docs/loop-design-review-2026-07-01.md` §8.

## Usage

```bash
# Step 1: scaffold SPEC.md and CONSENSUS.md
/init parse_amount

# Step 2: fill in SPEC.md (boundary table, requirements, test expectations)

# Step 3: run the full 4-phase multi-agent workflow
/start ./SPEC.md
```

## Output artifacts

Each phase writes prose Markdown deliverables to the SPEC.md directory (see the **Agents** table below for the per-agent files). Coverage and residual-uncertainty tracking live in `CONSENSUS.md` and the verifier's `VERIFICATION.md`, reconciled against `SPEC.md` by prompt discipline, phase by phase.

> An earlier release (1.1.0) shipped a JSON schema + validator for a machine-readable agent output. It was never wired into the live `/start` flow — the agents emit the prose reports above — so it was removed in 1.2.0 (see `CHANGELOG.md` and `docs/loop-design-review-2026-07-01.md`). This plugin's rigor comes from its epistemic division of labor, not a structural output contract.

## Agents

| Agent | Role | Model | Output |
|-------|------|-------|--------|
| Implementer A | Independent implementation — spec-first / top-down | `opus` | `IMPL_A_REPORT.md` |
| Implementer B | Independent implementation — test-first / behavior-driven | `sonnet` | `IMPL_B_REPORT.md` |
| Critic | Finds bugs using severity 1–5 scale | `opus` | `CRITIQUE.md` |
| Adversary | 3-round red-team attack | `opus` | `ATTACKS.md` |
| Disproof Agent | Tries to disprove critic/adversary findings | `opus` | — |
| Verifier | Compares implementations, merges best parts | `opus` | `VERIFICATION.md` |

### Model assignment

**Builders are split across two models; checkers all run on `opus`.** implementer-a (`opus`, spec-first) and implementer-b (`sonnet`, test-first) take different approaches on different models, and the Phase 4 test gate checks what both produce. The four checkers — critic, adversary, disproof-agent, verifier — decide whether something has a problem; a review that misses a bug is never discovered afterwards, so none of them gets the cheaper tier. `/start` names `model="opus"` on every checker dispatch so a PreToolUse model-floor hook, where one is installed (it cannot read a named agent's frontmatter), does not bounce it. That explicit value overrides the frontmatter, so `tests/agent-models.test.sh` pins the checkers to `opus` and requires each dispatch to equal its agent's frontmatter.

1.5.0 put critic and disproof-agent on `sonnet` for cross-family decorrelation. Opus and Sonnet of one generation from one vendor share more blind spots than that assumed, and a setup with a model-floor hook re-sent those dispatches on opus anyway. For decorrelation, add a different vendor's pass (e.g. Codex) rather than a cheaper model from the same one; the genuinely independent check is still the Phase 4 environmental test gate, which is not a model at all.

Effort: current Claude Code accepts `effort:` in agent frontmatter, plugin agents included; these agents leave it unset so they follow the session's `/effort`. To run everything on the session model instead, set each agent's `model:` to `inherit` and drop the `model="opus"` arguments in `commands/start.md`.

## License

MIT
