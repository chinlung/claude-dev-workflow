# Changelog

All notable changes to the `session-reflect` plugin will be documented in this file.

> Backfilled on 2026-09-18 from the root changelog and git history: this plugin shipped both
> releases below without a changelog of its own. The entries describe what each version actually
> changed, but they were written after the fact, not at release time.

## [1.0.1] - 2026-09-17

### Fixed

- **The review playbook never loaded.** The plugin shipped both `commands/reflect.md` and `skills/reflect/SKILL.md`, which resolve to the same qualified name `session-reflect:reflect`; the command shadowed the skill, so a Skill-tool call returned the command body — whose only content was "call the `session-reflect:reflect` skill" — and the playbook itself was never read. Both the manual path and the Stop-hook path (`reflect-gate.sh` asks for that same name) hit the self-reference. The redundant command is removed: skills are user-invocable by default (`/session-reflect:reflect`), and `skills/` is the documented layout. The qualified name is unchanged, so the gate's already-reflected pattern and `tests/gate.test.sh` needed no change.

### Notes

- Verified end-to-end on 2026-09-17: with 1.0.1 installed and plugins reloaded, a Skill-tool call returns the playbook body; the same session had reproduced the 1.0.0 bug an hour earlier, making it a like-for-like comparison. Not exercised: the Stop-hook-triggered path under 1.0.1 (the gate fires once per session and had already fired); it requests the same qualified name, so the same resolution applies.

## [1.0.0] - 2026-08-03

### Added

- Initial release — session-end reflective review. A fail-open bash Stop-hook gate (loop guard via `stop_hook_active`, once-per-session flag file, a <10-line substantiveness floor, and mid-interaction detection that yields without consuming the session's single trigger) hands off to a two-stage skill: quick triage (routine sessions exit with a one-line "nothing to review"), then a four-lens sweep — out-of-scope findings, pre-existing issues, adjacent optimizations, knowledge gaps.
- Candidates must survive a verification layer before the user sees them: an inline four-filter self-review (anchor actually Read, existing safeguards, deliberate design, observable value) plus one adversarial verifier subagent (main-loop model, never downgraded) framed to refute rather than confirm.
- Up to 5 survivors are offered in a single `AskUserQuestion` call — two options when one survives, one multiSelect question for 2-4, split 3+2 for 5; chosen ones execute in-session, unchosen ones land in `.claude/reflect-backlog.md` (`[rejected]` entries kept forever as dedup evidence). The plugin never commits the backlog.
- `tests/gate.test.sh` — 18 fixture assertions covering the gate, wired into CI. Design: `docs/session-reflect-design-2026-08-03.md`.
