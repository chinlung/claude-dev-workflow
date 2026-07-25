# Triage Decision Tree

**When to read this:** Phase 3 (triage + EV decisions) and any time there is a conflict between confidence, EV, severity label, and status — particularly when a finding "feels important" but the math says dismiss, or vice versa.

**Location:** `<plugin-root>/tools/triage-decision-tree.md`, where `<plugin-root>` is `plugins/code-audit-rigor/`.

---

## Primary Decision Tree: Evidence → Decision Field

```
For each candidate finding:
│
├─ Do I have a verbatim quotedCode anchor from the file?
│   ├─ No → RE-READ the file now. Do NOT proceed without anchoring.
│   └─ Yes → continue
│
├─ Compute confidence% (honest estimate, 0–100):
│   ├─ < 33% → EV will be strongly negative. DISMISS unless Critical.
│   ├─ 33–67% → borderline; compute EV to decide
│   └─ > 67% → EV likely positive; compute EV to confirm
│
├─ Compute EV = (conf/100 × points) − ((100−conf)/100 × 2 × points)
│   ├─ EV > 0 → ACT or INVESTIGATE_FURTHER (see severity split below)
│   ├─ EV < 0 → DISMISS (but record rationale)
│   └─ EV = 0 → borderline; default to INVESTIGATE_FURTHER
│
└─ Severity split for EV > 0:
    ├─ Critical or High → ACT (cost of inaction too high)
    ├─ Medium → ACT if conf ≥ 80%, else INVESTIGATE_FURTHER
    └─ Low → ACT only if conf ≥ 90%; otherwise DISMISS with note
```

---

## Decision Field Values

| Decision | Meaning | When to use |
|----------|---------|-------------|
| `ACT` | Finding confirmed; fix required | EV > 0, anchored, steel-manned |
| `INVESTIGATE_FURTHER` | Finding probable but needs more evidence | EV borderline, or Critical/High at lower confidence |
| `DISMISS` | Finding ruled out; rationale recorded | EV < 0 after steel-manning |
| `USER_REVIEW` | Cannot determine without domain knowledge | Ambiguous business logic, policy decisions |

---

## Conflict Resolution: When Math and Intuition Disagree

### Case A: EV < 0 but the finding "feels critical"

**Resolution protocol:**
1. Re-check the confidence estimate — is 50% an honest number or defensive hedging?
2. Re-read the file:lines to push confidence above 67% or below 33%
3. If after re-reading confidence is still 50–60% on a Critical finding: set to `INVESTIGATE_FURTHER`, not `DISMISS` — the cost asymmetry at Critical severity makes "dismiss on math alone" dangerous
4. Record: "Confidence insufficient for ACT; marking INVESTIGATE_FURTHER pending additional evidence"

**Example:**
- Auth bypass (Critical, 10 pts) at 50% confidence
- EV = 0.5 × 10 − 0.5 × 2 × 10 = −5 → math says dismiss
- But: 50% confidence on auth bypass is "I'm not sure" — that's insufficient investigation
- **Correct action:** re-read the auth path, push confidence above 67% or below 33%, then re-decide

---

### Case B: High severity label but unanchored quote

**Resolution protocol:**
1. The `quotedCode` must be found verbatim in the claimed file:lines (±10 lines)
2. If not found: mark `UNVERIFIED_REFERENCE`, reduce confidence by 30 points, recompute EV
3. A 30-point confidence reduction typically drops most findings below the 67% threshold → DISMISS

**Example:**
- Finding claims "SQL injection at `src/queries.py:145`" with quotedCode `f"SELECT * FROM {table}"`
- Grep finds this string at line 167, not 145, and the surrounding code shows `table` comes from an allowlist enum, not user input
- **Correct action:** correct line to 167, re-read context, update claim to reflect the allowlist guard → likely DISMISS or downgrade to Low

---

### Case C: EV above zero but steel-manning weakens it

**Resolution protocol:**
1. Run all six OC checks from `STEEL_MANNING.md`
2. Each passed counter-check reduces confidence per the delta rules in `STEEL_MANNING.md`
3. Recompute EV with the updated confidence
4. If EV drops below 0 after steel-manning: DISMISS (steel-manning is the corrective to over-confidence)

**Example:**
- Medium injection finding at 75% confidence, EV = +0.6
- OC-2 (framework parameterization): framework uses prepared statements for all queries in this module
- Confidence drops by 25 → 50% → EV = 0.5 × 3 − 0.5 × 2 × 3 = −1.5 → DISMISS

---

## Common Anti-Patterns in Triage

### Anti-pattern T1: Confidence Without Source

**Symptom:** Finding states "confidence: 85%" but the crossReferences have no quotedCode, or the quotedCode was not found in the file.

**Why it fails:** Confidence is meaningful only when anchored to actual code. An unanchored 85% is LLM confabulation, not evidence-based estimation.

**Recovery:** Run Phase 4 reference anchoring check before assigning any confidence number. Confidence is set after anchoring, not before.

---

### Anti-pattern T2: High Severity but Unanchored Quote

**Symptom:** A Critical finding is marked ACT, but the crossReference quotedCode doesn't appear in the claimed file.

**Why it fails:** High severity amplifies the impact of false positives (−3 per FP) and wastes the most investigation time. An unanchored Critical claim is almost certainly an LLM reconstruction.

**Recovery:** Apply the Case B protocol above. Mark `UNVERIFIED_REFERENCE`, reduce confidence 30 points, recompute EV. Most Critical unanchored findings drop to DISMISS or INVESTIGATE_FURTHER.

---

### Anti-pattern T3: EV Below Zero but Scary Label

**Symptom:** A "Critical" or "Security" label is attached to a finding with EV = −2, and the reviewer is reluctant to DISMISS it because it "sounds serious."

**Why it fails:** The severity label describes impact if real; the EV already accounts for impact via the `points` value. A Critical finding at 30% confidence has EV = −8 — the math already says it is more likely a false positive than a real critical issue.

**Recovery:** Follow the decision tree. If confidence is genuinely 30% on a Critical finding, that means "I'm 70% sure this is fine." DISMISS with rationale. If that confidence estimate feels wrong, re-read the code to update it.

---

### Anti-pattern T4: Skipped Finding Without Rationale

**Symptom:** The Phase 5 report's DISMISSED section has entries with no steel-manning argument — just "dismissed" or "false positive."

**Why it fails:** The dismissed-findings rationale is the primary value for future reviewers. "Dismissed" without explanation provides zero value as a prior — the next reviewer will have to re-do the same investigation.

**Recovery:** Every DISMISS entry must include: (a) the specific counter-argument; (b) the confidence after steel-manning; (c) a "future note" about conditions under which the dismissal would not apply.
