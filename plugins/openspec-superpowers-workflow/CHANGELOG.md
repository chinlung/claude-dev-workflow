# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2026-11-14

### Changed (BREAKING)

- **Follows OpenSpec 2.0.** OpenSpec 2.0 removed the `/opsx:*` slash commands; each became the skill of the same workflow, installed in `.agents/skills/` and read by Claude Code through links in `.claude/skills/`. The skill, `phases.md`, `PHASE-IDENTIFICATION.md`, `RECONCILIATION-CRITERIA.md`, `SUPERPOWERS-HANDOFF.md` and the README now name the skills: `/openspec-propose`, `/openspec-explore`, `/openspec-new-change`, `/openspec-continue-change`, `/openspec-ff-change`, `/openspec-apply-change`, `/openspec-update-change`, `/openspec-verify-change`, `/openspec-sync-specs`, `/openspec-archive-change`, `/openspec-bulk-archive-change`, `/openspec-onboard`. The skill's trigger names them too. The phase each one belongs to is unchanged.
- **What was checked before the rename.** Both versions were initialised with the same twelve workflows, and each 1.16.1 skill was compared with its 2.0.0 counterpart. Once the new names and "command" → "skill" are applied, nothing else differs: the steps are the same, so every sentence about what a command does still holds. `TASK_LINE_PATTERN` is identical in both versions; 2.0 only joins a wrapped task's lines into its text, so `task-line.cjs` still counts tasks as OpenSpec does.
- **A project made with OpenSpec 1.x** may still have `.claude/commands/opsx/`. The prerequisites check now spots it and says to run `openspec update` first: it installs the skills and removes the old command files it generated (edited ones are kept and listed). A project that stays on OpenSpec 1.x stays on this plugin's 3.x.
- **archive-gate** is unchanged in what it does: `openspec archive` is still there, and the archive skills still run `mkdir -p` and `mv "<change>" "<changes>/archive/<date-name>"`. Its comments and the hooks.json description now name the skills.

### Tests

- `cli-claims.test.sh` (16 checks) checks the docs against OpenSpec 2.0.0 (`tests/openspec-version`; CI installs the same string).
  - The skill names come from a full-profile `init` through `.claude/skills/`, and a link must resolve.
  - A `/openspec-*` name in the docs must be one of them. This plugin's own name and paths are not names.
  - No `/opsx:*` command may be left.
  - A full-profile `init` must make no `/opsx:*` command files. That check is what fails under 1.16.1, locally as well as in CI.
  - Mutants on a copy of the docs (a made-up name, a leftover `/opsx:`, a skill dropped from `phases.md`) each turn it red.
- `archive-gate.test.sh`: one case with the exact `mv` the 2.0 archive skill runs (both paths quoted and absolute, no trailing slash).

## [3.2.1] - 2026-11-14

### Fixed

