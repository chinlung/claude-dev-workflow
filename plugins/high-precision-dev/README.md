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
| Critic | Finds bugs using severity 1–5 scale | `sonnet` | `CRITIQUE.md` |
| Adversary | 3-round red-team attack | `opus` | `ATTACKS.md` |
| Disproof Agent | Tries to disprove critic/adversary findings | `sonnet` | — |
| Verifier | Compares implementations, merges best parts | `opus` | `VERIFICATION.md` |

### Model assignment (cross-family decorrelation)

The `model` per agent is set **cross-family on purpose** — this is the strongest lever against the shared-model correlation floor described above. Two agents on the same base model share systematic blind spots (they mis-read the same spec clause the same way); two agents on *different* model families (Opus vs Sonnet) have *different* blind spots, so their disagreements carry real decorrelated signal. The assignment keeps **builders and checkers spanning both families**: implementer-a (`opus`) vs implementer-b (`sonnet`) decorrelates the two implementations, and the checkers (`sonnet` critic / `opus` adversary / `sonnet` disproof / `opus` verifier) ensure both families review the work. The verifier and adversary run on the stronger `opus`.

Caveats: (1) this is still bounded — different frontier models can share *some* blind spots; the genuinely independent check is the Phase 4 environmental test gate, which is not a model at all. (2) It requires access to both families and costs more than a single model. To run everything on the session model instead, set each agent's `model:` back to `inherit`. Per-agent **effort** is *not* configurable via agent frontmatter (only `model` is) — effort follows the session's `/effort` setting.

## License

MIT
