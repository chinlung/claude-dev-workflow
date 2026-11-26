# pr-closeout-hooks-fail-closed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (the tasks share the two hook files and their suites). One checkbox per Task; steps are a plain list.

**Goal:** pr-merge-gate and pr-watch-guard give the same decisions under bash 3.2 (UTF-8 locale) as under bash 5, and block the action whenever they fail.

**Architecture:** Fix the four bash 3.2 failure shapes in place (design D1); add `"onFailure": "block"` to every handler of the two hooks in hooks.json (D2); a static lint in both suites (D3); a CI job that builds GNU bash 3.2.57 and runs both suites with it behind a canary (D4).

**Tech Stack:** bash (3.2 and 5), perl, jq, node, GitHub Actions.

**Spec:** `openspec/changes/pr-closeout-hooks-fail-closed/design.md`, `specs/pr-watch/spec.md`, `specs/pr-merge-gate/spec.md`

## Global Constraints

- Hooks keep `set -u` (and the merge gate `set -uo pipefail`); fixes change expansions, not shell options.
- `onFailure` is a field of each hook handler (sibling of `type`/`command`/`timeout`), value `"block"`; the 4 handlers whose `command` runs `pr-merge-gate.sh` or `pr-watch-guard.sh` all carry it.
- bash 3.2.57 source: `https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz`, sha256 `3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4`; serial `make`; `CFLAGS` and `CFLAGS_FOR_BUILD` = `-O2 -std=gnu89 -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -Wno-incompatible-function-pointer-types`.
- Versions: pr-closeout 1.2.1 → 1.3.0, marketplace 1.23.1 → 1.24.0.
- Each suite is judged by its own exit code (`cmd > log; RC=$?`), never through a pipe.
- Local 3.2 runs: a directory holding a `bash` symlink to `/bin/bash` (or the GNU build) first on PATH, `LANG=LC_ALL=en_US.UTF-8`.

## Review Focus

- A hook run with no `CLAUDE_PROJECT_DIR` and no usable `cwd` under 3.2 must exit 0 with no output — with `onFailure: "block"`, a crash there blocks every Bash call (Task 3 test: existing `[no CLAUDE_PROJECT_DIR]` case, run under 3.2).
- The CI 3.2 job going green without testing anything (wrong locale, wrong `bash` on PATH) — the canary must fail the job (Task 5).
- hooks.json gaining a handler for either hook without `onFailure` — the derived check with a floor of 4 (Task 4).
- A deny reason that lost its file path or exit code after the `${var}` rewrite — existing `reason_has` / `deny reason names …` cases, run under 3.2 (Task 2).
- Backslash-newline commands under 3.2 deciding differently from bash 5 — existing continuation cases, run under 3.2 (Task 3).

---

## 1. Tests that run under bash 3.2

### Task 1: Suites run under bash 3.2; lint for `$name` followed by non-ASCII
- [x] 1.1 Both suites build their inputs in a 3.2-safe way and carry the D3 lint; the lint is red on today's hooks
1. Files: `plugins/pr-closeout/tests/pr-merge-gate.test.sh`, `plugins/pr-closeout/tests/pr-watch-guard.test.sh`.
2. In the merge-gate suite, replace every MCP input written as an escaped JSON string inside `"$(mcp_in "…")"` with one built by `jq -n --arg`/`--argjson` (design D1d); keep labels and expectations.
3. Add to each suite one check `[no $name glued to a non-ASCII byte in <hook>]`: `LC_ALL=C perl -ne 'print "$.\n" if /\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]/' "$HOOK"` prints nothing; raise `MIN_PASS` by one in each.
4. Run both suites under bash 5: expected FAIL only on the new lint (guard: line 42; merge gate: 494, 501).
5. Run the merge-gate suite under local bash 3.2 against `HOOK=` a copy with D1a applied: the `[MCP sha: args]` failure is gone.
6. Commit the two test files.

## 2. Hook fixes

### Task 2: `${name}` before full-width characters (D1a)
- [x] 2.1 guard line 42 `${active}`, merge gate 494 `${sha}` and 501 `${rc}`; lint green; deny reasons intact under 3.2
1. Files: `plugins/pr-closeout/hooks/pr-watch-guard.sh`, `plugins/pr-closeout/hooks/pr-merge-gate.sh`.
2. Apply the three rewrites.
3. Run both suites under bash 5 (rc 0) and under local 3.2 (merge gate rc 0; guard leaves only the two Task 3 failures).
4. Commit.

