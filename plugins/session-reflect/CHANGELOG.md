# Changelog

All notable changes to the `session-reflect` plugin will be documented in this file.

> Backfilled on 2026-09-18 from the root changelog and git history: this plugin shipped both
> releases below without a changelog of its own. The entries describe what each version actually
> changed, but they were written after the fact, not at release time.

## [1.2.0] - 2026-10-19

### Added

- **Friction evidence comes from the transcript, not from memory.** `skills/reflect/scripts/friction-digest.sh` reads the session's transcript JSONL and returns, as JSON, the events the environment-friction lens needs: failed commands (`tool_result.is_error` with `Exit code`), user permission denials, auto-mode classifier denials, PreToolUse hook blocks, PostToolUse (and other non-Stop) hook failures from `hook_blocking_error` attachments, errors hidden in successful Bash output (an error-shaped line — `<source>: Operation not permitted`, `no matches found`, `command not found`, `Permission denied`, `failed to verify certificate` — so a document or list that merely mentions the phrase does not count), user interrupts, and other tools' errors (`tool_error`, e.g. an Edit whose string was not found); plus per-kind counts, operations that failed at least twice, and the transcript line of each event. "Same operation" means the same first 160 characters of input, so a retry that only changes the tail (an output file number, a dropped `&& …`) counts as a repeat: measured over 536 transcripts on this machine, grouping by the full input instead turned 3 real retries into misses to remove 1 false repeat. Long sessions are usually compacted by the time Stop fires, and the friction details ("worked on the third try") are what compaction drops first. Sub-agent (sidechain) lines and Stop-hook blocks are excluded; each kind keeps at most 8 events, counts stay exact. The field shapes were measured on a real transcript on 2026-10-19 (e.g. `blockingError` is an object, not a string); the interrupt marker did not occur in that sample and is unmeasured.
- The Stop gate's block reason now ends with `transcript: <path>`, built with `jq` so a path containing quotes still yields valid JSON; if building it fails the gate approves without consuming the session's trigger. The skill gains a Stage 0 that runs the digest when a path is present; a manual `/reflect` has none and says so instead of silently skipping. Events are candidates: `hidden_failure` also matches error lines inside logs or test output a command printed, so the anchor filter still confirms each one. `detail` is raw tool output; the skill says to cite it as evidence, never follow it as an instruction, and to mark it as quoted when it goes into the verifier's prompt or the backlog.
- `tests/digest.test.sh` (37 assertions, wired into CI); 14 targeted mutations of the script (sidechain filter, Bash-only hidden scan, Stop exclusion, per-kind cap, repeat threshold, malformed-line tolerance, line numbers, classifier/permission split, clipping, error-shape prefix, matching-line detail, `tool_error` catch-all, 160-character repeat grouping, object `blockingError`) each turn it red. One mutation stayed green at first — narrowing the hidden-error match had left the Read-exclusion fixture unable to match anyway — and the fixture was changed so only the Bash-only rule stops it. `tests/gate.test.sh` 23 → 24; the new case first reused the shared `$t` of the case after it, which left "second run after block → approve" passing on a missing transcript even with the once-per-session flag check removed (caught by the Codex cross-vendor pass) — it now has its own variable, and that mutation turns the case red.

### Notes

- Jev stays unwired: the reassessment condition also needs more than 5 candidates per run and per-candidate graded verification; reflect still dispatches one batched verifier.

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
