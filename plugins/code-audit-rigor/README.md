# code-audit-rigor

> Quantitative decision frameworks for high-stakes code audits — EV calculation, score-based calibration, STRIDE+CWE classification, mandatory cross-reference contract.

## What it does

`code-audit-rigor` is a single-skill plugin that adds a **deep-audit checklist** to your Claude Code workflow for situations where intuition is insufficient:

- Security-critical reviews (auth, crypto, payments, PII)
- Adversarial-input handling (LLM context assembly, parsers, deserializers)
- Production hot-path / infra-glue changes
- Any situation where a misjudged false negative is structurally more expensive than a false positive

It does **NOT** replace `/review-branch` or `pr-review-toolkit:review-pr` — it complements them by quantifying which findings to act on when the stakes warrant the extra rigor.

## The four frameworks

| # | Framework | Purpose |
|---|---|---|
| 1 | **Score-based calibration** | Align findings with severity, penalize false positives (+10 / +5 / +3 / +1 vs −3) |
| 2 | **Expected-Value (EV) threshold** | `EV = confidence% × points − (100 − confidence%) × 2 × points`; ≥67% confidence to act |
| 3 | **STRIDE + CWE classification** | Every security finding tagged with both — forces explicit reasoning, integrates with industry tooling |
| 4 | **Mandatory cross-reference contract** | Every finding includes `file:line` evidence; empty array rejected — counter-measure against LLM reference fabrication |

## When to invoke

Trigger phrases the skill watches for:
- "rigorous review", "deep audit", "quantified review"
- "security review", "auth / crypto / payment review"
- "對抗式 review", "嚴謹審查"
- Any code touching secrets, auth boundary, crypto, payment, IaC, untrusted-input parsers

For routine PR review, just use `/review-branch` directly — this skill is overkill.

## Output format

Findings are produced as structured JSON-style objects:

```json
{
  "id": "BUG-001",
  "title": "...",
  "severity": "Critical | High | Medium | Low",
  "confidence": 0-100,
  "stride": "Elevation of Privilege",
  "cwe": "CWE-863",
  "claim": "...",
  "evidence": "...",
  "crossReferences": [
    {"file": "src/auth/middleware.ts", "lines": "42-58", "note": "..."}
  ]
}
```

Plus an executive summary, dismissed findings (with rationale so they can be challenged), and a coverage statement listing which files were read.

## Inspiration

The four frameworks distill the quantitative review patterns from [`codexstar69/bug-hunter`](https://github.com/codexstar69/bug-hunter)'s Hunter / Skeptic / Referee adversarial flow into Claude-native checkpoints.

**Deliberately excluded** from the inspiration:
- Auto-fix with canary rollout (too aggressive for production code)
- Hard-exclusion lists for "settled false-positive classes" (creates blind spots)
- LLM-readable instruction files beyond `SKILL.md` (minimizes prompt-injection surface)

## Relationship to other plugins

- **Complements** `dev-workflow` (architecture / implementation phases), `pr-review-toolkit` (standard review)
- **Distinct from** `high-precision-dev` (which is a multi-agent zero-defect implementation flow, not a review discipline)
- **Independent of** `multi-agent-debate` (decision-making for design choices, not review of existing code)

## License

MIT
