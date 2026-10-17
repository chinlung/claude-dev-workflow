# code-audit-rigor

> Code review & audit toolkit — routine two-round review commands sharing path-matched language rule packs, plus quantitative decision frameworks (EV calculation, score-based calibration, STRIDE+CWE classification, mandatory cross-reference contract) for high-stakes audits.

## What it does

`code-audit-rigor` ships two layers that share the same `rules/` packs:

**Routine commands** (since 1.2.0):
- `/review-branch [base-branch] [--focus <pathspec>]` — two-round branch review: Phase 1 suggestions (with per-file-type rule injection) → Phase 2 per-suggestion sub-agent verification (quotedCode grep anchoring first) → Phase 3 report with a mandatory coverage reconciliation table. Scope is the union of the committed branch diff (`merge-base...HEAD`), working-tree modifications and untracked files, so a pre-commit self-review sees the work you have not committed yet (2.0.1; each scoped file carries a `source` of `committed` / `working-tree` / `untracked`). Since 2.1.0 the command remembers earlier rounds — unchanged files are skipped, verified-but-unfixed suggestions are carried, dismissed anchors are never re-posted — tags each suggestion `introduced` or pre-existing, and prints the risk tier resolved from the rule-pack manifests (see below)
- `/review-pr <PR#>` — fetch all three GitHub comment endpoints (`pulls/comments`, `pulls/reviews`, `issues/comments`), classify, fix security/logic issues with verification tests, commit, reply, and (2.1.0) answer each inline thread with the recorded evidence or rationale and resolve it

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

Since 2.1.0 the resolution is done by `scripts/resolve-rules.cjs` (a real glob matcher over the three layers), which also resolves the `risk` list each manifest may carry.

## Round memory, `introduced` and the risk tier (since 2.1.0)

| Piece | Mechanism |
|---|---|
| Skip what did not change | `scripts/review-branch-rounds.cjs plan` hashes every scoped file (`git hash-object`) and compares with the previous round's results on the same branch; identical files are `skipped` with `unchanged since r<N-1> (blob match)`. `--full` overrides |
| Never re-post a dismissal | every `FAIL` verdict's anchor (`file` + `quotedCode`) accumulates in `dismissed[]` with its round; `annotate` exits 1 without writing when a new suggestion matches one from an earlier round, and the validator rejects such a file |
| Carry, do not re-verify | a `PASS` suggestion whose file is unchanged is `carried` into the report and not sent to a verifier again |
| `introduced` | computed by `annotate` from `git diff -U0 <merge-base>` (committed + working tree; untracked = introduced); the report splits verified findings into *introduced* and *pre-existing* |
| Risk tier | `scripts/resolve-rules.cjs` resolves the `risk` lists of the three manifest layers; `tier: deep` is printed first when any scoped file matches a deep pattern (a project entry wins, even when it says `standard`) |

The round state lives in `<gitdir>/review-branch-plan.json` and `<gitdir>/review-branch-rules.json` (not in the work tree) and in the results file itself (`round`, `scopeMode`, `dismissed`, `carried`, `risk`).

## Validators

All output artifacts are validated by zero-dependency Node scripts. Run from the repo root:

```bash
# All fixture checks (valid fixtures → exit 0; invalid fixtures → exit non-zero)
node scripts/validate-fixtures.cjs

# Validate individual artifacts
node plugins/code-audit-rigor/validators/validate-finding.cjs path/to/finding.json
node plugins/code-audit-rigor/validators/validate-review-branch-results.cjs path/to/review-branch-results.json
node plugins/code-audit-rigor/validators/validate-review-pr-comments.cjs path/to/review-pr-comments.json
node plugins/code-audit-rigor/validators/coverage-reconcile.cjs path/to/review-branch-results.json

# Round memory and rule resolution (2.1.0) — run by /review-branch, usable by hand
node plugins/code-audit-rigor/scripts/review-branch-rounds.cjs plan --root <repo> --base <merge-base> --files <list>
node plugins/code-audit-rigor/scripts/review-branch-rounds.cjs annotate <repo>/review-branch-results.json --root <repo> --base <merge-base>
node plugins/code-audit-rigor/scripts/resolve-rules.cjs --root <repo> --files <list>
bash plugins/code-audit-rigor/tests/review-branch-rounds.test.sh
```

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
