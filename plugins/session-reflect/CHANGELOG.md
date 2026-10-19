# Changelog

All notable changes to the `session-reflect` plugin will be documented in this file.

> Backfilled on 2026-09-18 from the root changelog and git history: this plugin shipped both
> releases below without a changelog of its own. The entries describe what each version actually
> changed, but they were written after the fact, not at release time.

## [1.1.0] - 2026-10-19

### Added

- **A fifth lens, environment friction.** The four existing lenses all point at the work product (the next thing to do); none asked what in the agent's environment made this session slow or wrong, so the same friction recurred session after session without ever being proposed as a fix. The new lens maps observed symptoms to remedies: a long hunt for one file or fact → a navigation pointer in an on-demand doc; a mistake a machine could have caught → a check, or wiring up an existing one; a review miss → a review rule; an instruction that was present but not followed → turn it into a mechanism or delete it; expensive or repeated tool calls; missing information; recurring permission/sandbox denials. Its evidence anchor is the friction event itself plus the path the remedy would change. Adapted from a user-invoked `retro` skill whose whole subject is the environment.
- **A fifth inline filter, placement.** Environment-friction suggestions, and any suggestion to add a rule, doc or check, must first look for an existing check that is unwired, conditionally skipped or silently failing (that becomes the suggestion), then pass a placement ladder: a mechanical violation gets a deterministic check that reads environment facts and has a downstream consumer; a judgement call needed only for some work or files goes to an on-demand layer; only what every session needs and no machine can enforce goes in an always-loaded instruction file, preferably as a one-line pointer. A remedy that is really "remember this" belongs to session-learning and is not proposed here. The adversarial verifier checks environment suggestions for both.
- **Activation conditions per lens.** A lens whose condition does not hold is skipped instead of being filled with a candidate for the filter to throw away.

### Changed

- **Triage no longer skips a routine or abandoned session that had friction.** A session of pure git or command running used to exit as routine even when the same operation failed several times or kept hitting a permission wall, and work abandoned after such failures exited as "no substantive output" — the most useful signals for the new lens. When friction occurred, those two skip reasons no longer apply: the unfinished-task and already-reviewed checks still run, and if neither hits, only the environment-friction lens runs. The Stop gate's block reason now says the same, so the first instruction the model reads does not contradict the skill.
- **The gate's pending-question check reads the last 400 characters, not the last character.** A closing question followed by a list and a remark ("shall I implement this? Scope: … I will handle X separately.") was missed and the review fired mid-interaction (observed 2026-10-19). An ASCII `?` counts only before whitespace, end of text or a closing mark, so `?query` in a URL and `${x:?}` do not. Trade-off: a question mark inside the window that does not ask the user anything (a heading, a quoted question, a self-answered one) now also makes the gate yield. The flag is not consumed and the next Stop decides again, but if that message is the session's last, the session goes unreviewed. The old miss was no cheaper: it fired mid-interaction and spent the session's only trigger. `tests/gate.test.sh` 18 → 23 assertions; each new case was confirmed red against the 1.0.2 gate or a targeted mutation.

## [1.0.2] - 2026-09-18

### Added

- `CHANGELOG.md` reaches installed copies. The file was backfilled in marketplace 1.10.11 without a version bump, and the plugin cache is keyed by version (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`) — an unchanged version is never re-fetched, so the backfill stayed in the repo and never shipped. Measured on this machine: the cached `1.0.0/` tree lacks the README added in `c7c8169` (also without a bump) while `1.0.1/` has it, because a later bump carried it in. No behaviour changes in this release; it exists to deliver the changelog.

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
