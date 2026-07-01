# Loop Design Review — 4 Plugins vs. "Getting Started with Loops"

**Date:** 2026-07-01
**Scope:** `code-audit-rigor` (`/review-branch`, `/review-pr`, `/audit-review-fix`), `multi-agent-debate` (`/debate`), `high-precision-dev` (`/start`), `openspec-superpowers-workflow` (6-phase skill)
**Method:** Fetched https://claude.com/blog/getting-started-with-loops for the design framework. Read `code-audit-rigor` and `security-audit` (the stated inspiration for the schema+validator layer) directly. Dispatched 3 independent research agents (one per remaining plugin) to read every command/agent/schema/validator file in full. All load-bearing cross-plugin claims were personally re-verified against source (`debate.md`, `start.md`, `security-audit`'s `VALIDATION-AND-REPORTING.md` + `validate-findings.cjs`) per this repo's anti-hallucination discipline (`親自 Read 才算數`).

> **Revision note (v2):** This document was rewritten after the plugin author supplied the design-intent history. The original v1 treated the four plugins as peers with a flat priority menu. v2 reframes around the author's actual three-layer intent stack (below) and the security-audit reference model, which sharpens the per-plugin gap sizing and reorders the fixes. The detailed per-plugin findings from v1 are retained in §6.

---

## 0. Decision & execution log (2026-07-01)

