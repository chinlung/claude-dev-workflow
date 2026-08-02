# session-reflect

> Session-end reflective review — a cheap Stop-hook gate plus a two-stage skill that proposes up to 5 **verified** improvement suggestions (out-of-scope bugs, pre-existing issues, adjacent optimizations, knowledge gaps), executes the ones you pick, and parks the rest in a backlog.

## Quick start

```bash
# 1. Install (one-time)
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install session-reflect@scl-claude-plugins
```

That's it. At the end of any substantive session the Stop hook fires once, and Claude reviews the session before letting it end. Run `/reflect` anytime to trigger the same review manually.

## How it works

```
Stop event
  └─ reflect-gate.sh (bash, fail-open)
       ├─ loop guard (stop_hook_active) / once-per-session flag / <10-line floor
       ├─ already-reflected detection (matches real Skill-invocation shape only —
       │   merely *mentioning* the plugin never suppresses the review)
       ├─ mid-interaction detection (pending question → yield without consuming
       │   the session's single trigger; parse failure → approve, per contract)
       └─ block → Claude invokes the reflect skill:
            Stage 1  quick triage — routine session? one-line "nothing to review", done
            Stage 2  four-lens sweep — every candidate needs a concrete evidence anchor
            Stage 2.5 verification — inline four-filter self-review (anchor actually
                     Read, existing safeguards, deliberate design, observable value)
                     + one adversarial verifier subagent framed to refute, not confirm
            Stage 3  multi-select prompt (2-4 options per question, per tool limits)
                     → chosen: execute now, while context is hot
                     → unchosen: append to .claude/reflect-backlog.md
```

## The backlog

`.claude/reflect-backlog.md` in your project root. States: `[pending]` (deduped on later runs, re-open with `/reflect`) and `[rejected]` (kept forever as dedup evidence, so a suggestion you refused never comes back). Completed entries are deleted. The plugin never commits this file — versioning it is your call.

## Design guarantees

- **Fail-open everywhere** — a broken hook must never trap you in a session; every error path approves.
- **No enthusiasm without evidence** — suggestions with no `file:line` (or concrete conversational fact) are dropped before you see them; survivors face an adversarial verifier that inherits the main-loop model (verification is never downgraded).
- **One trigger per session** — flag file + `stop_hook_active` double guard; yielding to an in-flight interaction preserves the trigger instead of consuming it.

## Testing

```bash
bash plugins/session-reflect/tests/gate.test.sh   # 18 assertions, also run in CI
```

## Relation to session-learning

Complementary: **session-learning** saves *lessons* (patterns worth remembering), **session-reflect** proposes *actions* (work worth doing next). Both hook the Stop event independently, each with its own once-per-session guard.

Design doc: [`docs/session-reflect-design-2026-08-03.md`](../../docs/session-reflect-design-2026-08-03.md) · Plan: [`docs/session-reflect-plan-2026-08-03.md`](../../docs/session-reflect-plan-2026-08-03.md)
