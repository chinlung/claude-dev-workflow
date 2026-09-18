# Changelog

All notable changes to the `session-learning` plugin will be documented in this file.

> Backfilled on 2026-09-18 from the root changelog and git history: this plugin shipped both
> releases below without a changelog of its own. The entries describe what each version actually
> changed, but they were written after the fact, not at release time.

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
