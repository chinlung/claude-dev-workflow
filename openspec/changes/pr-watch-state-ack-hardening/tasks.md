# pr-watch-state-ack-hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Each `### Task N` has one checkbox (the deliverable); its steps are a plain numbered list.

**Goal:** A state file `pr-closeout` cannot read is refused with a `foreign-state:` message, and `watch --stop --force` moves it aside so the guard hook stops blocking.

**Architecture:** `loadState` raises a `ForeignStateError` (a `QueryError`) for every unreadable state; `watchCli` catches it only on `--stop --force` and renames the file to `foreign-pr-watch.<pr>.<time>.local.json`, a name the guard's `pr-watch.*.local.json` glob misses and `*.local.json` ignore rules cover. The pr-watch SKILL never adds `--force` itself.

**Tech Stack:** Node ES module (`plugins/pr-closeout/scripts/pr-closeout.mjs`), bash test suites with a perl mutant runner, Markdown docs.

**Spec:** `openspec/changes/pr-watch-state-ack-hardening/design.md` (decisions D1–D6) and `specs/pr-watch/spec.md` (2 ADDED requirements); proposal in the same folder.

## Global Constraints

- Error prefix is exactly `foreign-state:`; the script exports it as `FOREIGN_STATE = 'foreign-state'`. Exit code for every refusal is 7.
- Moved-aside name is exactly `foreign-pr-watch.<pr>.<YYYYMMDDTHHMMSSZ>.local.json` in the same `.claude/` directory; time is `o.now ?? new Date()`, ISO with `-`, `:` and milliseconds removed. Bytes are never changed; an existing destination is refused, never overwritten.
- `--force` is accepted only with `watch --stop`; on a readable state it behaves like plain `--stop`.
- `STATE_VERSION` stays 1; `hooks/pr-watch-guard.sh`, `hooks.json`, `plugins/code-audit-rigor` are not touched.
- Versions: pr-closeout 1.3.0 → 1.4.0 (`plugin.json`), marketplace `.claude-plugin/marketplace.json` 1.24.0 → 1.25.0 (its `pr-closeout` entry 1.3.0 → 1.4.0).
- Public repo: commits use `git commit --no-gpg-sign`, no `Claude-Session` trailer, stage files by name (never `git add -A`), never modify `.gitignore`.
- The suite's mutants substitute on these exact source fragments; write them verbatim: `e instanceof ForeignStateError`, `if (fs.existsSync(dest)) throw new QueryError(`, a destination template beginning `foreign-pr-watch.${o.pr}.`, `if (o.force && !(o.cmd === 'watch' && o.stop)) throw new UsageError('--force is for watch --stop only');`, `throw foreign(file, 'not JSON')`.

## Review Focus

- The state path is a directory (or otherwise unreadable): `--stop` must give `foreign-state`, not a stack trace (Task 1).
- Empty file, whitespace-only file, JSON `null`, JSON array: all unreadable, all `foreign-state` (Task 1).
- `--force` on a readable state keeps the file in place and keeps `seen` (Task 2).
- A file already at the destination: refuse, original untouched (Task 2).
- The moved name is outside the guard's glob but inside `*.local.json`, proven by running the real guard (Task 2).

## 1. Script

### Task 1: Unreadable state files are refused as `foreign-state`
- [ ] 1.1 `loadState` raises `ForeignStateError` with a `foreign-state:` message for every unreadable state, and `watch`, `watch --start`, `watch --stop`, `watch-ack` refuse it with exit 7 and the file untouched.

**Files:**
- Modify: `plugins/pr-closeout/scripts/pr-closeout.mjs` (`loadState`, :539-555; add the class and helper next to `QueryError`, :36)
- Test: `plugins/pr-closeout/tests/pr-closeout.test.sh` (new section before `# ── summary and mutants`)

**Interfaces:**
- Produces: `export const FOREIGN_STATE = 'foreign-state'`; `export class ForeignStateError extends QueryError {}`; `const foreign = (file, why) => new ForeignStateError(\`${FOREIGN_STATE}: state ${file}: ${why}; upgrade the plugin, or run watch --stop --force to move it aside\`)`. Task 2 and Task 3 rely on the prefix.

