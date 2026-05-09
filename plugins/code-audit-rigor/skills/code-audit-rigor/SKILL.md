---
name: code-audit-rigor
description: Use when conducting high-stakes code audits where intuition alone is insufficient — security-critical reviews, financial / cryptographic / safety-critical code, or any deep dive triggered by user keywords like "rigorous review" / "deep audit" / "quantified decision" / "security review" / "對抗式 review" / "嚴謹審查". Provides five core review-discipline principles plus four quantitative frameworks (Expected-Value decision threshold, score-based calibration, STRIDE+CWE classification, mandatory cross-reference contract). This skill is fully self-contained — it does not depend on the host project's CLAUDE.md to function. SKIP for routine PR review or simple bug fixes where standard review flows are adequate. Inspired by adversarial multi-agent review patterns (e.g. codexstar69/bug-hunter), distilled into Claude-native checkpoints without auto-fix or LLM-readable injection vectors.
---

# Code Audit Rigor

> **Activation reminder (for Claude):** if you are reading this file, the user has signalled this is not a routine review — they want quantitative discipline applied to a high-stakes decision. Do NOT short-cut to "looks fine to me" or "probably safe." Apply the principles and frameworks in order, document each step, and surface uncertainty to the user rather than absorb it as confidence.

## Why this skill exists

Routine code review flows are calibrated for everyday PR work. They produce findings, prioritize them, and rely on the reviewer's judgment for the final accept / reject call. That works most of the time.

But some reviews need more rigor:
- **Security-critical code** — auth, crypto, payment, PII handling
- **Adversarial-input handling** — anything that processes untrusted external data (LLM prompts, parsed file uploads, deserialized payloads)
- **Tight blast radius** — production hot path, infra glue, IaC templates
- **High decision-cost asymmetry** — where dismissing a real bug is structurally far more expensive than investigating a false positive

For these cases, **a misjudged false negative is structurally more expensive than a false positive**. This skill provides the discipline and arithmetic to surface that asymmetry explicitly.

## When this skill applies

Trigger on any of:
- User keywords: "rigorous review", "deep audit", "quantified review", "security review", "對抗式 review", "嚴謹審查", "auth / crypto / payment review"
- Code touches: secrets handling, auth boundary, crypto primitives, payment flows, IaC / infra glue, untrusted-input parsers, LLM context assembly
- User explicitly requests "use code-audit-rigor"

If the user is asking for routine PR review, this skill does NOT apply.

## Part A — Five core review-discipline principles

These principles apply to every step of an audit. They are mandatory checkpoints — skipping any of them invalidates the audit.

### Principle 1 — Read first, score later

Do a literal pass through every file in scope BEFORE forming any opinion or producing any finding. No shortcuts via:
- Filename heuristics ("looks like config, probably fine")
- Grep summaries without reading surrounding context
- Diff-only inspection without reading the full file

If you have not read a file, you cannot have a finding about it.

### Principle 2 — "Have I actually read this, or am I guessing?" self-check

Before submitting any finding, ask yourself this question literally. If the honest answer is "guessing from memory" or "inferring from the diff", **re-read the relevant file:lines now**.

LLMs reconstruct plausible-sounding code from training data. This self-check is the single most effective counter-measure.

### Principle 3 — Verify the source, not the diff

Diff-only review is unreliable because:
- Diff shows changed lines, not the surrounding context that determines whether the change is correct
- Identical-looking symbols (`User`, `user`, `userObj`, `userData`) may refer to different types or scopes
- Reviewers (including AI agents) frequently confuse same-named functions / variables / constants from different files

For any critical or high-severity claim, you MUST `grep` for the symbol and `Read` the full definition before adopting the finding.

### Principle 4 — Multi-agent consensus is not verification

If three independent agents (or three review tools, or three reviewers) all flag the same issue, that is **not evidence the issue is real**. They are reading the same diff through similar reasoning paths — misreads amplify in the same direction, not orthogonally.

