# multi-agent-debate

> Multi-agent dialectical system for design decisions and trade-off analysis. Generates optimal solutions through structured debate, quantitative scoring, and consensus building.

## Purpose

`multi-agent-debate` is a **decision-making and design trade-off tool** — not a security vulnerability hunter, not a code reviewer. Use it when you need to compare design options, technology choices, or architectural strategies with explicit rationale and scoring.

**When to use this vs related plugins:**

| Goal | Use |
|------|-----|
| Compare design/architecture options | `/debate` (this plugin) |
| Hunt for exploitable security bugs | `security-audit` skill |
| Rigorous review of a known code change | `code-audit-rigor` |
| Implement spec-driven, safety-critical code | `high-precision-dev` |

## Usage

```bash
/debate Design a caching strategy for the API layer
/debate Should we use microservices or monolith for the new project?
/debate --max-rounds 5 How to optimize database query performance?
/debate --perspectives "security,performance,maintainability" Design the authentication system
```

## Output contract

Every debate produces a machine-readable artifact validated against `schema/debate-output.schema.json`:

```json
{
  "metadata": { "sessionId": "...", "timestamp": "...", "model": "..." },
  "requirement": "...",
  "proposals": [ { "id": "p1", "scores": { "feasibility": 8, "completeness": 7, "riskLevel": 3 }, ... } ],
  "critiqueRounds": [ { "round": 1, "criticisms": [...] } ],
  "consensus": { "reached": true, "summary": "...", "agreedProposals": ["p2"] },
  "finalDecision": { "selectedProposal": "p2", "reasoning": "..." },
  "validation": { "verdict": "verified" }
}
```

A prior debate run can be summarized in `schema/prior-debate.schema.json` — a durable local artifact that provides context to future debates. Key contract: `reuseConstraint.suppressNewFindings` and `suppressNewDecisions` **must both be `false`**; prior runs never override independent analysis.

## Validators

```bash
# Validate a debate output artifact
node plugins/multi-agent-debate/validators/validate-debate-output.cjs path/to/debate-output.json

# Run all fixture checks from repo root
node scripts/validate-fixtures.cjs
```

Note: `prior-debate` artifacts currently have no standalone CLI validator. The repo-root fixture runner performs inline shape checks for `schema/prior-debate.schema.json`, including `schemaVersion`, `reuseConstraint.suppressNewFindings === false`, `reuseConstraint.suppressNewDecisions === false`, and `reuseConstraint.applicabilityNote`.

## Agents

| Agent | Role |
|-------|------|
| Orchestrator | Analyzes requirement, configures perspectives, manages workflow |
| Perspective A/B/C | Propose solutions from assigned angles |
| Critic | Reviews all proposals, raises challenges, scores quantitatively |
| Validator | Approves or rejects final decision artifact |

## License

MIT