- **The lexer reads on where it finds no closer** (archive-gate; the same bytes as pr-closeout 1.1.1's merge gate). A heredoc whose delimiter never comes, an arithmetic that never closes and an unclosed quote in a heredoc delimiter each ran to the end of the text, as they do in bash — unless bash drops that line as a syntax error, when the lines after it run. The lexer cannot tell which, so it reads the text after them as commands too (it already did after an unclosed quote), the later heredocs of the same line first.
- A substitution leaves a mark in its word: `\x01` inside quotes and for arithmetic (exactly one word), `\x02` when unquoted (any number of words, none included). archive-gate reads names with the substitution taken as empty, as before, so nothing changes for it; the merge gate reads a marked value as unknown (see pr-closeout 1.1.1). `subs_of` moved into the lexer region, the lexer's `${…}` reading being one of its callers.

### Not done: retiring the two older readings

Tried on this branch and measured; see pr-closeout 1.1.1 and `docs/gate-lexer-design-2026-11-13.md` §11. They stay, and the suite now checks what they are for.

### Tests

- `tokenizer-differential.test.sh` (59 checks). **New invariant:** on generated commands, both gates report at least what they did at `b16fb23` (3.2.0) — every line it printed, or for the merge gate a line that denies the command outright — over the default grammar and a random-punctuation seed, 1500 cases each; two canaries show the lexer alone fails it. The harness: the `gh` stub records the repo and a merge counts as caught only with the repo and number bash used, a `-`, or a repo GitHub cannot have; one merge in four carries a substitution in its number or repo or a word that expands to nothing; three random-punctuation seeds instead of one; an empty line in the call log (a name with a newline in it) is not a call; `--superset-of … --judge` lists the cases where an earlier parser printed a line today's does not while bash ran nothing today's misses. Three lexer mutants left: with the fix above a mistake in those rules only makes the lexer read more, which bash cannot catch. Not compared: the head sha (the merge gate's suite has cases for it).
- `archive-gate.test.sh` (138 checks): the 11 mutants break the lexer and run on a copy with the lexer alone, each pinned to the case that exists for its path; the suite checks that this copy fails only the one case the older readings exist for.
- `shared-tokenizer.test.sh` (9 checks): two regions, the lexer (with `subs_of`) and the older readings.

## [3.2.0] - 2026-11-13

### Added

- **archive-gate reads each command a third time, with a lexer that reads it the way bash does** (W5-8, `docs/gate-lexer-design-2026-11-13.md`). One pass over the characters with a context for each quote and substitution: `$( … )`, backticks and `${…}` are read by the same lexer, recursively, instead of being cut out and scanned again; a heredoc body is read at the end of its line. What any of the three readings finds counts, so the lexer can add to what the gate checks but not take away; the two older readings stay until a later release shows, by the same machine check, that the lexer alone loses nothing. The lexer is a new shared region (`# >>> shared-tokenizer: lexer`), byte for byte the same in pr-closeout's merge gate (pr-closeout 1.1.0).

### Fixed

Archives bash runs and the gate did not see, all older than this release:

- The three gaps recorded with 3.1.2: a heredoc closed by `EOF)` inside `$( … )` (the commands up to a later `EOF` line were swallowed); a delimiter written in mixed quotes (`<<'E'"F"` closes on `EF`); a double-quoted string inside a substitution that is itself inside double quotes (`echo "x $(echo "a"; openspec archive foo) y"`).
- Found by the new random-punctuation grammar: an archive after a `\` line continuation (`true && \⏎openspec archive foo`); after a backtick that holds a lone quote (`` echo `'-#`⏎openspec archive foo ``); a redirection glued to the name (`openspec archive foo>/dev/null` was read as the change `foo>/dev/null`, which does not exist, so the archive was let through); a heredoc inside backticks inside double quotes.
- Found while writing the lexer, each checked in bash 3.2 and 5.3: a `$( … )` or a backtick inside `$(( … ))` runs, a backtick inside its `'…'` too; `$[ … ]` is arithmetic; `<<\⏎EOF` is `<<EOF` (the `\⏎` joins lines, so the body is expanded); a `${…}` or a backtick in a delimiter is part of the word, and a quote inside one does not make the body literal.

Bash facts the lexer follows where they differ from what the older readings assumed: a heredoc whose delimiter never comes takes the rest of the text and no line of it runs; `$((` is arithmetic only when the `)` that closes its first `(` is followed at once by another (otherwise it is `$( ( … ) … )`), and since an unclosed quote also changes where bash ends it, the text of a `$(( … ))` is read as `( … )` too; `${ cmd; }` runs in bash 5.3 (3.2 rejects it), and the lexer reads it as commands. The text after a quote that never closes is read as commands too: bash drops a line it rejects as a syntax error and runs the lines after it, and a quote on such a line was never one. Those second readings nest, so each text is read only once (reading it again could only find the same commands); without that, 40 nested `$((` would take hours. The lexer stops after 3,000,000 steps for the whole command, its `bash -c` and `eval` strings included (the review before merging found the limit reset for each of them: 50 took the lexer 18 s), a step being a character any of its loops looks at — a scan for a `}` that never comes and a text copied for a reading of its own count each time — and `$((` nests no deeper than 50, as `$(` does: while only the main loop counted, the pre-commit review found 12,000 nested `$((` taking 20 s (0.07 s before the lexer), past archive-gate's 10 s hook timeout, and 4,000 unclosed `${a:-` doubling the parse from 3.8 s to 7.9 s. The lexer now stops on either in half a second at most.

### Known gap

- **A line bash drops as a syntax error.** When bash rejects a line (`a=(-( <<EOF`), a heredoc opened on it was never one and the lines after it run; all three readings take them for its body. Knowing which lines bash rejects takes bash's grammar. Pinned as `--gap 0` in `tokenizer-differential.test.sh` and recorded in follow-ups.

### Tests

- `tokenizer-differential.test.sh` (57 checks; 20 `bash -c` strings that together take 9 s with a limit each must share one, and a canary that resets it per string must run out of time): 40 nested unclosed `"$(` and 40 nested `$((` must finish in under 5 s in both gates, and so must 15,000 nested `$((` (both gates) and 8,000 unclosed `${a:-` (each gate's lexer alone: the two older readings are themselves quadratic on them); 60 nested `$((` are past the lexer's depth; three canaries each remove one guard and must fail (without reading each text once the 40 nested `$((` spend the step limit and the merge after them goes unread; without the counting in `param_end` the `${a:-` run out of time; without the depth check and the counting in `lex_arith` and `lex_text` the 15,000 `$((` do); a copy with a lowered step limit must make the merge gate report an unreadable merge; the three gaps and the shapes above are in the default grammar; both gates are also run with only the lexer (a copy whose reading loop runs the third pass alone), over the default grammar and the random-punctuation grammar (`--chars`, one fixed seed each); 18 lexer mutants, each breaking one path of the lexer in that copy, must each give bash a command the copy misses; today's gates must print every line the gates at `b81dcdc` and at `01457c3` print, and the harness must tell `01457c3` from today's gate. The harness now waits for the process group of each bash run before reading what it ran: a process bash left running could write into the next case's record and fake a counterexample. It reads the merge gate's output lines the way the hook does (`read -r`, a number that is not all digits counts as unreadable).
- `archive-gate.test.sh` (139 checks): nine end-to-end cases for the lexer, kept last; the 15 mutants run on a copy with only the two older readings, which the lexer would otherwise cover for.
- `shared-tokenizer.test.sh` compares three regions (the lexer added, with a line floor and a canary).

## [3.1.2] - 2026-11-12

### Fixed

- **archive-gate sees the archive on the line after a comment.** The heredoc pass skipped a `#` comment, the tokenizer did not: an apostrophe in `# don't archive yet` opened a single-quoted string that swallowed everything up to the next apostrophe, so `openspec archive foo` on the next line (or a `bash -c` / `eval` string, or anything inside a `( … )`) was never seen. Bash runs it. A `#` that starts a word now comments out the rest of its line in the tokenizer too; a `#` inside a word (`echo x#y`) is not a comment. Two things bash knows went into the tokenizer with it, because the comment rule is only right where the tokenizer's words are bash's words: inside `` `…` `` a comment ends at the closing backtick (`` echo `# don't`; openspec archive foo `` still archives), and `${…}` is the inside of one word, where a `#`, a quote or a blank starts nothing (`echo ${x:- #}; openspec archive foo` still archives) and a `}` inside quotes does not close it; the `$( … )` and backticks a `${…}` holds are still scanned as commands, except inside its own single quotes. A `#` counts as a comment only at a real word start (not glued to the `)` or backtick that closes a substitution, as in `echo v$(echo 1)#L10 && openspec archive foo`).
- **Each command is read twice, and what either reading finds counts.** One reading has the rules above; the other is the reading from before them. A mistake in the new rules can therefore add to what the gate catches but not take away: reviews of this release found six command shapes the new rules alone lost, and this is what closes that class instead of the seventh shape. `tokenizer-differential.test.sh` checks it directly: on every generated command, today's parser prints every line the parser before this release prints. Found by the differential test below; the same region lives in pr-closeout's merge gate (pr-closeout 1.0.5).

### Tests

- **New `tokenizer-differential.test.sh` (with `tokenizer-differential.pl`).** Bash is the oracle: generated commands run in an empty directory whose PATH holds only stubs of `openspec` and `gh`, and the gate's parser (the text the hook hands to perl, run the way the hook runs it) must report every `openspec archive` and `gh pr merge` bash ran (the grammar generates only those two: an archive by `mv`, a merge by `gh api` and the MCP merge tool are not covered). A fixed seed keeps it repeatable. The suite also proves the harness can fail: for each past tokenizer fix (#48, #51 in both gates, #55 in both gates) it finds a command the version before the fix misses and the fixed one catches. Those versions are read from git history, so CI checks out with `fetch-depth: 0` and a missing commit fails the suite. Three gaps both gates still have, all older than this release (a heredoc closed by `EOF)` inside `$( … )`; a delimiter written with mixed quotes; a double-quoted string inside a substitution that is itself inside double quotes, as in `echo "x $(echo "a"; openspec archive foo) y"`) are left out of the default grammar and pinned one by one (`--gap 0`, `--gap 1`, `--gap 2`): fixing any one turns its own check red, as the reminder to move it into the default grammar. A parser that runs past 10 s ends the run as "cannot judge" (exit 2), never as a counterexample.
- `archive-gate.test.sh`: 115 checks and 15 mutants.

## [3.1.1] - 2026-11-11

### Fixed

- **archive-gate sees the archive that bash runs from inside a string.** `$( … )` and backticks inside double quotes or inside an unquoted heredoc body still run, so `echo "$(openspec archive foo)"` and `cat <<EOF` followed by a `$(openspec archive foo)` line archived a change without a reconcile-check pass. The gate dropped heredoc bodies whole and never looked inside double quotes. It now scans those substitutions as commands, the way pr-closeout's merge gate has since 1.0.0; a body behind a quoted (`<<'EOF'`) or backslashed (`<<\EOF`) delimiter, single quotes and an escaped `\$` still do not count, because bash does not run them. A heredoc body is scanned as one text, so a `$( … )` that runs across its lines is read whole (pr-closeout 1.0.4 fixes the same line-by-line scan in its copy).

### Tests

- `archive-gate.test.sh`: 95 checks and 7 mutants. Each mutant breaks one path of the substitution scan and must be caught first by the case written for it; the mutant copy sits in a plugin-shaped tree, so it cannot pass by failing to find `reconcile-check.cjs`.
- **New `shared-tokenizer.test.sh`.** The tokenizer lives in both gates because the two plugins install apart and cannot source each other. The suite compares the regions between `# >>> shared-tokenizer:` and `# <<< shared-tokenizer:` markers in `archive-gate.sh` and pr-closeout's `pr-merge-gate.sh`, indentation aside, with a line floor per region and canaries for an edit inside a region, a missing or repeated marker and empty regions. Before this release the two copies had drifted (the fix above was in one of them only), and nothing said so.

## [3.1.0] - 2026-11-11

### Changed

- **P2 stops on a structural fact P1 did not see.** Every `gate-check p1` run records the change's structural facts (a `BREAKING` marker, delta kinds, `high_risk_paths` hits) in `.claude/openspec-gate.<change>.local.json`; `p2` stops with `structure-changed-since-p1` when one is new since P1 (the proposal, the specs or the `high_risk_paths` settings changed), and with `no-p1-record` when there is no readable record; if the user already approved P1 (an earlier session, a change from before 3.1) the agent runs `p1` once to create it and stops for any reason it cannot confirm the user approved, and a session without a shell compares by hand against what the user was shown at P1. On a P1 stop the agent runs `p1` again after folding in the review, so the record matches what the user was shown and an approved trigger does not stop P2 a second time.
- **P1 stops on missing or unreadable specs:** `no-specs` when there is no `specs/**/spec.md` (unless `.openspec.yaml` sets `skip_specs: true`), `spec-unreadable` when a spec file cannot be read. Both used to read as "no delta".
- **A personal `high_risk_paths` adds to the project's list** instead of replacing it, so `.claude/openspec-workflow.local.md` can no longer switch off the committed high-risk paths with an empty list. `gates` still lets the local file win.

### Fixed

- **Comment and fence stripping no longer swallows real content.** One pass over the lines tracks fences and comments together, so neither pairs across the other (a ``` line inside a comment or a `~~~` fence); a backtick fence's opening line cannot contain another backtick (CommonMark), so ```` ```x``` ```` is a code span; a `<!--` inside inline code opens nothing. Each used to hide a later `BREAKING` marker or delta heading.
- **State files are never written through a symlink.** gate-check's P1 record and reconcile-check's verdict state go to a temp file in the same directory and are renamed over the target (a new shared `validators/safe-write.cjs`), so a symlink a checkout ships at the state path is replaced, not followed; a `.claude` that is itself a symlink is refused. reconcile-check wrote through such a symlink before this release too.
- **A P1 run that cannot write its record exits 1** instead of warning and proceeding: a stale record that stays readable would let P2 wave through a fact this run no longer saw.

### Docs

- phases.md "Gates" and the plugin README say where the settings files live (the project root's `.claude/`, beside `openspec/`).

### Tests

- `gate-check.test.sh`: 190 checks; `reconcile-check.test.sh`: 86 (state symlink). Seventeen mutations of the new paths against copies, each red.

## [3.0.0] - 2026-11-10

Analysis behind this release: `docs/openspec-hitl-gate-analysis-2026-11-10.md` (of 87 gate events at P1–P3, 1 was a reversal; the problems caught at gates surfaced only after the user asked for an extra review). Design: `docs/openspec-workflow-3-gates-design-2026-11-10.md`.

### Changed (breaking default)

- **Gates stop on facts, not on every phase.** At the end of Phase 1 the agent runs `gate-check.cjs p1`: a `BREAKING` marker, a spec delta with `MODIFIED`, `REMOVED` or `RENAMED Requirements`, a `[needs user]` item under the new `## Decisions` section, an `## Impact` path matching `high_risk_paths`, a missing `## Decisions` section or unreadable settings mean a stop; otherwise it lists its defaults and carries on in the same turn. Phase 2 stops the same way on a `[needs user]` item under `## Open Questions`.
- **A stop starts with an independent review.** Before waiting, an opus subagent reads the proposal and specs (or the design) for decisions made without saying so, options common practice offers that the change does not list, and contradictions with existing specs.
- **Phase 3 and Step 6b no longer wait.** tasks.md goes on to Phase 4 once the bundled validator passes; the Phase 6 rewrite is summarized in the reply and in the archive PR, and reconcile-check stays the gate.
- **Phase 5 suggests convergence** when the last round of every layer found no new `Y`, no `[CODE]` finding is open and every layer ran since the last fix. Declaring `final` stays the user's.
- **`gates: supervised`** in `.claude/openspec-workflow.local.md` restores a stop at every gate.

### Added

- `validators/gate-check.cjs <p1|p2|p3|p6b>` (exit 0 proceed, 10 stop, 1 error: fix the call, or at p3 a tasks.md that breaks the one-checkbox-per-Task rule, and re-run; a second failure is a stop). P2 also stops when design.md cannot be read. Settings: `.claude/openspec-workflow.md` (committed, `high_risk_paths`) and `.claude/openspec-workflow.local.md` (personal, `gates`). Unreadable settings or an unknown `gates` value count as a stop; `p3` and `p6b` look at the settings only. A session without a shell applies the same rules by hand.
- proposal.md gets a required `## Decisions` section (`[needs user]` / `[default]` items); Phase 6a rewrites it as the decisions taken.

### Tests

- `gate-check.test.sh`: 149 checks, including the settings YAML shapes (unindented list, comments, blank lines, inline values, unknown or repeated keys), generous `[needs user]` matching, case-insensitive delta headings, wrapped, root-level and trailing-slash Impact paths, an unreadable design.md and the tasks.md format; twenty-six mutations against a copy each turn it red. `skill-docs.test.sh`: 24 checks (validators named in phases.md exist, gate-check p1/p2 are run, the old Phase 1 hard stop is gone).
- Eval (local, not committed): design suite 05 (Phase 1 trigger stops) with 1.00 / without 0.73; 06 (Phase 3 does not wait) with 1.00 / without 1.00, so it shows 3.0 does not stop there but cannot show uplift; 01, 02, 04 unchanged; 03 (skip the questions) fell to 0.56 on the first run, fixed by the delegation rule, back to 0.85 as before. Phase 6 suite: 01 and 03 at 1.00, 02 at 0.92 (0.83 before). Phase 5 suite: 8 of 8 cases at 1.00 with the plugin, as before. Eval runs have no shell. The numbers above were measured while a shell-less session stopped at every P1/P2 gate; under the final rule (apply the gate rules by hand) 03, 05 and 06 were rerun: 03 with 1.00 / without 0.56, 05 with 1.00 / without 1.00, 06 with 1.00 / without 1.00.

## [2.2.1] - 2026-11-10

### Fixed

- **archive-gate: `$'…'` is a quote.** Inside it `\'` does not close the string. The hook read `$'it\'s'` as a string that ended at the backslash, every quote after it paired wrongly, and an `openspec archive <name>` on a later line was never seen. The code before 2.1.0 missed it the same way.
- **archive-gate: an archive behind a shell keyword or a wrapper is checked.** Command position was the first word of a segment, so `if …; then openspec archive x; fi`, `for … do`, `{ …; }`, `! …`, `env X=1 …`, `command …`, `exec …`, `time …` and a command inside backticks went through unchecked. A command string handed to `bash -c`, `sh -lc` or `eval` is parsed the same way now, when the shell or `eval` is itself in command position. A script fed to a shell on stdin (`bash <<EOF`, `… | bash`) is still not seen.
- **skip-gate: an `archive/` whose mtime is in the future no longer locks every edit.** No declaration written now can be newer than it, and skip-gate has no bypass word, so each code edit was denied until the clock caught up. That comparison is skipped while the directory's mtime is ahead of the clock (needs perl; without it the comparison is made as before).

### Tests

- `archive-gate.test.sh`: 84 checks (two `$'…'` shapes, twelve keyword, wrapper and shell-string shapes, six that must not count). `skip-gate.test.sh`: 53 checks.

## [2.2.0] - 2026-11-10

### Changed

- **R6: a skip reason is the ` — skip: <reason>` suffix only.** The check accepted a `skip:` anywhere on an unchecked task's line, so a task that merely mentioned one (`add a skip: flag`, `noskip:`, `the --skip: option`) counted as excused. It now wants whitespace, a dash (`—`, `–`, `-` or `--`), whitespace and then `skip:` with a reason, which is the form every document of this workflow has taught. `openspec-archive-stats` reads the same parser and counts the same way.
- **Rules version 2 → 3.** A pass verdict recorded under the old rule answers `stale:rules`; run `check` again. A change whose unchecked tasks carry `skip:` in another form fails R6 until the suffix is written out, or the archive is run with `OPENSPEC_ARCHIVE_OK=1`.

### Tests

- `reconcile-check.test.sh`: five lines that mention `skip:` without the suffix, four dash forms that carry it, and a verdict from rules 2. `archive-stats.test.sh`: one more line counted as having no reason.

## [2.1.0] - 2026-11-10

Three deferred review findings on the two gates, each reproduced against the hook before it was fixed.

### Changed

- **skip-gate: the declaration must also be newer than `openspec/changes/archive/`.** The archive marker is only written when this session's archive-gate allows an archive, so an archive that bypassed the gate (`OPENSPEC_ARCHIVE_OK=1`) or one made by another session left an older declaration valid. The directory's mtime moves whenever a change is moved into it, so the gate now compares against it as well and asks for a fresh declaration, with its own deny message. Anything else that moves that mtime (a checkout that adds or removes an archived change) asks for one too.

### Fixed

- **archive-gate: a here-string or a quoted `<<` is not a heredoc.** The heredoc pre-pass matched `<<WORD` anywhere on a line, so `cat <<< hello` or `echo "<<EOF"` followed by `openspec archive <name>` on the next line dropped that line as a heredoc body and the archive went through unchecked. The pre-pass now walks the characters and carries an open quote from one line to the next, so a `<<` opens a heredoc only outside quotes, including inside a string that spans lines. A heredoc opened on a line that is not finished yet (its string is still open, or it ends in a continuation backslash) starts its body after that line ends, as bash does, and each `<<` on a line has its own body. A `$( … )` starts over inside the quote around it, so the heredoc of `git commit -m "$(cat <<'EOF' …)"` counts and a lone quote in its body pairs with nothing outside; inside `$(( … ))` and `(( … ))` a `<<` is a shift, and a `#` comment is skipped, so a lone quote in one opens nothing.
- **archive-gate: a `<<` whose delimiter line never comes is not a heredoc.** Every line after it was dropped to the end of the command, so an arithmetic shift such as `echo $((1<<n))` followed by `openspec archive <name>` went through unchecked. Lines held as a heredoc body are now put back when the delimiter never appears, and scanned again for heredocs, so a real heredoc after the shift, on a later line or the same one, still hides its body. The closing line must equal the delimiter: `EOF)` inside `$( … )` is not taken as one, so that heredoc reads as never closed and its body as commands.
- **archive-gate: a heredoc with a backslash delimiter (`<<\EOF`) is recognised, and the delimiter is read as a whole word.** `<<EOF-TEXT` closes on `EOF-TEXT`; only the leading `\w+` used to be taken. A body that was read as commands had text in it that looked like an archive denied.

### Tests

- `archive-gate.test.sh` covers the shapes above and real heredoc bodies (plain, quoted and backslash delimiters, the `$(cat <<'EOF'` commit-message form, a heredoc opened where a multi-line string closes or before a continuation line, an escaped quote before a quoted delimiter, two heredocs on one line), and gains a case that lets archive-gate allow an archive and then runs skip-gate against the marker it left: the marker name was a literal in both hooks and in both suites, with nothing that ran one hook after the other.
- `skip-gate.test.sh` covers the archive-directory comparison in both directions.

## [2.0.0] - 2026-11-09

Two months of real sessions (10 sessions that loaded the skill, 9 archives, 133 archived changes on disk) showed that the rules which only existed as prose were not followed: no archiving session read the reconciliation checklist, four archived before review had converged, 38% of archived changes still had unchecked tasks, the skip gate's twelve denials never produced the eight-surface check, and users asked three times to skip the Phase 2 questions. 2.0.0 gives those rules a machine check where one is possible and rewrites the playbook where the evidence said it was wrong. Design and plan: `docs/openspec-workflow-2-design-2026-11-09.md`, `docs/openspec-workflow-2-part2-design-2026-11-09.md` and the two plan files beside them.

### Breaking

- **Archiving needs a fresh pass from `reconcile-check.cjs`.** A new PreToolUse Bash hook, `archive-gate.sh`, denies `openspec archive <name>` and the OpenSpec 1.16 `/opsx:archive` template's `mkdir … && mv <changes>/<name> <changes>/archive/…` unless `validators/reconcile-check.cjs check` recorded a pass verdict for that change and none of proposal, design, tasks, review-notes or specs changed since (hashes). Bypass with `OPENSPEC_ARCHIVE_OK=1` in the command, only when the user asks. Fail-open: no jq/perl/node, no parsable change name, or a crash of the checker all allow.
- **Review is closed by the user, and the playbook does not reconcile before that.** The last `## Round` heading of `review-notes.md` must carry `final`, added only after the user says review has converged (R4). Phase 6 has an entry check: without `final`, the agent names the open items and asks instead of rewriting anything.
- **An unchecked task must carry a skip reason.** R6 is a failure: every unfinished task line in `tasks.md` (what OpenSpec 1.16 counts as a task: `-`, `*`, `+` or numbered bullet, at any depth, box not `[x]`/`[X]`, so `[~]` and `[]` are unfinished) needs `skip:` followed by a reason with at least one letter or digit. The definition lives in one module, `validators/task-line.cjs`, used by R6 and the stats script and checked against the real CLI by `tests/cli-claims.test.sh`. A reason may start with punctuation or a quote (`skip: （範圍外）`, `skip: "not required"`) and the colon may be full-width. A pass verdict now records the rules version that produced it, so a verdict written under 1.5.0's warn-only R6 reports `stale:rules` and needs a fresh `check` before the gate lets the change through. `reconcile-check.cjs snapshot` runs R6 first and refuses (exit 1, no state file) while it fails, so ticking and skip notes are settled before `tasks.md` freezes for reconciliation.
- **`tasks.md` is one checkbox per Task.** Phase 3 writes `### Task N` headings with exactly one `- [ ]` line each and the steps as a numbered list; Phase 4 ticks the box in the same turn as the task's commit. OpenSpec counts every checkbox as a task, so the old "one box per step" plans inflated progress and were never ticked.
- **skip-gate v2 reads a declaration file instead of denying once.** With `openspec/` present and no active change, a code edit is denied until `.claude/openspec-skip.<session>.local.md` holds `契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：<一句>`; every key once, as a whole word, with 是 or 否, before `｜`. Any 是 denies and asks for Phase 1. Documentation paths (`.md .mdx .txt .rst .adoc`, `docs/`, `doc/`, `openspec/`, `.claude/`) are not gated. After an archive in the session the declaration must be newer than the archive. The batch window, session flag and `stat` handling of 1.4.x are gone.
- **Phase 2 asks at most two questions.** Facts are looked up, not asked; the cap covers the whole phase and only questions that change *what* gets built; everything else is written as an assumption under `## Open Questions` with its default; a request to skip the questions means none; `design.md` is written in the same reply even when a question is asked. The draft is checked against the new `DESIGN-RED-FLAGS.md` (eight flags adapted from pstack, MIT) and the hits go under `## Trade-offs`.
- **Phase 4 defaults to `executing-plans`.** `subagent-driven-development` is for tasks that are independent of each other (it was the stated default and was used 0 times in two months; executing-plans 5 times).

### Added

- `validators/reconcile-check.cjs` with `snapshot`, `check` (R1–R9, `--json`) and `verify` (exit 3 for no verdict or a stale one, so the hook can tell "not ready" from "the checker crashed").
- `hooks/archive-gate.sh`, `tests/archive-gate.test.sh`, `tests/reconcile-check.test.sh`.
- `scripts/openspec-archive-stats.cjs`: how many archived changes left tasks unchecked, with and without a skip reason, by month; project names hashed unless `--names`. Baseline 2026-11-09 on the author's disk: 133 archived, 51 incomplete (38.3%), 26 with nothing ticked, 0 with a skip reason.
- `DESIGN-RED-FLAGS.md`, `tests/skill-docs.test.sh` (description length, referenced documents exist, the red-flags file keeps its shape).
- `tests/cli-claims.test.sh` and `tests/openspec-version`: every `openspec <sub> --flag` in the plugin's documents is checked against the real CLI's `--help`, `phases.md` must name every upstream `/opsx:*` command (taken from a full-profile `openspec init`), two known-wrong sentences must stay gone, and the tasks.md format sample must count one task per heading in `openspec instructions apply --json`. CI installs the pinned CLI (1.16.1, Node 22) and the test fails there when it is missing; locally it skips with a visible message.
- `phases.md`: a "`/opsx:*` commands by phase" table (propose/new/continue/ff → 1; update → 1–3; explore → 0–2; apply → 4; verify → 5 and 6; sync → 6 after 6b5; archive/bulk-archive → 6c; onboard → none), and the CLI equivalent of `/opsx:apply` (`openspec instructions apply --change <name> --json`), which 1.5.0 said did not exist.

### Changed

- 6c: the incomplete-task warning is expected only for lines that carry a `skip:` reason; the CLI fallback keeps `--yes` because a non-interactive `openspec archive` with any skip line exits 1 without it.
- README, SKILL.md body, PHASE-IDENTIFICATION.md, RECONCILIATION-CRITERIA.md (C1–C5 ↔ R1–R9 table), OUTPUT-CONTRACTS.md and SUPERPOWERS-HANDOFF.md follow the rules above. The SKILL.md description is unchanged in size (1506 chars).

### Notes

- Local eval suites (gitignored; de-identified cases). Red on 1.5.0 → green on 2.0.0, `runs: 3`, with-plugin arm, judge sonnet: tasks ticked after finishing (design/01) 2/3 → 3/3; undone task gets a skip reason (design/02) 0/3 → 3/3; "skip the questions" asks nothing (design/03) 0/3 → 2/3; at most two decisions asked and design.md still written (design/04) 0/3 → 3/3; archive requested before `final` is held back (phase6/01) 0/3 → 3/3; constitution item kept out of the spec (phase6/03) 3/3 → 3/3. The trigger case for a tiny single-module edit stays red (0/3 → 1/3): the skill is not loaded for such an edit, so the skip-gate hook, not text, is the fix there, and a hook cannot run inside the eval sandbox. The existing Phase 5 suite: with-plugin 8/8 at 1.00, mean Δ +0.55 (was +0.60; the without arm moved, the with arm did not).
- Installed copies update only with `claude plugin update openspec-superpowers-workflow`.

## [1.5.0] - 2026-09-14

### Added

- **`review-notes.md` is seeded with a semantics header instead of being created empty.** Phase 1 step 3 now writes a fixed HTML-comment header that pins the entry format, the tag set, and the one question Y/N answers ("must an OpenSpec artifact change in Phase 6?"). Evidence from 62 real archived changes across two projects: files that started empty grew their own header ("Y/N = handled this round"), and 54 entries were written as `[CODE] Y` — 30 of them *after* the 1.3.1 fix-landing-point rule shipped — so the rule existed but nothing pinned the semantics at the moment an entry is written, often by a later session. A new eval case (`08-template-misleads-yn`: an existing file whose header defines Y as "handled") reproduced the drift on 1.4.2 in 3/3 runs with the plugin loaded — the agent tagged the spec-impact item correctly and *still* wrote `[CODE] Y` for finished code fixes, i.e. it followed the project's header over the playbook.

### Changed

- **Phase 5: declining an explicit "edit the spec now" request must be said out loud.** New rule in phases.md and in SKILL.md rule 1: when a reviewer or the user asks to change a spec file during review, the reply states that it is not being changed, why (Phase 6 clean rewrite would overwrite an in-review patch and blur original intent from after-the-fact edits), and that the item is recorded as a Y entry. Eval `02-spec-wording-vs-impl` caught the silent-reroute variant on 1.4.2 (1/3 runs: notes correct, spec untouched, but the reply never said the instruction was not followed).
- **Phase 5: an existing notes header with different Y/N semantics is not adopted** — write entries per the playbook, add one line noting the discrepancy, leave earlier rounds as-is.
- **Tag semantics tightened in phases.md and SKILL.md rule 1**: `[CODE] Y` is declared non-existent (a finished code fix is still `[CODE] N`); `[CONSTITUTION]` is only for a *new* cross-feature rule, "complies with existing rule X" is not an entry (real notes had used it as a compliance remark, 4 lines with no Y/N). The fix-landing-point sentence is lifted from phases.md into SKILL.md rule 1 so it is present when the tag is written, not only when the playbook section happens to be re-read.
- OUTPUT-CONTRACTS.md Phase 1 rows updated from "empty" to "header stub"; validator unchanged (existence check only, header absence never blocks).
- PHASE-IDENTIFICATION.md: the "Phase 5 in progress" signal is now "`review-notes.md` has `## Round N` entries", not "has content" — with the seeded header every fresh Phase 1 folder has content, so the old wording would have misread Phase 1 as Phase 5 (caught in pre-commit self-review).

### Notes

- Local eval suite (Phase 5 flow, 8 cases, `runs: 3`, with/without ablation, sonnet judge — kept out of the repo because cases are de-identified rewrites of client review notes): baseline on 1.4.2 mean Δ +0.59 with case 02 at 0.90 and case 08 at 0.47/0.47 (Δ 0). Post-change figures are recorded in the commit that ships this version.

## [1.4.2] - 2026-08-13

### Fixed

- **Batch window survives non-BSD `stat`: numeric whitelist before arithmetic.** The window read the flag's mtime via `stat -f %m || stat -c %Y` — BSD-first. On GNU/uutils coreutils (Ubuntu CI, and macOS projects whose nix devshell shadows `stat`), `-f` means *filesystem* mode: the call "succeeds" printing non-numeric text, the fallback never runs, and the non-numeric value hits `$((now - mtime))` — under `set -u` an arithmetic expansion error kills the shell *without* running the ERR trap, so the hook died with exit 1 (harness treated it as non-blocking → net allow, noisy error; the batch window was effectively dead on those machines). Caught twice within the hour by both machine layers: CI red on ubuntu (assertion 3a) and the first live end-to-end test (`列 64: File: 未綁定的變數`). Fix: try `-c %Y` first, fall back to `-f %m`, and pass both `now` and `mtime` through a digits-only whitelist — anything non-numeric degrades gracefully to allow instead of crashing. Two new fixture cases pin the contract cross-platform: a fake non-numeric `stat` must exit 0 and allow; a fake numeric `stat` must keep denying inside the window (suite now 24 assertions).

## [1.4.1] - 2026-08-13

### Fixed

- **Frontmatter is now strict-YAML valid: the description scalar is double-quoted.** The unquoted plain scalar contained "touches none of: public API" — a colon+space sequence strict YAML rejects — so `claude plugin validate --strict` failed on this skill since 1.3.0, misleadingly claiming it "loads with empty metadata" while the lenient runtime parser demonstrably loaded it in full (the validator-vs-runtime contradiction was itself the reason to fix). Quoting proven safe by live precedent: superpowers 6.2.0's brainstorming skill ships a double-quoted description on disk and renders unquoted in the active skill listing. `--strict` now passes; description content is byte-identical.

## [1.4.0] - 2026-08-13

### Added

- **skip-gate PreToolUse hook — the implicit SKIP decision is machine-forced into an explicit, auditable procedure** (new enforcement surface, hence minor bump). A real session skipped the whole workflow by eyeballing a one-line CLAUDE.md summary ("no contract surfaces → bare superpowers") while the change actually touched cross-module behavior documented in the canonical spec, in an already-spec'd capability domain — the 1.3.0 rubric was in context and still lost to rationalization, because skipping happens by *not acting* and leaves no artifact to check. The hook closes the gap at the moment of the mistake: on the session's first Edit/Write in a project that has `openspec/` but no active change under `openspec/changes/` (`archive/` doesn't count), it denies the edit once and demands a per-surface verdict on all eight contract surfaces before retrying. Scope guards: paths under `openspec/` and `.claude/` are exempt (writing proposals/specs IS workflow work), as are paths outside the project; fully fail-open (missing jq, malformed input, unknown tool shapes all allow) — the gate forces the judgment to happen and leave a trace, it does not judge contract risk itself. A 5-second batch window keeps sibling edits from the same parallel tool batch behind the gate (cross-vendor review caught that a bare once-per-session flag lets every edit after the first sail through when the session opens with a multi-file batch); path exemptions are evaluated before the window so legitimate same-batch `openspec/` writes are never denied. Ships with a 20-assertion fixture suite (`tests/skip-gate.test.sh`) wired into CI; flag dedupe, archive exclusion, and path exemption are each mutation-verified to break a distinct assertion, and the session_id path-sanitization case doubles as a fail-open regression guard (an unsanitized `/` in the id silently disabled the whole gate via a failed `touch`).

### Changed

- **SKIP clause proceduralized: an unstated skip is now a workflow violation.** The frontmatter description (the site where the auto-trigger skip decision is actually made) now requires the reply to enumerate all eight surfaces with explicit per-surface verdicts, and adds the strongest concrete signal the incident exposed: a behavior change in a capability domain already covered by `openspec/specs/` almost always has spec impact — a checkable environment fact that outranks free-form judgment. `PHASE-IDENTIFICATION.md` Case 3 gains the same SKIP 判定程序, 絕對禁止事項 gains the corresponding ❌, and the README documents the hook and its boundaries. The SKIP block sits ahead of the role-separation elaboration inside the description: the runtime truncates skill descriptions both per-skill (1536-char cap) and under an aggregate listing budget (`skillListingBudgetFraction`), so the load-bearing invariant must not live at the truncatable tail.

## [1.3.1] - 2026-08-08

### Changed

- **Review-notes tagging criterion made explicit: tag by fix-landing artifact, not problem nature.** `phases.md`'s Tags section described `[REQUIREMENT]`/`[DESIGN]` by the *kind* of problem ("wrong behavior" vs "architecture change"), while `RECONCILIATION-CRITERIA.md` C1 routes strictly by *artifact destination* ([DESIGN] may never touch `specs/`). The two axes diverge for one recurring class: a deliberate design decision whose conflicting text lives in a spec scenario's literal wording — by nature it feels like `[DESIGN]`, but the file that must change is the spec, so the correct tag is `[REQUIREMENT]`. Surfaced in a real Phase 6 run where two such items had to be re-tagged at the gate; the silent-failure mode this prevents is worse: honoring a mis-tag by skipping the spec edit archives a spec-vs-implementation divergence into `openspec/specs/` as permanent wrong truth. `phases.md` now states the criterion at the tag-writing site (Phase 4/5, where context is fresh), and C1 gained a 修正路徑 paragraph institutionalizing the re-tag-with-note recovery instead of leaving it to improvisation.

## [1.3.0] - 2026-07-26

### Changed

- **SKIP clause sharpened from vague to contract-risk rubric** (trigger-behavior change, hence minor bump). The frontmatter description's skip criterion was "small bug fixes with no spec impact" — undefined, and "small" invites judging by LOC / file count, which are the wrong proxies. It now enumerates the contract surfaces whose absence permits skipping: public API / data contract / schema / migration / backward compatibility / security or permission boundaries / concurrency or consistency / cross-module behavior — with an explicit "judge by contract risk, not LOC or file count". Single-module changes with clear acceptance criteria and none of those surfaces route to bare superpowers skills. Rationale: this is where the auto-trigger skip decision is actually made, so the rubric belongs in the description (self-contained for every installer) rather than in any one user's global CLAUDE.md.
- `PHASE-IDENTIFICATION.md` Case 3's 判斷標準 now lists the same contract-surface signals alongside the SHALL/MUST test; root README's when-NOT-to-use line synced to the same language.

## [1.2.2] - 2026-07-02

### Changed

- **Phase 1 pre-check path unified to `${CLAUDE_PLUGIN_ROOT}`.** `phases.md` step 4 previously used a repo-relative path (`node skills/openspec-superpowers-workflow/validators/…`) with a prose "resolve it from where the skill is installed" note; it now uses `${CLAUDE_PLUGIN_ROOT}/skills/…`, matching the convention every other plugin's commands/skills use (verified available in the skill bash context). Makes the pre-check runnable as-written regardless of the caller's working directory.

## [1.2.1] - 2026-07-01

### Added

- **Phase 1 gained an optional, lenient local pre-check.** `phases.md` Phase 1 now suggests running the bundled `validate-openspec-workflow.cjs` on the change folder to catch a missing artifact (any of `proposal.md` / `design.md` / `tasks.md` / `review-notes.md`, or no `specs/**/spec.md`) or an empty SHALL/MUST first paragraph *before* the authoritative `openspec validate --strict` — fast and needs no OpenSpec install. Explicitly a pre-check, not a substitute for the strict CLI. From the loop-design review (`docs/loop-design-review-2026-07-01.md`), which noted the plugin's own validator was CI-only and never surfaced in the live workflow.

## [1.2.0] - 2026-07-01

### Added

- **Durable, machine-checkable output contract for the workflow.** New `skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs` (zero-dependency) plus reference docs `OUTPUT-CONTRACTS.md`, `RECONCILIATION-CRITERIA.md`, and `PHASE-IDENTIFICATION.md` — formalizing what was previously prompt-only guidance (Phase 5 reconciliation criteria, Phase 6 archive discipline) into an explicit, testable contract, enforced repo-wide via GitHub Actions CI and a PostToolUse hook.
- `SUPERPOWERS-HANDOFF.md` — documents the Phase 2-4 handoff contract to Superpowers skills (`brainstorming`, `writing-plans`, `subagent-driven-development`).

### Notes

- This release was previously merged (commit `893821c`, PR #4) without a corresponding version bump on `plugin.json` / `marketplace.json` or a changelog entry — the plugin sat at `1.1.0` both before and after a functional (non-doc) change. This entry backfills the version and changelog for that change; no further code changes were made.

## [1.1.0] - 2026-06-17

### Changed
- **Phase 4 playbook realigned to Superpowers 6.0.0.** `phases.md` Phase 4 previously documented a per-task *two-stage* review (Stage 1 spec compliance, Stage 2 code quality). Superpowers 6.0 merged these into a single `task-reviewer` that returns both verdicts in one pass — plus a "can't verify from the diff" verdict — followed by one whole-branch review at the end on the most capable model. The playbook now matches the actual `subagent-driven-development` flow instead of describing the retired two-reviewer design.
- **Worktree location note added to Phase 4.** Superpowers 6.0 removed the legacy global `~/.config/superpowers/worktrees/`; worktrees now live in the project under a local worktree *root* — `.worktrees/` by default (or an existing `.worktrees/`/`worktrees/`), with each worktree created under it at `<root>/<branch>` rather than at the root itself. Phase 4 now reminds you to keep that root git-ignored.
- **Reviewer-integrity rules added to Phase 4.** Findings may not be suppressed and severity may not be pre-rated, mirroring Superpowers 6.0's guard against a controller coaching the reviewer; a plan-mandated defect is surfaced for the human to decide on.

### Notes
- Requires **Superpowers >= 6.0.0** for the Phase 4 behaviour described above. Earlier Superpowers still works but runs the legacy two-reviewer, task-by-task flow.
- No behavioural change to Phases 1-3, 5, 6. This release only realigns documentation with the upstream SDD rewrite.

## [1.0.1] - 2026-04-10

### Changed
- **Stronger auto-trigger guarantees**: `SKILL.md` frontmatter `description` rewritten with imperative "MUST use" wording, expanded trigger list (now also matches `openspec CLI` commands and the presence of `openspec/changes/<name>/` folders), and explicit forbidden-behaviours enumeration (no spec modification in Phase 5, no sidecar design/plan files, no incremental spec patching in Phase 6, no `[CONSTITUTION]` items in feature specs). This removes the need for users to add a separate "must call this skill" reminder in their own `CLAUDE.md`, because the same meta-instruction now ships with the plugin.
- Added an "Activation reminder" note at the top of `SKILL.md` body that anchors Claude on the non-negotiable rules before any action, mirroring the pattern used by `superpowers:using-superpowers`.

### Notes
- No change to `phases.md` — the detailed playbook is unchanged.
- Behavioural intent is unchanged from 1.0.0; this release strengthens the **likelihood** that Claude actually invokes the skill when it should.

## [1.0.0] - 2026-04-10

### Added
- Initial release
- `openspec-superpowers-workflow` skill with progressive disclosure (SKILL.md + phases.md)
- Six-phase feature development workflow:
  - Phase 1: Spec Definition (OpenSpec leads)
  - Phase 2: Design Refinement (Superpowers `brainstorming` → overwrites `design.md`)
  - Phase 3: Task Planning (Superpowers `writing-plans` → overwrites `tasks.md`)
  - Phase 4: Implementation (Superpowers `subagent-driven-development` + TDD)
  - Phase 5: Review & Feedback (records to `review-notes.md`, never modifies spec)
  - Phase 6: Reconcile & Archive (OpenSpec, clean rewrite discipline)
- Six non-negotiable rules enforcing strict role separation between OpenSpec and Superpowers
- `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag taxonomy with Y/N classification for Phase 5 feedback
- Clean-rewrite discipline for Phase 6 reconciliation (no incremental patches)
- `tasks.md` freeze rule during reconciliation (execution history, not current spec)
- Constitution routing to `openspec/config.yaml` `context:` / `rules:` fields (not feature specs)
- Prerequisites section documenting OpenSpec CLI vs `/opsx:*` slash-command alternatives
- `openspec init .` gotcha documented (no `--here` flag)
- Validator strictness gotcha documented (`SHALL`/`MUST` must appear in first paragraph of each `### Requirement:`)
- Archive folder date-prefix behaviour documented (`openspec/changes/archive/<YYYY-MM-DD>-<name>/`)
- Decision quick-reference table covering 13 common situations
- Anti-patterns list (8 items) covering the most frequent mistakes