Treat any agent-reported confidence score as "the agent's confidence in its own reasoning", not as "probability the bug is real". Always re-verify against source code yourself.

### Principle 5 — Wrongful dismissal costs 2× the score

When deciding whether to dismiss a finding as a false positive, treat the cost of dismissing a real bug as **2× the severity score** (see Framework 1 below). This asymmetric penalty exists because:
- A false positive costs 5–30 minutes of investigation
- A wrongly dismissed real bug costs anything from a security incident to silent data corruption — potentially unbounded

This penalty is the engine that makes the EV math (Framework 2) work.

## Part B — Four quantitative frameworks

### Framework 1 — Score-based calibration

Incentive structure to align findings with severity, penalize false positives:

| Severity | Confirmed bug | False positive |
|---|---|---|
| Critical (auth bypass, RCE, data leak) | +10 | −3 |
| High (injection, privilege escalation) | +5 | −3 |
| Medium (logic error, missing validation) | +3 | −3 |
| Low (style, minor inefficiency) | +1 | −3 |

**Rule:** Five real bugs beat twenty false positives. If finding count starts to balloon, re-read the code before adding more — quality > quantity.

### Framework 2 — Expected-Value (EV) decision threshold

Before dismissing or acting on any finding, compute its expected value:

```
EV = (confidence%) × points − (100 − confidence%) × 2 × points
```

- `confidence%` = honest estimate that the finding represents a real bug (0–100)
- `points` = severity score from Framework 1
- The `2×` factor encodes Principle 5

**Decision rule:**
- `EV > 0` → finding is worth investigating / acting on
- `EV < 0` → safe to dismiss, but record the rationale so it can be challenged
- Breakeven is **≥67% confidence** (algebraic consequence of the 2× penalty)

**Worked examples:**
- Critical (10 pts) at 50% confidence: `EV = 0.5 × 10 − 0.5 × 2 × 10 = −5`. Dismiss is statistically supported, BUT 50% confidence on a critical finding usually means insufficient investigation — re-read to push confidence above 67% or below 33% before deciding.
- Medium (3 pts) at 80% confidence: `EV = 0.8 × 3 − 0.2 × 2 × 3 = +1.2`. Investigate / act.
- Low (1 pt) at 60% confidence: `EV = 0.6 × 1 − 0.4 × 2 × 1 = −0.2`. Dismiss with note.

**Anti-pattern:** Using "I'm not sure" as a default to skip findings. The EV formula forces an explicit confidence number — that is the point.

### Framework 3 — STRIDE + CWE classification (security findings)

Every security finding MUST be tagged with both:

**STRIDE category** (one of):

| Code | Name | Example |
|---|---|---|
| S | Spoofing | Forged identity, JWT signature bypass |
| T | Tampering | Modified data in transit / at rest, parameter pollution |
| R | Repudiation | Missing audit logs, log injection |
| I | Information disclosure | Stack traces in prod, PII in logs, side-channel leaks |
| D | Denial of service | Unbounded loops, memory bombs, ReDoS |
| E | Elevation of privilege | Auth bypass, role escalation, sandbox escape |

**CWE ID** — pick the most specific applicable ID at https://cwe.mitre.org/

Common CWEs to memorize:

| CWE | Description |
|---|---|
| CWE-22 | Path Traversal |
| CWE-78 | OS Command Injection |
| CWE-79 | Cross-site Scripting (XSS) |
| CWE-89 | SQL Injection |
| CWE-200 | Information Exposure |
| CWE-287 | Improper Authentication |
| CWE-352 | Cross-Site Request Forgery (CSRF) |
| CWE-434 | Unrestricted Upload of Dangerous File |
| CWE-502 | Deserialization of Untrusted Data |
| CWE-639 | Insecure Direct Object Reference (IDOR) |
| CWE-732 | Incorrect Permission Assignment |
| CWE-798 | Hardcoded Credentials |
| CWE-862 | Missing Authorization |
| CWE-863 | Incorrect Authorization |
| CWE-918 | Server-Side Request Forgery (SSRF) |
| CWE-1333 | Inefficient Regex (ReDoS) |

