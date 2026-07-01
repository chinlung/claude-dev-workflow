# high-precision-dev

> Multi-agent implementation mode for safety-critical code. Compresses single-agent error rate from p to p^4 through epistemic division of labor: two independent implementers, a critic, an adversary, a disproof agent, and a verifier.

## Purpose

`high-precision-dev` is a **spec-driven implementation discipline** — not a security audit tool, not a design debate tool. Use it when a bug in the code would be expensive: cryptography, financial calculations, data validation, security-critical logic.

**When to use this vs related plugins:**

| Goal | Use |
|------|-----|
| Implement safety-critical / zero-defect code | `/init` + `/start` (this plugin) |
| Decide *what* to implement (design choices) | `multi-agent-debate` first |
| Review an existing code change rigorously | `code-audit-rigor` |
| Hunt exploitable security bugs in a codebase | `security-audit` skill |

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

| Agent | Role | Output |
|-------|------|--------|
| Implementer A | Independent defensive implementation | `IMPL_A_REPORT.md` |
| Implementer B | Independent defensive implementation | `IMPL_B_REPORT.md` |
| Critic | Finds bugs using severity 1–5 scale | `CRITIQUE.md` |
| Adversary | 3-round red-team attack | `ATTACKS.md` |
| Disproof Agent | Tries to disprove critic/adversary findings | — |
| Verifier | Compares implementations, merges best parts | `VERIFICATION.md` |

## License

MIT
