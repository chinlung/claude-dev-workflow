# Changelog

All notable changes to the `session-learning` plugin will be documented in this file.

> Backfilled on 2026-09-18 from the root changelog and git history: this plugin shipped both
> releases below without a changelog of its own. The entries describe what each version actually
> changed, but they were written after the fact, not at release time.

## [1.0.2] - 2026-09-18

### Fixed

- **The already-ran guard treated reading this plugin's own docs as having run the command.** The pattern matched the expanded command tag anywhere in the transcript, and that shape contains no quotes, so it is not escaped inside a JSONL string — any session whose transcript had seen the text (a `Read` of the file is enough) was judged "already saved" and got no reminder for the rest of its life. This is the same failure 1.0.1 fixed for the bare command name (62 matches, zero executions); writing the shapes verbatim into the new README below reopened it through a different door. The command branch is now anchored on the JSON quote that opens the field, which a real invocation has and prose does not. `tests/reminder.test.sh` gains a 12th assertion that feeds **the actual README file** to the hook, so a future doc edit that reintroduces a matching shape turns the suite red instead of silently disarming the reminder.

### Added

- `README.md` — this plugin shipped without one while the other eight had theirs. Written from the plugin's own manifest, `commands/save-session.md` and `hooks/save-session-reminder.sh`: the Stop-hook shape (once-per-session flag in `$TMPDIR`, a <10-line transcript floor, and already-ran detection that matches real invocation shapes only), the five phases, a table of where each kind of pattern lands, and why this plugin stays separate from `session-reflect`.

### Notes

- **Why a version bump for documentation.** The plugin cache is keyed by version (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`), so an unchanged version means an installed copy is never re-fetched and a new file never reaches it. Measured: `session-reflect`'s README was added in `c7c8169` without a bump, and the cached `1.0.0/` tree does not contain it — only `1.0.1/` does, where a later bump happened to carry it in. That makes the 1.0.1 changelog below, backfilled in marketplace 1.10.11 without a bump, undelivered too; this release carries both files.

## [1.0.1] - 2026-08-03

### Fixed

- **The "already ran /save-session" guard matched any *mention* of the string, not an execution.** The Stop hook grepped the transcript for the bare command name, so discussion of the command, a CLAUDE.md injection naming it, or a Read of this plugin's own files all counted as "already ran" — one real session showed 62 matches against zero executions, permanently suppressing the reminder. The pattern now matches only real execution shapes: `<command-name>/save-session</command-name>`, its namespaced variant, and the `"skill":"session-learning:save-session"` invocation form, all verified against real transcripts.
- Removed the no-op `matcher` field from the Stop hook entry.

### Added

- `tests/reminder.test.sh` — 11 fixture assertions covering the guard, wired into CI.

### Notes

- Ports the fixes `session-reflect` shipped with in marketplace 1.10.0; this release is marketplace 1.10.1. Surfaced by that plugin's own review flow on its first (manual) run.

## [1.0.0] - 2026-03-12

### Added

- Initial release — incremental capture of a session's valuable patterns as memory or skills via `/save-session`, plus a Stop hook that reminds when a session had substantive work.