If you cannot pick a CWE, the finding is probably too vague — refine it until you can.

**Worked example:**
- Finding: "Auth middleware checks `user.isAdmin` after fetching user object, but the fetcher uses cached results that may include stale role data"
- STRIDE: **E** (Elevation of Privilege)
- CWE: **CWE-863** (Incorrect Authorization)

### Framework 4 — Mandatory cross-reference contract

Every finding output MUST include a `crossReferences` array citing specific `file:line` evidence. **Empty array is rejected.**

**Required schema for each finding:**
```json
{
  "id": "BUG-001",
  "title": "Short imperative description",
  "severity": "Critical | High | Medium | Low",
  "confidence": 0-100,
  "stride": "S | T | R | I | D | E",
  "cwe": "CWE-NNN",
  "claim": "What is wrong, in one sentence",
  "evidence": "Why I believe it is wrong, in 1-3 sentences",
  "crossReferences": [
    {"file": "src/auth/middleware.ts", "lines": "42-58", "note": "isAdmin check after stale fetch"},
    {"file": "src/auth/cache.ts", "lines": "15-30", "note": "TTL 30 min, role changes immediate"}
  ],
  "ev": 8.0,
  "decision": "ACT | DISMISS | INVESTIGATE_FURTHER"
}
```

The `stride` and `cwe` fields are required for security findings, optional otherwise.

**Self-check before submitting any finding:**
> "Have I actually read every file:line in `crossReferences`, or am I guessing?"
> If the answer is "guessing", re-read the files now (Principle 2).

## Part C — End-to-end audit workflow

### Phase 1: Scope definition
Set the file list explicitly before starting. State which files are in scope, which are explicitly excluded and why. Output:
```
SCOPE:
  in: src/auth/**, src/api/auth-routes.ts
  out: tests/**, docs/**, third-party/**
  reason for exclusions: <one line>
```

### Phase 2: Literal pass (Principle 1)
Read every in-scope file end to end. Take notes on:
- Trust boundaries (where untrusted input enters)
- Authorization checkpoints
- External calls / side effects
- Cryptographic operations
- Error-handling branches

Do not produce findings yet.

### Phase 3: Findings draft
For each candidate issue:
1. Write `claim` and `evidence` in plain language
2. Populate `crossReferences` (Framework 4)
3. Self-check Principle 2 ("have I actually read the cross-references?")
4. Apply Framework 3 (STRIDE+CWE) if security-relevant
5. Assign severity and confidence
6. Compute EV per Framework 2
7. Set `decision` field

### Phase 4: Adversarial sweep (Principle 4 corrective)
For each finding marked ACT or INVESTIGATE_FURTHER, deliberately steel-man the **opposite** position:
- Could the framework / runtime already prevent this?
- Is there a guard further up the call chain you missed?
- Is the input you assumed adversarial actually validated upstream?

If steel-manning lowers confidence below 67%, downgrade to INVESTIGATE_FURTHER or DISMISS.

### Phase 5: Aggregate report
Output structure:
```
EXECUTIVE SUMMARY: <1 paragraph>

CONFIRMED FINDINGS (sorted by EV descending):
  - [Critical, conf 85, EV +6.5] BUG-001: ...
  - [High,     conf 72, EV +1.0] BUG-002: ...

DISMISSED FINDINGS (with rationale):
  - [Med, conf 30, EV -1.8] BUG-D01: dismissed because <reason>

COVERAGE:
  - Read in full: <list of files>
  - Skipped: <list with reason>
  - Total score: <sum of confirmed point values>
```