1. Write the failing tests as a section headed `# ── pr-watch-state-ack-hardening: a state file this script cannot read`. Setup: `W7="$tmp/w7"; mkdir -p "$W7/.claude"; ST7="$W7/.claude/pr-watch.1.local.json"`; a helper `alien <json-text>` that writes the text to `$ST7` and copies it to `$tmp/st7`. For each variant — `version 2` (`{"version":2,"pr":1,"active":true,"seen":[]}`), `not JSON` (`{`), `empty file` (empty), `whitespace` (`  `), `null`, `array` (`[]`), `other PR` (a complete valid-shape state with `"pr":2`), `a directory` (`mkdir "$ST7"` instead of a file) — run `run_cli 7 "<name>: --stop" watch example/repo 1 --repo-dir "$W7" --stop`, then `has "<name>: says foreign-state" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "foreign-state:"` and `has "<name>: names --force" … "--stop --force"`, and `cmp -s "$ST7" "$tmp/st7"` (skipped for the directory, which is checked with `[ -d "$ST7" ]`).
2. For the `version 2` variant also run `watch --start`, a round `watch` (no `--start`) and `watch-ack … --comment "issues/comments:1:0123456789abcdef"` (each with `--repo-dir "$W7" --fixture "$FX5"`): each exit 7, detail starts `foreign-state`, bytes unchanged.
3. Run `bash plugins/pr-closeout/tests/pr-closeout.test.sh` with `NO_MUTANTS=1`. Expected: the new cases FAIL (detail lacks `foreign-state:`; the directory case crashes with a stack trace).
4. Implement in `pr-closeout.mjs`: the three exports above; rewrite `loadState` so reading the file (`fs.readFileSync` failure → `foreign(file, \`unreadable: ${e.code}\`)`), `JSON.parse` failure (`throw foreign(file, 'not JSON')`) and every existing `bad(...)` check throw `foreign(file, why)` instead of `QueryError`. Update the comment above `loadState` to say an unreadable state is refused and only `watch --stop --force` may move it, never rewrite it.
5. Run the suite again with `NO_MUTANTS=1`. Expected: `pr-closeout: <n> passed, 0 failed` (the existing `state $bad refused` cases still exit 7).
6. Commit: `git add plugins/pr-closeout/scripts/pr-closeout.mjs plugins/pr-closeout/tests/pr-closeout.test.sh && git commit --no-gpg-sign -m "pr-closeout: an unreadable watch state is refused as foreign-state"`.

### Task 2: `watch --stop --force` moves the state aside
- [ ] 1.2 `watch --stop --force` renames an unreadable state to `foreign-pr-watch.<pr>.<time>.local.json`, exits 0 and reports `watch.movedAside`; the real guard blocks before and allows after; five mutants die.

