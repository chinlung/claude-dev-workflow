# code-audit-rigor

> Code review & audit toolkit — routine two-round review commands sharing path-matched language rule packs, plus quantitative decision frameworks (EV calculation, score-based calibration, STRIDE+CWE classification, mandatory cross-reference contract) for high-stakes audits.

## What it does

`code-audit-rigor` ships two layers that share the same `rules/` packs:

**Routine commands** (since 1.2.0):
- `/review-branch [base-branch]` — two-round branch review: Phase 1 suggestions (with per-file-type rule injection) → Phase 2 per-suggestion sub-agent verification (quotedCode grep anchoring first) → Phase 3 report with a mandatory coverage reconciliation table
- `/review-pr <PR#>` — fetch all three GitHub comment endpoints (`pulls/comments`, `pulls/reviews`, `issues/comments`), classify, fix security/logic issues with verification tests, commit and reply

**Deep-audit skill** — a quantitative checklist for situations where intuition is insufficient:

- Security-critical reviews (auth, crypto, payments, PII)
- Adversarial-input handling (LLM context assembly, parsers, deserializers)
- Production hot-path / infra-glue changes
- Any situation where a misjudged false negative is structurally more expensive than a false positive

The skill complements `pr-review-toolkit:review-pr` by quantifying which findings to act on when the stakes warrant the extra rigor; for everyday work use `/review-branch`.

## The four frameworks

| # | Framework | Purpose |
|---|---|---|
| 1 | **Score-based calibration** | Align findings with severity, penalize false positives (+10 / +5 / +3 / +1 vs −3) |
| 2 | **Expected-Value (EV) threshold** | `EV = confidence% × points − (100 − confidence%) × 2 × points`; ≥67% confidence to act |
| 3 | **STRIDE + CWE classification** | Every security finding tagged with both — forces explicit reasoning, integrates with industry tooling |
| 4 | **Mandatory cross-reference contract** | Every finding includes `file:line` evidence **plus a verbatim `quotedCode` anchor**; empty array rejected, unanchored quote rejected — counter-measure against LLM reference fabrication |

## The three engineering guarantees (since 1.1.0)

Adapted from [alibaba/open-code-review](https://github.com/alibaba/open-code-review)'s deterministic-engineering layer — they turn three things that previously relied on LLM self-discipline into mechanical checks:

| # | Guarantee | Mechanism |
|---|---|---|
| 1 | **Path-matched rule packs** (Phase 1b) | `rules/manifest.json` maps globs to per-language docs (`rule_docs/*.md`), each with a hunt list **and** a "Do NOT report" suppression list. Layered overrides: project `.reviewrules/` → user `~/.claude/review-rules/` → plugin built-in; first match wins |
| 2 | **Mechanical scope + coverage reconciliation** (Phase 1/5) | Scope list must come from `git diff --name-only` / `git show` / Glob output. Phase 5 reconciles every file into Read or Skipped; an `Unaccounted` file invalidates the audit |
| 3 | **Quoted-code anchoring** (Phase 4 Step 1) | Grep each finding's `quotedCode` in the claimed file before steel-manning: hit at claimed lines ±10 → anchored; elsewhere → re-locate; absent → `UNVERIFIED_REFERENCE`, confidence −30 |

## When to invoke

Trigger phrases the skill watches for:
- "rigorous review", "deep audit", "quantified review"
- "security review", "auth / crypto / payment review"
- "對抗式 review", "嚴謹審查"
- Any code touching secrets, auth boundary, crypto, payment, IaC, untrusted-input parsers

For routine PR review, just use this plugin's `/review-branch` command directly — the skill is overkill.

## Rule resolution layering

Both the commands and the skill resolve per-file review rules through the same chain (first match wins):

1. Project `.reviewrules/manifest.json` (team-shared, committed to git)
2. User `~/.claude/review-rules/manifest.json` (personal)
3. Plugin built-in `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json` — machine-independent, ships with the install

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

The four frameworks distill the quantitative review patterns from [`codexstar69/bug-hunter`](https://github.com/codexstar69/bug-hunter)'s Hunter / Skeptic / Referee adversarial flow into Claude-native checkpoints. The three engineering guarantees (1.1.0) adapt [`alibaba/open-code-review`](https://github.com/alibaba/open-code-review)'s deterministic file selection, four-tier rule priority chain, and external positioning module (Apache-2.0; rule docs rewritten, not copied).

**Deliberately excluded** from the inspirations:
- Auto-fix with canary rollout (too aggressive for production code)
- *Global* hard-exclusion lists for "settled false-positive classes" (creates blind spots) — the rule packs' suppression lists are file-type-scoped named patterns that still pass Phase 4 steel-manning, not global exclusions
- LLM-readable instruction files beyond this plugin's reviewed, versioned content (minimizes prompt-injection surface)
- Three-zone memory compression (the Claude Code harness already compacts context natively)

## Relationship to other plugins

- **Complements** `dev-workflow` (architecture / implementation phases), `pr-review-toolkit` (standard review)
- **Distinct from** `high-precision-dev` (which is a multi-agent zero-defect implementation flow, not a review discipline)
- **Independent of** `multi-agent-debate` (decision-making for design choices, not review of existing code)

## License

MIT