### Task 3: guard under 3.2 — continuation and no directories (D1b, D1c)
- [x] 3.1 guard suite rc 0 under local bash 3.2 and bash 5
1. File: `plugins/pr-closeout/hooks/pr-watch-guard.sh`.
2. RED: run the guard suite under 3.2; expected FAIL `[active: allow gh api repos/o/r/pulls/7/comments \ …]` and `[no CLAUDE_PROJECT_DIR] rc 1`.
3. Store `$'\\\n'` in a variable and use `"${cmd//"$nl"/}"` at line 110 (D1b).
4. After the `dirs` array is built, `[ ${#dirs[@]} -gt 0 ] || exit 0` before the loop (D1c).
5. GREEN: guard suite rc 0 under 3.2 and under bash 5 with mutants (24 red).
6. Commit.

## 3. Fail closed and CI

### Task 4: `onFailure: "block"` on every handler of both hooks (D2)
- [x] 4.1 hooks.json carries it on all 4 handlers; a derived check with a floor of 4 guards it
1. Files: `plugins/pr-closeout/hooks/hooks.json`, `plugins/pr-closeout/tests/pr-merge-gate.test.sh`.
2. RED: add check `[every pr-merge-gate / pr-watch-guard handler has onFailure block]`: jq over `.hooks.PreToolUse[].hooks[]` selecting `command` matching `pr-(merge-gate|watch-guard)\.sh`; count ≥ 4 and every `.onFailure == "block"`; raise `MIN_PASS`. Run: FAIL.
3. Add `"onFailure": "block"` to the 4 handlers.
4. GREEN: suite rc 0 under bash 5; `jq . hooks.json` parses.
5. Commit.

### Task 5: CI job running both suites under GNU bash 3.2.57 (D4)
- [ ] 5.1 `validate.yml` job builds bash 3.2.57 (cached), passes the canary, runs both suites with `NO_MUTANTS=1`
1. File: `.github/workflows/validate.yml`.
2. New job on `ubuntu-latest`: cache the built binary keyed by the tarball sha256; on miss, download, verify sha256, configure `--without-bash-malloc`, serial `make` with the Global Constraints flags.
3. Put a directory with `bash` → the build first on PATH; set `LANG`/`LC_ALL` to `C.UTF-8`.
4. Canary step: `bash -c 'set -u; a=1; echo "$a）"'` must exit non-zero; if it exits 0, the step fails with a message naming the locale.
5. Run `bash plugins/pr-closeout/tests/pr-watch-guard.test.sh` and the merge-gate suite with `NO_MUTANTS=1`, each its own step.
6. Local check: `actionlint` if available, else `ruby -ryaml -e 'YAML.load_file(ARGV[0])'` / `node` YAML parse; then the same steps by hand with the local GNU build under `C.UTF-8` if the locale exists on macOS, else `en_US.UTF-8`.
7. Commit; CI result is read after push.

## 4. Release

### Task 6: Versions, CHANGELOGs, README
- [ ] 6.1 pr-closeout 1.3.0 / marketplace 1.24.0 everywhere; README states the failure behavior, the CLI floor and the way out
1. Files: `plugins/pr-closeout/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (metadata and the pr-closeout entry), `plugins/pr-closeout/CHANGELOG.md` [1.3.0], `CHANGELOG.md` and `CHANGELOG.zh-TW.md` [1.24.0], `plugins/pr-closeout/README.md`, `plugins/pr-closeout/README.zh-TW.md`.
2. README: both hooks block when they time out, crash or print unreadable output (Claude Code v2.1.295 or later; older versions let the action through); a broken hook that blocks every Bash call → `/plugin disable pr-closeout`.
3. `grep -rn '1\.2\.1\|1\.23\.1'` over those files shows only CHANGELOG history lines.
4. Run the four pr-closeout suites (pr-closeout, pr-watch-guard, pr-watch-docs, pr-merge-gate) and review-pr-triage if present; each rc 0.
5. Commit.
