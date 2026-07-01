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

## Output contract

Every agent emits a machine-readable output validated against `schema/findings.schema.json` and `schema/coverage.schema.json`:

```json
{
  "implementerId": "implementer-a",
  "timestamp": "2026-07-01T00:00:00Z",
  "specRef": "SPEC.md#v1.0",
  "completionSignal": "SPEC_COMPLETE",
  "findings": [
    { "source": "critic", "severity": "high", "description": "...", "location": "src/...", "evidence": "..." }
  ],
  "coverage": {
    "tested": [ { "requirement": "REQ-001", "testCase": "tests/...", "passed": true } ],
    "untested": [ { "requirement": "REQ-003", "reason": "..." } ],
    "outOfScope": [],
    "verificationStatus": "PARTIAL"
  }
}
```

Key contract: `coverage.verificationStatus = "VERIFIED"` requires at least one entry in `coverage.tested`. A prior-run reference (`coverage.priorRunRef`) must have `suppressesFindings: false` — prior runs never suppress critic/adversary findings.

## Validators

```bash
# Validate a single agent output artifact
node plugins/high-precision-dev/validators/validate-high-precision-output.cjs path/to/output.json

# Run all fixture checks from repo root
node scripts/validate-fixtures.cjs
```

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