The author chose **selective consolidation** over both "complete L2 everywhere" and "revert 893821c entirely" (a full revert was rejected because 893821c is also where code-audit-rigor's *working* live validators, the CI + PostToolUse hook, and STEEL_MANNING came from — reverting throws out the good with the incomplete). Applied the "lift vs marginal value" criterion per plugin:

| Plugin | Decision | Done |
|---|---|---|
| **code-audit-rigor** | Keep as-is (L2 already live for review-branch/pr; audit-review-fix uses inline Workflow `schema:`) | — (follow-on enhancements only: §6.1) |
| **openspec-superpowers** | Keep; wire own `.cjs` as a cheap pre-check | follow-on (#3) |
| **multi-agent-debate** | **Complete L2** — dormant-but-valid, low lift, best loop mechanics | ✅ Phase 6 `6a` structural gate wired; cross-field referential integrity added to `validate-debate-output.cjs` (+2 mutations); coverage declaration schematized as a required, machine-checked `coverage` field (+4 mutations); Phase 4 convergence criteria reconciled with `orchestrator.md`; version 1.1.0→1.2.0 |
| **high-precision-dev** | **Remove L2** — dead code (validated a JSON shape no agent emits); high completion lift; rigor already maximal via agent diversity | ✅ removed `schema/`, `validators/`, fixtures + `validate-fixtures.cjs` wiring; README/`start.md` dangling refs cleaned; version 1.1.0→1.2.0 |
| — | Remove stray `t.json` (a prior-debate test artifact committed to repo root in 893821c) | ✅ `git rm` |

Machine check after consolidation: `node scripts/validate-fixtures.cjs` → **133 passed, 0 failed** (was 148; −21 removed high-precision checks, +6 new debate mutations: 2 cross-field + 4 coverage). Marketplace metadata 1.8.5→1.8.6.

**Follow-on items — completed the same session (separate commit):** openspec Phase 1 gained a lenient local pre-check that runs the bundled validator before `openspec validate --strict` (1.2.1); `/review-pr` Phase 3 was hardened to the baseline + exit-code-sentinel regression discipline already audited in `/audit-review-fix`, and `/review-branch` gained `--focus <pathspec>` + a Phase 2 confidence field (code-audit-rigor 1.5.0); high-precision's unimplemented `--phase N` arg hint was removed and the `disproof-agent` non-registration was investigated — **not a defect** (its frontmatter is identical to sibling agents that register; it was the under-versioned-PR-#4 reload artifact, resolved by the 1.2.0 bump + a reload) (1.2.1). **Dropped (not pursued):** the canonical-pattern doc (scaffolding for the not-taken "complete everything" path), the skill/audit-review-fix `.cjs`-exposure decision (resolved: existing mechanisms suffice), openspec Phase-6 spec-drift check, debate code-grounding mode. Coverage-declaration schematization for debate (the higher-value L2 stretch) — initially deferred — was completed in the consolidation itself: `debate-output.json` now carries a required, machine-checked `coverage` field, so an uncovered aspect can no longer be silently dropped or left unexplained.

---

## 1. Design-intent stack (from the plugin author)

These four plugins' current state is the result of three intentional layers, built in order:

| Layer | When | Intent | Source model |
|---|---|---|---|
| **L1 — deterministic checks** | earliest | `code-audit-rigor` skill mechanizes coverage / rule-specialization / reference-accuracy — the three things that previously relied on LLM self-discipline | alibaba/open-code-review's deterministic engineering layer |
| **L2 — structured output + validation** | this morning (2026-07-01, PR #4) | Add a JSON schema + zero-dependency validator to **all four** plugins to "shift from prompt discipline to explicit, machine-checkable output contracts" — *uniformly* | cloudflare/security-audit-skill (structured-output + independent-verification phases) |
| **L3 — agentic loops** | this session | Push verification + automation further using the loop concept | claude.com "Getting Started with Loops" |

The `code-audit-rigor` plugin itself is a consolidation of four originally-independent features: the `code-audit-rigor` skill (L1), the `/audit-review-fix` workflow (distilled from real ultracode/Workflow runs into prompt+JS), and `/review-branch` + `/review-pr` (migrated from personal command prompts so other installers can use them).

**The central finding of this review is about L2, and it is a prerequisite problem for L3.**

---

## 2. Headline finding: L2 was NOT completed uniformly, and that blocks L3

The article's core premise for a loop: *encode verification as a script so the agent can self-check, and rerun the failing step until the check passes.* That requires a **machine-checkable gate on the live execution path.** For 3 of the 4 plugins, the L2 validator is **not** on the live path — so there is currently nothing for an L3 loop to gate on. **L2 is a hard prerequisite for L3.**

How deeply the L2 contract is wired into each plugin's *live* run, measured on three axes:

| Plugin | ① Emits a machine-readable artifact | ② Structural validator (script) runs as a live gate | ③ Semantic verification (agent) runs live | L2 gap |
|---|---|---|---|---|
| **code-audit-rigor** (review-branch/pr) | ✅ `*-results.json` | ✅ `review-branch.md`:99-105 / `review-pr.md`:97-101,115-119 run `node validate-*.cjs` and gate on it | ✅ Phase 2 per-suggestion sub-agents | **none** |
| **openspec-superpowers** | ✅ `openspec/changes/<name>/` | ✅ **but via the external `openspec validate --strict` CLI** (Phase 1 step 4, Phase 6 C4); the plugin's *own* `.cjs` is CI-only, self-labeled a "lenient pre-check" (`README.md`:93) | ⚠️ human-driven (Phase 5) | **smallest** — a live gate already exists; the new `.cjs` just isn't used as a cheap pre-check |
| **multi-agent-debate** | ⚠️ schema shape matches agent output, but no JSON is actually emitted | ❌ Phase 5.5 evaluates the validator **agent's prose verdict**; never runs `node validate-debate-output.cjs` (verified by full read of `debate.md`) | ✅ validator agent (Phase 5.5) | **medium** |
| **high-precision-dev** | ❌ all 6 agents emit **prose** (`IMPL_A_REPORT.md`, `CRITIQUE.md`, `ATTACKS.md`, `DISPROOF.md`, `VERIFICATION.md`) — no JSON at all | ❌ schema validates a shape **nothing produces**; `start.md`:198 references the schema once as reading-guidance only | ✅ verifier/critic/adversary/disproof | **largest** |

**Root cause (same shape as the version-bump gap fixed earlier this session):** PR #4 landed the *meta* layer well — CI (`.github/workflows/validate.yml`) + a PostToolUse hook keep the validators themselves from regressing, and "148 checks pass" is genuinely true *for the fixtures*. But the *product* wire — actually calling the validator during a real `/debate` / `/start` / Phase-1-6 run — was only carried through for the two commands that already had the pattern before today (`review-branch`, `review-pr`). For the other three, schema+validator files were added without updating the command/agent files that would invoke them.

**Why this is not just tidiness:** a validator that only runs against hand-authored fixtures manufactures false confidence. "CI green" reads as "output contract enforced" when, for 3 of 4 plugins, it enforces nothing at runtime. `high-precision-dev` is the worst case — the schema validates a JSON shape that *cannot occur*, because no agent is ever asked to produce it.

---

## 3. The reference model (security-audit) — what "done" looks like

The author modeled L2 on `security-audit`. Reading it settles what the intended end-state is — and it is unambiguously a **live gate + a correction loop**, not CI-only meta-tooling:

- **Phase 5 — structural gate (live):** write `findings.json` conforming to `report-schema.json`, then `node validate-findings.cjs findings.json`, and **"Fix any failures before proceeding"** (`VALIDATION-AND-REPORTING.md`:65). Explicitly framed as *structural only* — "it confirms the JSON conforms to the schema, not that the findings are correct."
- **Phase 6 — semantic verification + correction loop:** one **fresh agent per finding** ("You did NOT write this finding") re-checks every claim against source → `VERIFIED` / `CORRECTED` / `REJECTED`; a `CORRECTED` finding updates the JSON and **re-runs the schema validation** (`:102`). Prose report and JSON "must not disagree" (`:105`).

Two takeaways that drive the priority below:

1. **Structural (script) and semantic (agent) checks are complementary layers, not substitutes.** The script guarantees a well-formed, machine-checkable artifact; the fresh agent catches the blind spots the authoring agent can't (`:69`). `debate` and `high-precision-dev` already have the *semantic* layer (their whole premise) — what they lack is the *structural* layer and the machine-readable artifact that makes the loop mechanizable.
2. **The L3 loop is already embodied in the reference** (Phase 6's CORRECTED → re-validate). So the L3 target for each plugin is concrete and copyable, not open-ended.

---

## 4. Reassuring corollary: the L3 loop scaffolding mostly already exists

L3 is a smaller lift than it looks, because the loops are already built — they just gate on the wrong thing:

- **multi-agent-debate** already loops: Phase 4→2 on non-consensus (up to `--max-rounds`), and validator-`rejected`→Phase 2 (`debate.md`:96-101,140). These gate on *semantic* verdicts. Once L2 is live, wire the *structural* validator's exit code into the same loop's exit condition.
- **high-precision-dev** already loops: the 3-iteration-capped fix loop (`start.md`:115-120) and the Type-D escalation back to Phase 1/2. Same story — add the structural gate to the loop's exit condition.
- **code-audit-rigor** routine commands are deliberately single-shot; forcing a loop there would be the article's "over-engineering a simple task" anti-pattern. The one exception is `review-pr`'s fix phase, which should adopt the "on test-fail, don't hand back partial work, loop back" discipline `audit-review-fix` already implements.

So L3 for the two loop-bearing plugins ≈ "connect the now-live structural gate into the loop's existing exit condition," not "build a loop from scratch."

---

## 5. Revised priority

### Tier 0 — Define the canonical pattern (no code; do first)
Extract one **canonical output-contract pattern** from the two implementations that already work (`security-audit` Phase 5+6, `code-audit-rigor` review-branch): *emit machine-readable artifact → live structural-validate as a gate → fresh-agent semantic verify → on correction, update artifact + re-validate.* Apply it uniformly to the other three, so each doesn't reinvent a slightly different wiring. This directly serves the author's original "uniform strengthening" intent.

### Tier 1 — Complete L2 (put the structural validator on the live path). Cheap → expensive:
| Order | Plugin | Work | Size |
|---|---|---|---|
| 1 | **openspec-superpowers** | One line in `phases.md` Phase 1/6: run the plugin's own `.cjs` as a free pre-check before the expensive `openspec validate --strict`. (Warm-up; a real gate already exists.) | 🟢 |
| 2 | **multi-agent-debate** | Phase 5.5/6: emit `debate-output.json` → run `validate-debate-output.cjs` as a gate → then final output. Plus reconcile the `debate.md` vs `orchestrator.md` convergence-criteria inconsistency (score-gap ≥8). Clean analog of the working code-audit-rigor pattern. | 🟡 |
| 3 | **high-precision-dev** | Make `verifier.md` also emit schema-conformant `findings.json`/`coverage.json`, then add a live validate step. Largest lift (needs a new structured-output *production* step, not just a validate call); do last, with two templates in hand. | 🔴 |

### Tier 2 — Wire L3 loops (only possible once Tier 1 makes the gate live)
Connect each now-live structural gate into the plugin's **existing** loop exit condition (validator FAIL → route back to the responsible phase → rerun → re-validate, capped). For code-audit-rigor specifically: port `audit-review-fix`'s already-audited `extractTestSignals`/`computeTestsPass`/baseline-capture (or at least the `WF_TEST_EXIT=<code>` sentinel) into `review-pr.md` Phase 3/4 — this is simultaneously a correctness fix and the L3 touch-point (see finding #1).

### Tier 3 — Judgment calls + housekeeping (need a scoping decision or are pure doc/reality mismatches)
- 🔵 openspec Phase-6 mechanical spec-drift check (needs a definition of what "spec matches code" means)
- 🔵 debate optional "ground in real code" mode
- 🔵 code-audit-rigor optional multi-angle fan-out above a diff-size threshold
- 🟢 high-precision `--phase N`: implement or remove from `argument-hint`
- 🟢 high-precision `disproof-agent`: investigate why it's absent from this session's registered agent types (plausibly tied to the same under-versioned PR #4; may just need a plugin reload)

### Two orderings to choose from
- **Cheap-first (recommended):** openspec → debate → high-precision. Builds a working template incrementally; each completed plugin becomes the reference for the next; matches the article's "start simple / pilot on a slice first."
- **Risk-first:** high-precision → debate → openspec. Fixes the most misleading "CI-green-but-enforces-nothing" case first.

---

## 6. Detailed per-plugin findings (retained from v1)

Sizes: 🟢 small (bounded, low-risk, clear) · 🟡 medium (real design change, scoped) · 🔴 large · 🔵 judgment call (needs scoping first).

### 6.1 `code-audit-rigor` — L2 done; items are L3 polish + one correctness port
- **#1 🟢 (also the L3 touch-point):** `review-pr.md`:109,115-119 regression check is the *pre-hardening* naive form ("run the suite, confirm no regression") — no baseline capture, no exit-code sentinel, no pre-existing-vs-new-failure distinction. `audit-review-fix`'s own `CHANGELOG.md` [1.3.2]/[1.3.3]/[1.3.4] documents three separate real fail-open bugs fixed in exactly this logic (e.g. a build broken by the fix reported `READY_FOR_COMMIT`). Port the audited pattern.
- **#2 🟢:** No cost/scope knobs on review-branch/review-pr; add `--focus <pathspec>` (cheapest high-value knob per `audit-review-fix`'s own experience).
- **#3 🟡:** Phase 2 verdict is binary PASS/FAIL; add a `confidence` (0-100) field so borderline verdicts surface instead of collapsing to one bit.
- **#4 🔵:** Optional 2-3-angle fan-out above a diff-size threshold — needs a decision on where the line sits so it doesn't blur the deliberate routine/rigor tiering.

### 6.2 `multi-agent-debate` — strongest loop mechanics of the four; missing the structural gate
- **#5 🟡:** Structural validator never invoked live (see §2). Emit `debate-output.json` + run `validate-debate-output.cjs` before trusting the Phase 5.5 routing table.
- **#6 🟢:** Convergence criteria inconsistent — `debate.md`:96-101 lists only 2-agent-consensus + round-cap; `orchestrator.md`:104-109 adds "分數差距 ≥8" with no stated composition rule. Reconcile (add to `debate.md` with explicit precedence, or remove from `orchestrator.md`).
- **#7 🔵:** Zero code/evidence grounding anywhere (`validator.md`:15 scopes itself to the debate transcript's own claims). Appropriate for pure architecture debates; consider an optional code-grounding mode when invoked on a checkable codebase.

### 6.3 `high-precision-dev` — most sophisticated isolation/loop; starkest schema decoupling
- **#8 🔴:** Schema is decoupled from what agents produce (see §2 — the largest L2 gap). Either make `verifier.md` emit schema-conformant JSON + add a live validate step, or explicitly relabel the schema as aspirational. Current state (CI-green over a shape nothing produces) is worse than either alone.
- **#9 🟢:** `--phase N` advertised in `start.md`:3 frontmatter but never parsed. Implement resume-from-phase or remove.
- **#10 🟢:** `high-precision-dev:disproof-agent` dispatched at `start.md`:101-104 but absent from this session's registered agent types (the other five are present). Investigate — may be a registration/cache issue rather than a file defect.

### 6.4 `openspec-superpowers-workflow` — cross-session filesystem loop; smallest L2 gap
- **#11 🔵:** No mechanical spec-drift check at Phase 6 — nothing cross-checks the rewritten spec against Phase 4's actual code diff; `RECONCILIATION-CRITERIA.md` C3 only verifies `tasks.md` is unchanged. Even a shallow path-level diff check would help.
- **#12 🟢:** Validator is CI-only; add one line to `phases.md` Phase 1/6 to run it as a free pre-check before `openspec validate --strict`.
- **#13 🔵 (low urgency):** Phase-completion criteria (`PHASE-IDENTIFICATION.md`:69-75) are judgment calls ("substantive content, not placeholder"); the multi-session filesystem nature makes a mechanical check inherently harder than the other three plugins' single-session checks.

---

## 7. Considered non-issues (checked against the article, no gap — recorded so they aren't re-litigated)
- `review-branch`/`review-pr` staying turn-based/single-shot — correct scoping for the "routine" tier, not a gap.
- `multi-agent-debate` perspective count fixed at 3 — "avoid over-parallelizing" satisfied by construction.
- `high-precision-dev` having no cost/budget knobs — its premise is "worth the p→p⁴ cost for high-stakes work"; lightweight-by-default was never the goal.
- `openspec-superpowers-workflow` running all 6 phases regardless of size — it already has a binary skip condition (small bug fix → don't trigger); a partial mode wasn't asked for and isn't well-defined for a spec-driven flow.

---

## 8. `/debate` re-examination of the high-precision-dev decision (2026-07-01)

The 1.2.0 "remove HP's L2, don't add L3" decision was stress-tested by running the now-live-wired `/multi-agent-debate:debate` on "is HP suitable for (re-)adding L2/L3?" — three adversarial perspectives (keep-removed / add-a-thin-prose-anchored-ledger / seam-decomposition) plus a source-reading critic. Source-verified outcome:

- **The removal was correct.** All three perspectives and the critic agree the removed `findings.schema.json` (schematizing `verified`/`passed`/`outcome` verdicts) was a category error — those are judgment verdicts, not machine facts.
- **No machine consumer = theater** (the critic's decisive, source-verified point). A machine-readable contract is only non-theater if a machine reads it and acts. HP terminates in a human-read report; its only possible consumer is the existing capped fix-loop, which already runs on exit code + severity. That was the dead code's deep cause — deeper than "wrong shape."
- **The one worthwhile addition** (implemented — HP 1.3.0): a **controller-run environmental gate** that actually runs the SPEC tests and captures the exit code after the verifier merges, wired into the capped fix-loop as an extra exit condition. Governing **meta-rule**: *a gate is justified iff (a) it reads an environmental fact (exit code / git / fs / loop counter), not an agent assertion, **and** (b) a downstream consumer acts on it.* It deliberately does NOT reintroduce a structured-output contract.
- **Deeper finding — the `p→p⁴` claim is overstated** (the critic's second blind spot, source-verified, not yet acted on): `implementer-a.md` and `implementer-b.md` are byte-identical except the A/B label — same base model, same SPEC/CONSENSUS, same framing, differing only in worktree output-isolation. Two identically-prompted instances of one model make *correlated* errors on systematic misreadings (the dangerous class); worktree isolation stops plagiarism, not correlated independent error. Combined with the shared-base-model correlation floor (a blind spot in the weights is shared by all 4–6 roles) and `CONSENSUS.md` as a common-mode single point of failure (a wrong Phase-1 resolution is trusted by every downstream channel), the multiplicative `p⁴` does not hold as stated. The real compression is role-diversity-driven (builder vs attacker vs checker — the genuine engine) and unquantified. **Recommended follow-ups (not yet done, need sign-off):** (1) reframe the claim honestly in `plugin.json`/`README` (from a specific `p⁴` to "role-diverse adversarial review reduces systematic-error escape, bounded by a shared-model correlation floor"); (2) give `implementer-a`/`-b` genuinely different framings (e.g. spec-first/defensive vs test-first/simplicity) so the weakest independence leg actually decorrelates.