**Always save the report to disk** — output to a file path the user can refer to later (e.g. `knowledge/audits/<target>-<YYYY-MM-DD>.md`, `audits/<target>-<YYYY-MM-DD>.md`, or wherever fits the project structure). Never produce only chat output for an audit — the user instruction `產生文件或參考資料時，一律存檔到磁碟` (save artifacts to disk by default) applies here even more strictly because audit reports have value to future reviewers, not just the current session.

### Phase 5b: When CONFIRMED FINDINGS is zero

**A clean audit is a valuable result, not a non-event.** When all candidates were dismissed (typically after Phase 4 corrective steel-manning), you MUST still produce the full report. Do NOT short-cut to "looks fine, no findings." The report serves three concrete purposes:

1. **Reviewer prior** for the next person (or AI) auditing the same code — they don't have to re-do the same Phase 4 steel-manning, they can build on this report's dismissed-findings rationales
2. **Audit trail** documenting which threats were considered and ruled out, with confidence numbers and steel-manning arguments — auditable by humans, not just trusted by assertion
3. **Diff baseline** for future change reviews — when the code changes, the next audit can compare against this snapshot ("did the change touch the lines that BUG-D01 identified as the source of `source $ENV_FILE` risk?")

**Required structure when zero confirmed:**

- **Executive summary must explicitly state the negative result.** Phrasing like:
  - "No confirmed findings. After Phase 4 corrective steel-manning, all N candidate findings were downgraded to DISMISS."
  - "This is a valuable result, not absence of work — N specific threat vectors were considered and ruled out, with rationales preserved for future reviewers."
- **DISMISSED FINDINGS section is the body of the report** — every entry must include:
  - Original confidence vs re-evaluated confidence (shows Phase 4 work happened)
  - The specific steel-manning argument that led to dismissal
  - "Future note" describing conditions under which the dismissal would no longer apply (e.g. "Multi-user environments need this re-evaluated")
- **Total dismissed prior score** — sum the points of all DISMISS entries (as if confirmed). This is the "would-be cost if we had been wrong about every dismissal" — useful as a sanity check that you weren't reflexively dismissing everything.
- **Skill self-evaluation paragraph** (encouraged) — note any friction points hit during this audit (ambiguous scope, missing context, hard-to-pick CWE, etc.). Feeds back into improving this skill.

The total file length of a zero-findings report is typically not shorter than a findings-present report — it should be longer if anything, because steel-manning rationales are the substance.

## When NOT to use this skill

- Routine self-audit on small bug fixes — over-engineered
- Style / formatting / naming reviews — not what this skill optimizes
- Code recently audited by the same checklist — diminishing returns
- Brainstorming or design review — use a design-review tool instead

## Anti-patterns

- **Padding low-severity findings to look thorough** — Framework 1's −3 penalty exists to prevent this
- **Using STRIDE / CWE labels without thinking** — if you cannot justify the specific CWE ID, the classification is wrong
- **Treating confidence as binary** — "I think there might be a bug" is 50% confidence, not 100%
- **Auto-fixing findings** — this skill produces analysis, not patches; fixes go through the user's normal review-and-approve workflow
- **Skipping Principle 4 corrective sweep** — without steel-manning, multi-agent consensus becomes false-confidence amplifier
- **Treating "zero confirmed findings" as no audit needed** — the steel-manning rationales and dismissed-finding priors are the substance; Phase 5b exists exactly to prevent this anti-pattern

## Inspiration & deliberate exclusions

This skill distills the quantitative review patterns from `codexstar69/bug-hunter` (Hunter / Skeptic / Referee adversarial flow) into Claude-native checkpoints.

**Deliberately NOT included:**
- **Auto-fix with canary rollout** — too aggressive on production code; fixes belong to the user's review workflow
- **Hard-exclusion lists for "settled false-positive classes"** — creates blind spots, especially for prompt-injection-class issues that vendor exclusion lists ignore
- **LLM-readable instruction files outside this `SKILL.md`** — minimizes the prompt-injection surface area; everything Claude needs is in this single file