**Files:**
- Modify: `plugins/pr-closeout/scripts/pr-closeout.mjs` (`parseArgs` :493-532, `watchCli` :678-720, header comment :8-9 and `USAGE` :33)
- Test: `plugins/pr-closeout/tests/pr-closeout.test.sh` (cases after Task 1's; mutant list; `MUT_WANT_N`)

**Interfaces:**
- Consumes: `ForeignStateError`, `foreign`, `FOREIGN_STATE` from Task 1.
- Produces: `o.force` (boolean) from `parseArgs`; `moveAside(file, o): { exit: 0, gate: null, hits: [], watch: { active: false, movedAside: string } }`, where `movedAside` is the new path built with `path.join(path.dirname(file), …)`.

1. Write the failing tests after Task 1's, all with `--now 2026-11-25T00:40:00Z`, expected name `foreign-pr-watch.1.20261125T004000Z.local.json`: (a) `version 2` + `--stop --force` → `run_cli 0 "--force moves a version 2 state aside"`; the original path is gone, the new file exists and is `cmp`-equal to the original, `jq -r .watch.movedAside` is that path, `jqeq … '.watch.active' 'false'`; (b) repeat for `{`, empty file, `other PR`, and the directory (`[ -d ]` at the new path) — label `"<name>: moved aside"`; (c) readable state (written by `startState`-shaped JSON with `"seen":["issues/comments:1:0123456789abcdef"]`) + `--stop --force` → exit 0, file still at `$ST7`, `.active == false`, `.seen` unchanged, no `.watch.movedAside` (`jqeq … '.watch.movedAside // "none"' '"none"'`); (d) `[moved name]`: the basename equals the expected name exactly, and does not match the glob `pr-watch.*.local.json` (`[[ $name == pr-watch.*.local.json ]]` false) but does match `*.local.json`; (e) `[dest exists: refused]`: pre-create the expected name, `--stop --force` → exit 7, original bytes unchanged; (f) `--force` with `--start`, `watch-ack`, `ready`, and with plain `watch` (no `--stop`) → exit 7 each, labels starting `[--force with `; (g) no state file → `--stop --force` exit 7 with detail containing `not-started`.
2. Add the wiring case: build a project dir with `.claude/pr-watch.1.local.json` containing the `version 2` text with `"active":true`; feed `gh pr comment 1 -b x` (JSON built with `jq -cn --arg c … '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'`) to `CLAUDE_PROJECT_DIR=<dir> bash "$here/../hooks/pr-watch-guard.sh"` and assert `.hookSpecificOutput.permissionDecision == "deny"`; run `watch --stop --force` on that dir; feed the same input again and assert it is no longer `deny`. Label `[guard: blocks before, allows after --force]`.
3. Run the suite with `NO_MUTANTS=1`. Expected: the new cases FAIL (`--force` is an unknown option).
4. Implement: in `parseArgs` add `--force` to the boolean flags beside `--start`/`--stop` (`o.force = true; continue;`, initial `force: false`), and after the loop the verbatim usage line from Global Constraints (so it also covers `ready`/`landed`/`watch-ack`/`--start`). In `watchCli` replace `let s = loadState(file, o.pr);` with a `try`/`catch` that, on `o.stop && o.force && e instanceof ForeignStateError`, returns `moveAside(file, o)` and otherwise rethrows. Write `moveAside(file, o)`: destination from the Global Constraints template; `if (fs.existsSync(dest)) throw new QueryError(\`${dest} already exists\`)`; `fs.renameSync` failures re-thrown as `QueryError(\`could not move ${file} aside: ${e.message}\`)`. Update the header comment (:8) and `USAGE` (:33) to `[--start | --stop [--force]]`.
5. Add five mutants before `mutants_judged` and set `MUT_WANT_N=60`: `f-class` (want `[--force moves a version 2 state aside]`, `s/e instanceof ForeignStateError/false/`), `f-overwrite` (want `[dest exists: refused]`, `s/if \(fs\.existsSync\(dest\)\) throw/if (false) throw/`), `f-prefix` (want `[moved name]`, `s/foreign-pr-watch\./pr-watch.foreign./`), `f-usage` (want `[--force with `, `s/if \(o\.force && !\(o\.cmd === 'watch' && o\.stop\)\) throw/if (false) throw/`), `f-json` (want `not JSON: says foreign-state`, `s/throw foreign\(file, 'not JSON'\)/throw new QueryError('x')/`).
6. Run the full suite (mutants included). Expected: `pr-closeout: <n> passed, 0 failed` and 60 lines `mutant [...]: suite red as required`; no `MUTANT [...]` failure line.
7. Commit: `git add plugins/pr-closeout/scripts/pr-closeout.mjs plugins/pr-closeout/tests/pr-closeout.test.sh && git commit --no-gpg-sign -m "pr-closeout: watch --stop --force moves an unreadable state file aside"`.

## 2. pr-watch skill and docs

### Task 3: The SKILL reports `foreign-state` and never forces
- [ ] 2.1 `SKILL.md` stops and reports on `foreign-state`, adds `--force` only after the user asks, and the docs test pins both.

**Files:**
- Modify: `plugins/pr-closeout/skills/pr-watch/SKILL.md` (exit 7 step :38; the stop paragraph :105-107; the `## 不做` list)
- Test: `plugins/pr-closeout/tests/pr-watch-docs.test.sh`

**Interfaces:**
- Consumes: `FOREIGN_STATE` exported by the script (Task 1).

1. Write failing checks in `pr-watch-docs.test.sh`: read `FOREIGN_STATE` the way `STOP_REASONS` is read (`node --input-type=module -e "import { FOREIGN_STATE } from '$SCRIPT'; console.log(FOREIGN_STATE)"`) and assert the SKILL contains it; assert the SKILL contains `--stop --force`; assert the text before `## 不做` has no step that runs `--force` on its own by requiring the phrase `不自行加 --force` somewhere in the SKILL; raise the pass floor `-ge 28` to `-ge 31`.
2. Run `bash plugins/pr-closeout/tests/pr-watch-docs.test.sh`. Expected: the new checks FAIL.
3. Edit `SKILL.md`: in the exit 7 step add, before 「其他情況」, a clause: when `detail` starts with `foreign-state`, run no stop command, tell the user the state file was written by another version (possibly another session watching with a newer plugin), offer to upgrade the plugin or to run `--stop --force` only if they say so, end the loop with ScheduleWakeup `stop: true`; the same applies when `watch-ack` returns `foreign-state`. In the stop paragraph add: if the user's 「停止監看」 returns `foreign-state`, show the message and run `… --stop --force` only after the user confirms. In `## 不做` add 「不自行加 `--force`」.
4. Run the docs test. Expected: `pr-watch-docs: <n> passed, 0 failed`.
5. Commit: `git add plugins/pr-closeout/skills/pr-watch/SKILL.md plugins/pr-closeout/tests/pr-watch-docs.test.sh && git commit --no-gpg-sign -m "pr-watch skill: foreign-state is reported to the user, --force is never added by the skill"`.

### Task 4: READMEs, changelogs, versions, full verification
- [ ] 2.2 Docs and versions say 1.4.0 / 1.25.0 and every suite plus `openspec validate` is green.

**Files:**
- Modify: `plugins/pr-closeout/README.md` and `README.zh-TW.md` (the `watch` bullet, :108), `plugins/pr-closeout/CHANGELOG.md`, `plugins/pr-closeout/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `CHANGELOG.zh-TW.md`
- Test: `plugins/pr-closeout/tests/pr-watch-docs.test.sh`

1. Add a docs check that both READMEs contain `--stop --force` and `foreign-state` (four checks) and raise the pass floor to `-ge 35`; run the docs test and watch it FAIL.
2. In both READMEs extend the `watch` bullet: `[--start | --stop [--force]]` in the synopsis; refusals list a state file the script cannot read (`foreign-state`); `--stop --force` moves such a file to `foreign-pr-watch.<pr>.<time>.local.json`, which the guard no longer reads; a readable state is stopped as usual.
3. `plugins/pr-closeout/CHANGELOG.md`: a `## [1.4.0] - 2026-11-27` entry above 1.3.0 with `### Added` (`watch --stop --force`) and `### Changed` (a state the script cannot read is refused with `foreign-state:`; the pr-watch skill reports it instead of stopping). Same release as one bullet `**pr-closeout 1.3.0 → 1.4.0**` under a new `## [1.25.0] - 2026-11-27` in `CHANGELOG.md`, and the Traditional Chinese equivalent in `CHANGELOG.zh-TW.md`, each following its file's existing format.
4. Set `"version": "1.4.0"` in `plugin.json`; in `marketplace.json` set `metadata.version` to `1.25.0` and the `pr-closeout` entry's `version` to `1.4.0`.
5. Verify, each redirected to a file and judged by its own exit code: `bash plugins/pr-closeout/tests/pr-closeout.test.sh` (expect 60 mutants red as required), `pr-watch-docs.test.sh`, `pr-watch-guard.test.sh` (unchanged, expect `0 failed`), `node scripts/validate-fixtures.cjs` (expect `All fixture checks passed.`), `openspec validate pr-watch-state-ack-hardening --strict`.
6. Commit: `git add` the six edited files and the docs test by name, `git commit --no-gpg-sign -m "pr-closeout 1.4.0 (marketplace 1.25.0): watch --stop --force — versions, changelogs, README"`.
