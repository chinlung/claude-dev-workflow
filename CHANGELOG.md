# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [1.11.0] - 2026-09-23

### Added

- **scope-ledger 1.0.0** — a per-goal scope ledger, a per-repository follow-ups backlog and six fail-open hooks that keep review-driven work from expanding past the original request without letting real bugs or security findings be skipped. The ledger (`.claude/scope-ledger.local.md`) holds the user's goal verbatim, a `mode` (converge, or harvest when the goal itself is an audit or a batch of findings), a review round counter and In scope / Deferred / Log sections; it is not bound to a branch, because one goal routinely spans hotfixes and PR chains. PreToolUse denies the main thread's first source-file write once when no ledger exists — through Edit/Write or through `sed -i` / `perl -pi` / heredoc redirects / `cp` / `mv` / `patch` in Bash — and asks for `/scope-ledger:scope init` (subagent edits pass without consuming that one deny); UserPromptSubmit reminds once per session, non-blocking; PostToolUse injects the mode's finding-triage policy after every review-entry skill or review-type subagent (converge: findings are input, not a work order — adopt what belongs to this change plus exploitable security findings in the touched code, sibling instances, MUST rules and boy-scout fixes, defer the rest with severity, reason and destination, dismiss only with counter-evidence; harvest: findings are the work, batched by severity) and counts a round per allowlisted skill call; Stop blocks once per distinct open-item state and asks for a status rather than more work; SessionStart replays the whole In scope list and the open follow-ups after compaction or resume. `done` moves deferred items into `.claude/scope-followups.local.md`, and a HIGH security item cannot be deferred without an issue or a next goal. A git-tracked ledger — including one reached through a committed symlink or submodule — is repository-controlled content and every hook ignores it; the Codex cross-vendor pass caught the first version replaying a committed file verbatim into context, the pre-push security review caught the symlink / submodule bypass of that check. Designed from measurements, not intuition: across the author's whole session history the todo tool had been called zero times, one four-day session ran 23 security reviews across 17 PRs and ended with the user asking what the finding IDs meant, and a session that did use the task tool still had the user ask five times what was left — the audit backlog lived outside the task list. No existing skill on skills.sh enforces this with hooks; the closest (`piv-fix-review-findings`) has the same policy in prose, and its four-way taxonomy is adopted here. 276 fixture assertions, green under bash 5 and macOS bash 3.2 (and under a pure BSD userland), twenty-two mutations verified red on a copy. Two pre-release review rounds changed fourteen things before shipping, each recorded in the plugin's CHANGELOG with its reason: the first (five adversarial verifiers, Codex, the pre-push security review) — tracked-ledger handling and its symlink / submodule bypass, Agent dispatches not counting as rounds, an allowlist instead of keyword stems, subagent pass-through, a bump lock, frontmatter synthesis; the second, measured against the author's session history — per-goal instead of per-branch ledgers, the harvest mode, the follow-ups backlog with the HIGH-needs-a-destination rule, four adoption exceptions plus counter-evidence for dismissals, the Bash write gate and first-prompt reminder, a Stop message that defers to the user's last instruction, stale-lock recovery; and the second round's own reviews — Codex found a redirect after a heredoc delimiter slipping past the Bash gate, the security review found the tracked-ledger check defeated by case folding on APFS (`.Claude/…`) and the `$TMPDIR` flags written without a symlink check. Design: `docs/scope-ledger-design-2026-09-23.md`.

## [1.10.13] - 2026-09-19

### Fixed

- **The root README's session-learning section is deduplicated, and the drift it accumulated is fixed.** That section had grown to 62 lines describing the same pipeline, scope routing and hook behaviour as the plugin's own README, and one copy had been wrong since 2026-08-03: it described the Stop hook as firing on a transcript-length floor plus a once-per-session flag, never mentioning the already-ran detection that 1.0.1 added — the release's main fix, missing from the user-facing docs for over a month, found only when the plugin got a README of its own. Both root READMEs now carry one dense paragraph (including that detection) and link to the plugin README, which is the shape `security-audit`'s section already used and well inside the 24-121 line range the other sections span. The Phase 1 candidate table, which existed only in the root copy, moved into the plugin README rather than being dropped — deduplicating is moving, not deleting — after checking it column-by-column against `commands/save-session.md`. `session-reflect`'s section gets the same pointer to its own README. `CONTRIBUTING.md` §3 now says to summarise and link when a plugin has its own README, with this drift as the reason, so the rule carries its own justification.


## [1.10.12] - 2026-09-18

### Fixed

- **session-learning 1.0.1 → 1.0.2, session-reflect 1.0.1 → 1.0.2** — documentation added to an existing plugin does not reach installed copies unless the plugin's version moves. The plugin cache is keyed by version (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`), so an unchanged version is never re-fetched. Measured on this machine rather than assumed: `session-reflect`'s README was added in `c7c8169` with no bump, and the cached `1.0.0/` tree does not contain it — only `1.0.1/` does, where a later bump happened to carry it in. That precedent therefore was not evidence that doc-only changes need no bump; it was an undelivered file nobody noticed. The two changelogs backfilled in 1.10.11, and session-learning's new README, are all in that state, so both plugins are bumped to deliver them. Raised by the Codex cross-vendor pass on the README; the cache measurement widened it to the changelogs as well. `CONTRIBUTING.md` §4 now states the rule with the mechanism, so "it is only documentation" stops being a reason to skip the bump.

- **The README written one commit earlier contained a live self-suppression bug, and the self-review caught it before it shipped.** Its flow diagram quoted the invocation shapes the Stop hook matches on. Those shapes carry no quotes, so they are not escaped inside a JSONL transcript string, and the hook's `grep -Eq` matched them from the README's own text — any session that had read the file was treated as having already run `/save-session` and got no reminder again. Exactly what session-learning 1.0.1 fixed, reintroduced through the file a user is most likely to open, by a README that also *claimed* "merely mentioning the command never suppresses the reminder" — a guarantee its own two lines above disproved. Fixed in three places, because one is not enough: the hook's pattern is anchored on the JSON quote that opens the field, the README describes the shapes instead of quoting them, and a new assertion feeds the real README to the hook so a future doc edit cannot re-arm the trap quietly. The same README also asserted the two session plugins "are not merged on purpose", an intent no commit or doc in this repo records — the same shape as the "deliberately ships without one" claim this release set out to correct. It now says only what the code shows.
- **The new gate's collection and wiring had no canary at all — four mutations of them stayed green.** Stubbing the symlink list to `[]`, swapping `isSymbolicLink()` for `isFIFO()`, hardcoding `readme: true`, and dropping the second argument at the call site each left 203 passed / 0 failed, because the canaries hand `pluginDirProblems` a written-out map: the judgement was covered, the collection was not, and a clean repo reports nothing either way. Collection, floor and judgement now live in `pluginDirGateProblems()` behind one call, covered by a `mkdtemp` fixture tree (a complete plugin, one missing its README, one whose README.md is a *directory*, a half-built dir, a symlink, a dangling symlink, a loose file) that asserts the inventory and the end-to-end problem list. All six mutations die. Two real defects fell out of the same work: `existsSync` accepted a **directory** named README.md — and README.md is the one required file with no downstream reader to catch that — and on case-insensitive APFS it accepted `readme.md`, which CI's case-sensitive filesystem would then reject (green locally, red in CI). Both now go through `statSync().isFile()` plus a readdir name check.
- Corrected in the same pass: "invisible to all five repo-structure gates" was wrong — the version gate walks marketplace *entries* and resolves them with APIs that follow symlinks, so it does see a symlinked plugin; only the four gates that walk `pluginDirs` skip it (the gate's own message said so correctly, the prose around it overstated). `CONTRIBUTING.md` §1's template now marks `README.md` and `CHANGELOG.md` as required and lists `commands/`, `hooks/`, `agents/`, `tests/` — the gate's error message points contributors at that template as the authority, and it did not carry the rule it was cited for. Plus the README's Phase 3 (it listed three of five dedupe sources, omitting the two `commands/` dirs its own table names as destinations), a `two rules` comment that now covers three, a docblock that contradicted itself about whether README is required, the `one-line nudge` that actually blocks the stop once, `$TMPDIR` → `${TMPDIR:-/tmp}`, a missing Testing section, and a denyWrite message that told a repo-internal symlink its target "is not covered by denyWrite" when the literal already covered it.

## [1.10.11] - 2026-09-18

### Added

- **code-audit-rigor 2.0.3 → 2.0.4, multi-agent-debate 1.2.0 → 1.2.1** — `/review-branch`, `/review-pr` and `/debate` now machine-check that their own output artifact is git-ignored before continuing: `git check-ignore -q -- <artifact>; echo "check-ignore rc=$?"`, with all three exit codes handled — `0` ignored → continue; `1` not ignored → first ask `git ls-files --error-unmatch` whether it is already *tracked*, because a `.gitignore` line does nothing for a tracked file and `git rm --cached` has to come first; `128` not a git repo, or git itself failed (bare repo, path outside the worktree, broken `GIT_DIR`) → skip, not an error. The `rc` is echoed deliberately: `-q` prints nothing and a trailing `; RC=$?` assignment exits 0 itself, so all three states would reach the agent as an identical "exit 0, no output" and default to passing — the self-review caught exactly that in this change's own first draft, where the delivered step was a silent no-op. No command edits `.gitignore`; it is the project's own setting. All three previously delegated this to a one-off line per project, i.e. to memory, and this repo is the proof that does not hold: `review-branch-results.json` got its line only in 1.10.10, while `review-pr-comments.json` and `debate-output.json` had never been ignored at all — the first pass here fixed two of the three and a coverage sweep found the missed one. All three are covered now; `prior-debate.json` is deliberately excluded, being the next `/debate` run's input rather than a throwaway. Surfaced by this session's `/session-reflect:reflect`, whose adversarial verifier also refuted the original "move the artifact elsewhere" proposal: `.gitignore` entries without a leading slash match at any depth, so the existing line already covers a relocated copy — relocation does not remove the dependency on a `.gitignore` setting, and the only setting-free location is outside the worktree, where `$TMPDIR` differs inside and outside the sandbox. Details: each plugin's CHANGELOG.

### Fixed

- Both root READMEs carried a copy-pasteable `node plugins/high-precision-dev/validators/validate-high-precision-output.cjs …` command. That validator was removed as dead code in high-precision-dev 1.1.0 — its own CHANGELOG records why (it only ever validated a JSON shape no agent produced) — but the removal never reached the root READMEs, so anyone following them hit a missing file. Same shape as the codegraph npm links fixed in 1.10.9: a plugin-scoped fix that left the root docs pointing at something that no longer exists. Every `plugins/**.cjs` path the root docs and `CONTRIBUTING.md` now mention resolves on disk (swept, not spot-checked).
- **A claim this release made about two plugins was never verified, and it was wrong.** The changelog gate skipped plugins with no `CHANGELOG.md`, and the code comments plus `CONTRIBUTING.md` described session-learning and session-reflect as *deliberately* shipping without one. Nothing supports that reading: `CONTRIBUTING.md`'s own directory template lists `CHANGELOG.md`, §4 names the plugin changelog as one of the three places a version lives, no commit records such a decision, and the repo's precedent runs the other way — `e4a2729` backfilled 1.0.0 entries for high-precision-dev and multi-agent-debate the moment it found they had none. Both plugins were simply missed, and the claim turned an omission into a policy. Their changelogs are now backfilled from the root changelog and git history (labelled as written after the fact), and a fifth repo-structure gate enforces directory completeness: a dir with a `plugin.json` must have a `CHANGELOG.md`, and a dir carrying `CHANGELOG.md` / `commands/` / `skills/` without a `plugin.json` is reported as unfinished. That closes the two blind spots the reflect backlog had parked — deleting a plugin changelog silently disarmed the changelog gate (`rm` runs through Bash, which the PostToolUse hook, scoped to Edit/Write/MultiEdit, never sees), and a half-built plugin dir was invisible to every gate (the version gate walks marketplace entries; the registration gate only collects dirs that already have a manifest). Both directions were mutation-verified against a copy of the real repo: removing `plugins/codegraph/CHANGELOG.md`, and planting a manifest-less `plugins/zztest/`, each turn the new gate red while all four older gates stay green. Suite 176 → 185 (8 canaries + 1 live check), red-first. Neither the backfill nor the gate changes any plugin's behaviour, so no version moves.
- **That gate's canaries did not hold it up either — 15 mutants, 10 survived.** The self-review mutated `pluginDirProblems` fifteen ways and ran the suite on a copy each time: a `break` after the first half-built push, "skip once any problem exists", an early return, `parts.join(' + ')` reduced to `parts[0]`, the half-built message replaced by *the opposite failure mode*, the dir-name prefix dropped, and the coverage floor deleted or made always-false all left 185 passed / 0 failed. Three causes, each now closed: the case labelled "one broken dir does not mask another" held a single broken dir, so its expectation of 1 was met whether or not a second could be reported (and one of each kind is still not enough — a `break` in the half-built branch is invisible unless *two* dirs reach it, so the case now carries two of each breakage plus a clean dir); only one of the two branches had a whole-message assertion, which is why the opposite-meaning message stayed green; and the floor was an inline `if`, so nothing guarded the guard — it is now `shapedCountProblems()` with four canaries of its own. `parts` also listed three of the eight components this repo actually ships, leaving `agents/`, `hooks/`, `README.md` and a `.claude-plugin/` without a `plugin.json` invisible; `hooks/` mattered most, since `plugins/<p>/hooks/*` is exactly what the denyWrite gate enumerates as EXECUTED, so a manifest-less hooks dir would be run while counting as "not a plugin". Suite 185 → 194. Boy-scout, pre-existing: a *file* named `commands` passed `existsSync` and made the collision gate's `readdirSync` throw ENOTDIR, aborting the run with no Summary and no failure list — both call sites now use stat semantics. `dirShapes` is `Object.create(null)`, so a `plugins/__proto__/` dir is a key rather than a prototype write.
- **The two blind spots the reflect backlog still held are closed, and the argument that closed them is now applied consistently.** A plugin dir that is a *symlink* was invisible to the four gates that walk `pluginDirs` — `Dirent.isDirectory()` is lstat semantics and false for a symlink, so collision, dir-completeness, plugin-changelog and registration all skipped such a plugin outright. (Not all five: the version gate walks marketplace *entries* and resolves them with `path.resolve` + `existsSync`/`readFileSync`, which follow symlinks, so it does see one. The gate's own message and docblock said "every gate that walks pluginDirs" correctly; only the prose around it overstated to "all five", and the self-review measured the difference.) Symlinked plugin dirs are now refused rather than supported: the local hook follows symlinks when it runs `plugins/<p>/tests/*.test.sh`, so accepting them would widen an execution surface for a use case this repo does not have. (The self-review corrected the backlog's own framing here: the pre-existing denyWrite gate did already catch such a dir, under a different name — both now report it, with complementary messages.) And `README.md` is required of every plugin by exactly the argument that required `CHANGELOG.md` a commit earlier — CONTRIBUTING §1's template lists both and marks only `.mcp.json` / `reference.md` optional — so session-learning, the one plugin that lacked a README, got one written from its own manifest, command and hook rather than from memory. Using half of a reasoning is how the "deliberately ships without one" claim happened in the first place. Both rules are mutation-verified against a copy: a symlinked `plugins/ghost` and a removed `plugins/codegraph/README.md` each turn the gate red with a message naming the dir. Suite 194 → 203; every new branch gets two canary inputs, because one is not enough to catch a `break`, plus a whole-message assertion.

## [1.10.10] - 2026-09-18

### Fixed

- **code-audit-rigor 2.0.2 → 2.0.3** — call-chain tracing named `codegraph_callers` / `codegraph_impact` as MCP tools in three places (the skill's tool-selection note, `/review-branch` Phase 2 step 3, and `STEEL_MANNING.md`'s OC-1 check). codegraph lists only `codegraph_explore` over MCP by default, so those calls return "not found"; all three now name the CLI commands and state that "not found" means unlisted, not broken. `/review-branch`'s recovery condition is corrected too — it gated the grep fallback on a missing index, but the failure happens with a healthy index present. Pre-existing since 2026-06-08 and self-contradictory on the day it shipped; surfaced by the codegraph re-baseline in 1.10.9. Details: `plugins/code-audit-rigor/CHANGELOG.md`.

### Notes

- Marketplace patch bump 1.10.9 → 1.10.10.
- `.gitignore` now covers `review-branch-results.json`, the `/review-branch` output artifact.
- Repo infra (no plugin's shipped behaviour changes, hence no further bump): a fourth repo-structure gate, **plugin changelog bookkeeping** — each `plugins/<p>/CHANGELOG.md` that exists must carry its own `plugin.json` version as the top `## [x.y.z]` heading, under the same semver / unique / strictly-decreasing rules the root changelogs get; a plugin that ships without a changelog (session-learning, session-reflect) is skipped, not required — a premise 1.10.11 overturned; see above. The version gate structurally could not cover this — it compares every changelog it is handed against `metadata.version`, the marketplace's number rather than the plugin's — so `plugins/<p>/CHANGELOG.md` was read by no gate and no hook, which `CONTRIBUTING.md` recorded as a known limit. It had already cost twice: dev-workflow shipped 1.1.0 and then 1.1.1 against a `[1.0.1]` top heading (dfe8c1b/c920bd9, 2026-03-07), caught by hand 5 days later in 35c0a9c whose fix reverted the version *down* to match — and that revert also reverted a description by mistake, which took another month to surface (0631b24). Both root changelogs and every plugin's now share one heading-rule function, so the two rule sets cannot drift apart. Suite 167 → 175 (7 canaries + 1 live check), red-first, then mutation-verified against the real repo: moving only `plugins/codegraph/CHANGELOG.md`'s top heading to `[1.0.2]` turns the new gate red naming that file while the old version gate stays green — the drift is invisible to it. The local PostToolUse hook now triggers on `plugins/<p>/CHANGELOG.md` too (its assertions 22 → 23, red-first; `docs/CHANGELOG.md` and a plugin-internal `marketplace.json` still no-op). The gate's own protection is machine-checked as well: the canaries drive the pure function with hand-written maps, so they all stayed green when the collection loop was mutated to collect nothing (175 passed, 0 failed — a gate that had silently stopped reading anything). A coverage floor computed *independently* of that loop now names every changelog on disk it failed to read, and the same mutation turns it red; one canary asserts the whole message rather than the count, since naming the wrong file or crediting `metadata.version` instead of `plugin.json` also returns exactly one problem. A non-string `version` is reported instead of skipped: the version gate compares entry against manifest with `!==`, so one regex bump that drops the quotes on both sides compares equal and passes, which would leave that plugin's changelog checked by nobody.

## [1.10.9] - 2026-09-18

### Changed

- **codegraph 1.0.1 → 1.1.0** — skill re-baselined on codegraph CLI 1.6.0 (was 0.9.7). Upstream's MCP server now lists only `codegraph_explore` by default; `codegraph_trace` / `codegraph_context` are gone and `explore` / `node` gained CLI commands. The skill's entry-point table had four wrong cells and its proactive triggers named three MCP tools a default 1.6.0 server does not offer. Rewritten around "one MCP tool, everything else on the CLI". The reliability fallback no longer tells the agent to retry or run `codegraph init` when a tool is "not found" (the tool is unlisted or removed, not broken; indexing is the user's decision). `reference.md`: `init` replaces the deprecated `init -i`, allowlist trimmed to entries that resolve, new `CODEGRAPH_MCP_TOOLS` section, new gotcha (`<unknown-subcommand> --help` exits 0). Details and what was *not* re-verified: `plugins/codegraph/CHANGELOG.md`.

### Fixed

- Root READMEs (EN / zh-TW): every codegraph npm link and the prerequisite now name the scoped `@colbymchenry/codegraph`. Three links (two EN, one zh-TW) still pointed at the unscoped `codegraph` npm package — the unrelated placeholder that codegraph 1.0.1 removed from the plugin's own docs; that fix updated the plugin's four references and never reached the root READMEs.

### Notes

- Marketplace patch bump 1.10.8 → 1.10.9.
- Root READMEs (EN / zh-TW) and the plugin README carry the new entry-point table and triggers.

## [1.10.8] - 2026-09-17

### Fixed

- **session-reflect 1.0.0 → 1.0.1** — the review playbook now actually loads. The plugin shipped both `commands/reflect.md` and `skills/reflect/SKILL.md`, which resolve to the same qualified name `session-reflect:reflect`; the command shadowed the skill (the skill listing showed a single entry carrying the command's description), so a Skill-tool call returned the command body — whose only content was "call the `session-reflect:reflect` skill" — and the playbook never loaded. Both the manual path and the Stop-hook path (`reflect-gate.sh` asks for that same skill name) hit the self-reference; the model had to locate and Read `SKILL.md` by hand. Removed the redundant command: skills are user-invocable by default (`/session-reflect:reflect`), and `skills/` is the documented layout for new plugins. The qualified name is unchanged, so the gate's already-reflected pattern (`"skill":"session-reflect:reflect"`) and `tests/gate.test.sh` need no change.

### Notes

- Marketplace patch bump 1.10.7 → 1.10.8.
- READMEs (root EN / zh-TW and the plugin's own) now name the manual trigger by its qualified form `/session-reflect:reflect` instead of the bare `/reflect`.
- Verified end-to-end (2026-09-17): with 1.0.1 installed and plugins reloaded, a Skill-tool call to `session-reflect:reflect` returns the playbook body (base directory `…/session-reflect/1.0.1/skills/reflect`), and the skill listing carries SKILL.md's description. The same session had reproduced the bug on 1.0.0 an hour earlier — the identical call returned only the command's two-line self-reference — so the before/after is a like-for-like comparison. Not exercised yet: the Stop-hook-triggered path under 1.0.1 (the gate fires once per session and had already fired); it requests the same qualified name, so the same resolution applies.
- Repo infra (no plugin's shipped behaviour changes, hence no further bump): `scripts/validate-fixtures.cjs` gains two repo-structure gates, both surfaced by shipping this release. **Command/skill collision** — a plugin's `commands/<X>.md` next to a skill whose effective name (frontmatter `name`, else dir) is `<X>` now fails; `claude plugin validate` passes that layout, which is how the 1.0.0 bug shipped. **Version bookkeeping** — each marketplace entry must equal its `plugin.json`, `metadata.version` must equal the top heading of both root changelogs, and headings must be x.y.z, unique and strictly decreasing. This release was first cut on a base 3 commits behind, claiming a 1.10.7 already taken upstream; on integration `marketplace.json` auto-merged *silently* to the wrong number because both sides had made the identical `1.10.6→1.10.7` edit. The uniqueness rule exists because the top-heading rule alone misses a resolution that keeps two `[1.10.7]` sections. Suite 130 → 139 (7 canaries feeding planted defects + 2 live checks); each gate additionally mutation-verified against the real repo (shadowing command restored; metadata reverted; duplicate heading; `plugin.json` bumped alone — all red, all restored green). Known residue: two releases folded into one section is not statically detectable.
- A third gate, **marketplace registration**: every `plugins/<p>/` that has a `plugin.json` must be pointed at by some marketplace entry's `source`, and that entry's `name` must equal the manifest's `name`. The version gate walks *entries*, so a plugin nobody registered never reached it (self-review flagged this as a scope expansion and parked it in the reflect backlog; done the same day). An unreadable `marketplace.json` yields one "cannot evaluate" failure rather than nine cascading false orphans. "Unreadable" and "readable but nameless" are kept distinct (only the former is skipped, and the name test is an explicit `typeof` — with a bare `!==`, an entry and a manifest that both lack a name compare equal), and the marketplace is shape-normalised once for both gates so valid-JSON-of-the-wrong-shape (`plugins` an object, a `null` element, a manifest that is `null`) is a named ✗ instead of a summary-dropping `TypeError`; a malformed element is reported, never silently filtered. Suite 139 → 146 (6 canaries + 1 live check), red-first twice — both reds were delivered by the newly widened local hook itself; mutation-verified against the real repo (orphan dir; orphan with a malformed manifest; renamed manifest; manifest missing / mistyping `name`; broken, object-shaped and `null`-holed marketplace; `null` manifest).
- The local PostToolUse gate now also triggers on exactly the files those gates read (`plugins/<p>/commands/*.md`, `plugins/<p>/skills/<s>/SKILL.md`, `plugins/<p>/.claude-plugin/plugin.json`, the root `marketplace.json`, the two root changelogs); previously such an edit was gated only in CI. The match is root-relative and fully anchored: the first draft matched by substring and self-review measured it firing a full ~5 s suite run on `~/.claude/commands/*.md` — and a `/plugins/<p>/commands/` substring anchor would still have matched the marketplace cache clone under `~/.claude/plugins/marketplaces/`. Its suite 9 → 22 assertions, red-first (the four negative cases were confirmed red against the unanchored pattern).
- Manifest/changelog load failures in the version gate are reported as a ✗ naming the file, and the run continues — that block precedes every fixture check and the hook now fires it on manifest edits, so an uncaught `SyntaxError` would have dropped the summary and ~120 later checks without saying which of the nine `plugin.json` files broke. Entry manifests are resolved through each entry's own `source`.
- The four bash suites now create their scratch dir with a templated `mktemp -d "${TMPDIR%/}/<name>.XXXXXX"`. Template-less `mktemp -d` on macOS ignores `$TMPDIR` and lands in `/var/folders/…/T/`, which the Claude Code sandbox denies — every suite exited 1 before its first assertion, a false red on exactly the path (agent-run pre-commit verification) where the exit code is the verdict. No assertion changed.
- `.claude/settings.json` now lists the local hook's whole executed closure in `sandbox.filesystem.denyWrite` (`scripts`, `plugins/*/tests`, `plugins/*/hooks`, `plugins/*/validators`, plus the two validators that live under `skills/`). The hook runs *outside* the agent's Bash sandbox with the developer's privileges, and everything it runs was writable from *inside* it — an auto-approved sandboxed write could be traded for unsandboxed execution. Flagged (as pre-existing, not introduced) by the security review of the registration gate; the user-level config already applies the same rule to `~/.claude/scripts`. Edits to those files now go through the Edit/Write tools and their permission gate. Verified by probing: literal, glob and deep entries all deny (including creating a new file), control paths (README, SKILL.md, CHANGELOG) stay writable, and every suite still passes since they write only under `$TMPDIR`. Known cost, measured: git is a sandboxed process too, so a `pull` / `merge` / `checkout` / `stash pop` that must rewrite one of those files fails midway (`unable to unlink old …: Operation not permitted`) with the working tree untouched but the index already updated — run such operations outside the sandbox; recovery is `git reset HEAD -- <path>`. Machine-checked the same day: the runner's last check collects every file the hook ends up executing — the script named by each command hook in settings, the runner itself, each validator the runner *actually spawned* (recorded at the two spawn sites rather than scraped from its own source), and the suites and hook scripts under `plugins/*/{tests,hooks}` enumerated the way the hook enumerates them (by name, following symlinks) — and requires each to be covered by a `denyWrite` entry. Everything it cannot verify fails closed instead of being guessed at: only root-relative literals and single-segment `*` are understood as patterns; only `node "$CLAUDE_PROJECT_DIR/<path>"` is understood as a hook command (an independent adversarial review showed the first draft, which scraped script-looking tokens and dropped the ones that did not exist, going green on a command chained with `&& node …/typo-missing.cjs` — and a path that does not exist *yet* is the worst case here, not a harmless one); a symlinked plugin dir, `tests/` dir or suite is reported, since the hook would follow it. Suite 146 → 167 (20 canaries + 1 live check), red-first throughout; mutation-verified against altered *copies* of the settings, so the live protection was never loosened. The hook now also fires on `.claude/settings.json` (its suite 22 → 23). **What a green does not mean**, established by reading the sandbox runtime's rule generator in the 2.1.274 binary: (1) it checks the config, not enforcement — CI has no sandbox; (2) on Linux/WSL the runtime *drops every glob write pattern*, so the three `plugins/*/…` entries protect nothing there; (3) a glob entry denies only paths matching its regex, so renaming a directory that already contains `tests/` *into* `plugins/` is not denied, and a plugin dir protected only by globs can itself be renamed away — read from the generated rules, **not executed** (the in-sandbox probe was refused by the permission classifier twice). A literal entry has none of these holes. Resolved the same day — see the next entry.
- `sandbox.filesystem.denyWrite` is now two literal paths — `scripts`, `plugins` — and the gate rejects any entry containing `*`. The switch was forced by a probe, not a hunch: with the star-globs in force, `mv <dir-already-containing-tests/> plugins/zzp` **succeeded** from inside the sandbox (a rename is checked only on its destination path, which no three-segment regex matched; the subtree came along unchecked). After the change the identical `mv` fails with `Operation not permitted`, as do creating a symlink under `plugins/`, writing `plugins/<p>/README.md` / `plugin.json` / `SKILL.md`. Writing `.git/hooks/pre-commit` is also denied, but that is the runtime's own mandatory rule (`**/.git/hooks/**`, plus `.git/config`), not this entry — a `.git/hooks` entry was briefly included and removed after the security review pointed out it was redundant and that "the probe was denied" did not demonstrate it did anything. Root files (`README.md`, `CHANGELOG.md`, `marketplace.json`) stay writable. Literals also survive Linux/WSL, where the runtime drops every glob write pattern. Red-first: the tightened gate went red against the old settings (three globs rejected, 12 files reported uncovered) before the settings changed; a copy-based mutation putting the globs back is red. Suite unchanged at 167. Cost, accepted: every file under `plugins/` is Edit/Write-only from the agent, sandboxed git that must rewrite anything under `scripts/` or `plugins/` fails midway (CONTRIBUTING §6.5 has the recovery), and mutation checks on manifests use `$TMPDIR` copies.

## [1.10.7] - 2026-09-14

### Changed

- **openspec-superpowers-workflow 1.4.2 → 1.5.0** — `review-notes.md` is seeded with a semantics header (entry format, tag set, "Y = an OpenSpec artifact must change in Phase 6, never 'handled'") instead of being created empty; Phase 5 must decline an explicit "edit the spec now" request out loud rather than silently rerouting it; `[CODE] Y` declared non-existent and `[CONSTITUTION]` restricted to new cross-feature rules; the fix-landing-point rule lifted into SKILL.md rule 1. Driven by 62 real archived changes (54 `[CODE] Y` entries, 30 after the 1.3.1 rule) and a local eval suite that reproduced both failures on 1.4.2 (misleading-header case 3/3 with the plugin loaded; silent-reroute 1/3).

### Notes

- Marketplace patch bump 1.10.6 → 1.10.7.

## [1.10.6] - 2026-09-02

### Fixed

- **code-audit-rigor 2.0.0 → 2.0.1** — `/review-branch` scope now includes the working tree. The pre-flight list was the committed `merge-base...HEAD` diff only, so a pre-commit self-review silently skipped the latest uncommitted work while the coverage table stayed green (the table is only as complete as the mechanical list feeding it). Scope is now committed diff ∪ `git diff --name-only HEAD` ∪ untracked, `--focus` applying to all three; deleted files stay reviewed rather than auto-skipped; each scoped file records a required `source` (`committed` / `working-tree` / `untracked` — the validator rejects a missing value, the schema↔validator consistency gate pins the enum). The skill's Phase 1 is aligned to the same three sources. Suite 125 → 130 checks, red-first verified.

## [1.10.5] - 2026-08-13

### Changed

- **openspec-superpowers-workflow 1.4.1 → 1.4.2** — batch window survives non-BSD `stat`. The BSD-first `stat -f %m` "succeeds" with non-numeric output on GNU/uutils (Ubuntu CI; nix devshells shadowing `stat` on macOS), skipping the fallback and crashing the arithmetic under `set -u` (expansion errors bypass the ERR trap) — hook exited 1, harness allowed the edit, batch window effectively dead on those machines. Caught by CI red + the first live end-to-end test within the hour. Now `-c %Y` first, `-f %m` fallback, digits-only whitelist on both operands; non-numeric degrades to allow. Suite grows to 24 assertions with fake-stat cases pinning both directions.

### Notes

- Marketplace patch bump 1.10.4 → 1.10.5.

## [1.10.4] - 2026-08-13

### Changed

- **openspec-superpowers-workflow 1.4.0 → 1.4.1** — frontmatter made strict-YAML valid (description scalar double-quoted; the unquoted colon+space in "touches none of: public API" had failed `claude plugin validate --strict` since 1.3.0 while the lenient runtime loaded it fine). Quoting proven safe by live precedent (superpowers' brainstorming ships quoted and renders unquoted); `--strict` now passes with content byte-identical.

### Notes

- Marketplace patch bump 1.10.3 → 1.10.4.
- Repo infra: the local PostToolUse gate (`scripts/hooks/validate-on-plugin-edit.cjs`) now also triggers on `hooks/` edits and runs every `plugins/*/tests/*.test.sh` bash suite in addition to the node runner — previously bash hook logic was machine-gated only in CI, so a broken hook script surfaced at push instead of at edit time. Own 9-assertion suite (`scripts/hooks/validate-on-plugin-edit.test.sh`) wired into CI.

## [1.10.3] - 2026-08-13

### Changed

- **openspec-superpowers-workflow 1.3.1 → 1.4.0** — skip-gate PreToolUse hook + proceduralized SKIP clause. A real session bypassed the six-phase workflow by judging "no contract surfaces" from a one-line CLAUDE.md summary — the change in fact touched cross-module behavior spelled out in the canonical spec, in an already-spec'd capability domain. Root cause: SKIP is an *implicit* decision (achieved by not acting), so nothing ever forces the eight-surface check to happen. The plugin now ships a PreToolUse hook that, in an openspec project with no active change, denies the session's first code edit and demands explicit per-surface verdicts before retry, with a 5-second batch window so sibling edits from the same parallel batch stay behind the gate (fail-open on every error path; `openspec/`/`.claude/` and out-of-project paths exempt; 20-assertion suite wired into CI, key protections mutation-verified). The SKIP clause itself now declares an unstated skip a workflow violation and adds the "behavior lands in a capability domain already covered by `openspec/specs/`" signal — a checkable environment fact that outranks free-form judgment.

### Notes

- Marketplace patch bump 1.10.2 → 1.10.3.

## [1.10.2] - 2026-08-08

### Changed

- **openspec-superpowers-workflow 1.3.0 → 1.3.1** — review-notes tagging criterion made explicit: tag by the artifact the fix lands in, not by the nature of the problem. A design decision that contradicts a spec scenario's literal wording is `[REQUIREMENT]` (the spec is the file that must change) — the C1 gate routes strictly by tag and forbids `[DESIGN]` from touching `specs/`. Stated in `phases.md` at the tag-writing site, plus a C1 修正路徑 paragraph standardizing re-tag-with-note when a mis-tag is caught at reconcile (the dangerous alternative — honoring the mis-tag by skipping the spec edit — archives spec-vs-implementation divergence into `openspec/specs/` as permanent wrong truth). Surfaced by two real re-tags in a production Phase 6 run.

### Notes

- Marketplace patch bump 1.10.1 → 1.10.2.

## [1.10.1] - 2026-08-03

### Changed

- **session-learning 1.0.0 → 1.0.1** — save-session reminder hardening, porting the fixes session-reflect shipped with in 1.10.0. The "already ran /save-session" grep was matching any *mention* of the string (discussion, CLAUDE.md injection, Read output of the plugin's own files — one real session showed 62 hits with zero executions), permanently suppressing the reminder; the pattern now matches only real execution shapes (`<command-name>/save-session</command-name>`, namespaced variant, and the `"skill":"session-learning:save-session"` invocation form — all verified against real transcripts). Also removed the no-op `matcher` field from the Stop hook entry and added an 11-assertion fixture suite (`tests/reminder.test.sh`) wired into CI. Surfaced by the session-reflect plugin's own review flow on its first (manual) run.

### Notes

- Marketplace patch bump 1.10.0 → 1.10.1.

## [1.10.0] - 2026-08-03

### Added

- **session-reflect 1.0.0** (new plugin) — session-end reflective review. A fail-open bash Stop-hook gate (loop guard via `stop_hook_active`, once-per-session flag file, <10-line substantiveness floor, mid-interaction detection that yields without consuming the session's single trigger) hands off to a two-stage skill: quick triage (routine sessions exit with a one-line "nothing to review"), then a four-lens sweep (out-of-scope findings / pre-existing issues / adjacent optimizations / knowledge gaps). Candidates must survive a verification layer before the user ever sees them: an inline four-filter self-review (anchor actually Read, existing safeguards, deliberate design, observable value) plus one adversarial verifier subagent (main-loop model, never downgraded) framed to refute, not confirm. Up to 5 survivors are offered via a multi-select prompt — chosen ones execute in-session, unchosen ones land in `.claude/reflect-backlog.md` (`[rejected]` entries are kept forever as dedup evidence; the plugin never commits the backlog). Gate covered by 18 fixture assertions wired into CI (`tests/gate.test.sh`). Design: `docs/session-reflect-design-2026-08-03.md`.

### Notes

- Marketplace minor bump 1.9.1 → 1.10.0 (new plugin).

## [1.9.1] - 2026-07-26

### Changed

- **openspec-superpowers-workflow 1.2.2 → 1.3.0** — SKIP clause sharpened from "small bug fixes with no spec impact" to an explicit contract-risk rubric (public API / data contract / schema / migration / backward compatibility / security boundaries / concurrency / cross-module behavior; judge by contract risk, not LOC or file count). Placed in the skill description because that is where the auto-trigger skip decision is made — self-contained for every installer. `PHASE-IDENTIFICATION.md` and the root README synced to the same language.

## [1.9.0] - 2026-07-26

### Changed

- **code-audit-rigor 1.5.0 → 2.0.0** (BREAKING) — `/audit-review-fix` and its whole implementation (workflow script, command, schema, validator, 14 fixtures) retired. It overlapped with the `claude-security` plugin's *suggest-patches* job, which carries a strictly better risk model: patch files you review and apply yourself, versus ~86 sub-agents (~400k tokens) rewriting source in place. `/review-branch`, `/review-pr`, and the rigor skill are retained — they judge by correctness, which the exploitability-focused security tools do not cover. `scripts/validate-fixtures.cjs` updated accordingly; suite green at 125 passed, 0 failed. See that plugin's CHANGELOG [2.0.0] for the migration path.

## [1.8.11] - 2026-07-02

### Changed

- **security-audit 1.0.0 → 1.0.1** — added local drift protection for the vendored validator: a `valid-basic.json` fixture (confirmed + rejected findings) plus single-field mutations wired into `scripts/validate-fixtures.cjs`, so the repo-root suite + CI + PostToolUse hook now guard `validate-findings.cjs` (including its two semantic constraints: trace must start `entrypoint`, end `sink`). Re-vendor drift check recorded: pinned `4de1ac8` vs upstream HEAD `f75f9a0` is a pure directory move, zero content drift. No vendored file was modified.
- **openspec-superpowers-workflow 1.2.1 → 1.2.2** — Phase 1 pre-check path unified to `${CLAUDE_PLUGIN_ROOT}` (was a repo-relative path with a prose "resolve from install root" note), matching the convention used across the other plugins' skills/commands.

### Notes
- Also (non-plugin): added a `security-audit` entry to the personal `~/.claude/CLAUDE.md` plugin-decision tree (active vulnerability hunting → `/security-audit`; diff/PR governance → `code-audit-rigor`), and closed the two dangling Tier-3 judgment calls in `docs/loop-design-review-2026-07-01.md` with explicit won't-do dispositions + re-open triggers. Marketplace patch bump 1.8.10 → 1.8.11.

## [1.8.10] - 2026-07-01

### Changed

- **high-precision-dev 1.4.0 → 1.5.0** — cross-family model assignment to break the shared-base-model correlation floor: `implementer-a`/`adversary`/`verifier` on `opus`, `implementer-b`/`critic`/`disproof-agent` on `sonnet`, so builders and checkers span two model families. The `model` frontmatter is family-level (pairs Opus 4.8 × Sonnet 5; specific past versions not selectable, same-family pairings barely decorrelate); per-agent effort is not frontmatter-configurable and follows the session `/effort`.

### Notes
- Marketplace patch bump 1.8.9 → 1.8.10.

## [1.8.9] - 2026-07-01

### Changed

- **high-precision-dev 1.3.0 → 1.4.0** — honest `p→p⁴` reframe + implementer decorrelation. The multiplicative `p⁴` claim was demoted everywhere it appeared (`plugin.json` / `marketplace.json` / `README` / `start.md` / `ANTI-PATTERNS.md`) from a headline guarantee to an idealized model with an explicit shared-model-correlation-floor caveat (two identically-prompted instances of one base model make correlated errors on systematic misreadings). `implementer-a` and `implementer-b`, previously byte-identical, were given genuinely different approaches (A spec-first / top-down, B test-first / behavior-driven; same completeness bar, different path) so the weakest independence leg actually decorrelates.

### Notes
- Marketplace patch bump 1.8.8 → 1.8.9.

## [1.8.8] - 2026-07-01

### Added

- **high-precision-dev 1.2.1 → 1.3.0** — controller-run environmental test gate before Phase 4 completion. After the verifier merges, the controller itself runs the SPEC test suite and captures the exit code (`WF_TEST_EXIT=$?`), promoting "tests pass" from an agent prose claim to an environmental fact wired into the existing capped fix-loop's exit condition. Deliberately does NOT reintroduce a structured-output contract — it is the one machine gate that satisfies the meta-rule *a gate is justified iff (a) it reads an environmental fact, not an agent assertion, and (b) a downstream consumer acts on it.*

### Notes
- Marketplace patch bump 1.8.7 → 1.8.8.

## [1.8.7] - 2026-07-01

### Changed

- **code-audit-rigor 1.4.0 → 1.5.0** — `/review-branch` gained `--focus <pathspec>` and a Phase 2 confidence field (0-100, <67% flagged borderline); `/review-pr` Phase 3 regression check hardened to the baseline + exit-code-sentinel discipline already audited in `/audit-review-fix` (capture pre-fix baseline, count new-vs-preexisting failures, trust `WF_TEST_EXIT=0`, a build newly broken counts as regression, unparseable → fail closed).
- **openspec-superpowers-workflow 1.2.0 → 1.2.1** — Phase 1 gained an optional lenient local pre-check that runs the bundled `.cjs` before the authoritative `openspec validate --strict` (surfaces the plugin's own CI-only validator in the live workflow).
- **high-precision-dev 1.2.0 → 1.2.1** — removed the never-implemented `--phase N` arg hint from `start.md`; investigated the `disproof-agent` non-registration and confirmed it was not a defect (identical frontmatter to registering siblings; an under-versioned-PR-#4 reload artifact resolved by the 1.2.0 bump + reload).

### Notes
- Follow-on items from the loop-design review. Marketplace patch bump 1.8.6 → 1.8.7.

## [1.8.6] - 2026-07-01

### Changed

- **Selective L2 consolidation** (from `docs/loop-design-review-2026-07-01.md`) — the PR #4 uniform "schema + validator on all four plugins" was reduced to only where a machine consumer actually reads the contract, rather than reverted wholesale (a full revert would also have discarded code-audit-rigor's *working* live validators, CI, hook, and STEEL_MANNING).
  - **multi-agent-debate 1.1.0 → 1.2.0** — completed L2: `/debate` Phase 6 now emits `debate-output.json` and runs `validate-debate-output.cjs` as a live structural gate; added cross-field referential integrity (`selectedProposal`/`agreedProposals` must point at real `proposals[].id`) and a required, machine-checked `coverage` field; reconciled Phase 4 convergence criteria (≥8 score gap) with `orchestrator.md`.
  - **high-precision-dev 1.1.0 → 1.2.0** — removed dead L2: all six agents emit prose reports, so the schema validated a JSON shape nothing produces. Deleted `schema/`, validators, fixtures + runner wiring; cleaned dangling refs in `README`/`start.md`.
- Removed a stray `t.json` (a prior-debate test artifact committed to repo root in PR #4).

### Notes
- Suite went 148 → 133 checks (−21 removed high-precision checks, +6 new debate mutations). Marketplace patch bump 1.8.5 → 1.8.6.

## [1.8.5] - 2026-07-01

### Fixed

- **Backfilled version bumps + changelogs for PR #4** (commit `893821c`), which had landed a uniform "structured output + zero-dependency validator + fixtures + CI + PostToolUse hook" L2 layer across four plugins **without** any version bump — leaving each `plugin.json` at its pre-merge number both before and after a functional change, and two plugins with no `CHANGELOG.md` at all. This ambiguity is exactly what breaks registry version-caching (new agents/capabilities silently not loading).
  - **code-audit-rigor 1.3.4 → 1.4.0**, **openspec-superpowers-workflow 1.1.0 → 1.2.0** — version + changelog backfilled for the L2 change.
  - **multi-agent-debate 1.0.0 → 1.1.0**, **high-precision-dev 1.0.0 → 1.1.0** — `CHANGELOG.md` created (backfilled 1.0.0 initial-release + the 1.1.0 L2 change).

### Notes
- No functional code changes in this release — version/changelog hygiene only. Marketplace 1.8.4 → 1.8.5.

## [1.8.4] - 2026-06-29

### Fixed

- **code-audit-rigor 1.3.3 → 1.3.4** — `/audit-review-fix` Verify-Fix no longer reports a build that is broken at *both* baseline and verify as `testsPass`/`READY_FOR_COMMIT` (the run-2 review's "2b" residual). A new orthogonal `currentlyBroken` check (`errored` + explicit non-zero exit) fails closed regardless of baseline — committing a non-building tree is never OK. Requires an explicit non-zero exit so a passing run containing "error" text is not false-failed; assertion-only dirty baselines are unaffected. Unit harness now 76 assertions.

### Notes
- Marketplace patch bump 1.8.3 → 1.8.4.

## [1.8.3] - 2026-06-29

### Fixed

- **code-audit-rigor 1.3.2 → 1.3.3** — remaining LOW/NOTE robustness items from the run-2 self-audit of the `/audit-review-fix` workflow (unit harness now 71 assertions):
  - `status` no longer reports a lone `DEFER_OUT_OF_SCOPE` finding as `CLEAN` — new `REQUIRES_FOLLOW_UP` status (docs updated).
  - Fix agents that edit then return `applied=false` now surface the untested files left in the tree (no longer silently "declined").
  - `today` is path-sanitised before building the report path (no `../` traversal).
  - Scope-abort hardened: real-diff guard on the "no changes" check, and a bad `--focus` pathspec now aborts loudly instead of silently reviewing an empty diff.
  - Fix-agent prompt hardened against indirect prompt injection (treat diff/finding text as data).
  - EV 67% breakeven reviewed and intentionally left unchanged (faithful to the skill's documented Framework 2).

### Notes
- Marketplace patch bump 1.8.2 → 1.8.3.

## [1.8.2] - 2026-06-29

### Fixed

- **code-audit-rigor 1.3.1 → 1.3.2** — three safety-gate fixes in the `/audit-review-fix` workflow (fail-open → fail-closed), found by a self `security-audit` run (run-2) and adversarially reviewed, covered by a 56-assertion unit harness:
  - (HIGH) Verify-Fix reported `testsPass=true` for compile/collection/fatal "build broke" states (no `failed`/`FAIL ` token) → an unbuildable tree was reported `READY_FOR_COMMIT`. Now detects error/no-run states + an exit-code sentinel and fails closed.
  - (MEDIUM) A clean baseline disabled the count-regression backstop (`baselineFailCount=null`); now coerced to `0`.
  - (MEDIUM) Non-numeric/non-object args coerced to NaN or reverted safety flags → silent dropped findings / no review / no LOC cap / false `CLEAN`; now validated with finiteness/object-shape guards.

### Notes
- Marketplace patch bump 1.8.1 → 1.8.2 (one plugin patch release).

## [1.8.1] - 2026-06-29

### Security

- **codegraph 1.0.0 → 1.0.1** — fixed the prerequisite npm package name from the unowned unscoped `codegraph` (a third-party 469-byte placeholder with no `bin`) to the real scoped `@colbymchenry/codegraph`. Removes a dependency-confusion exposure and a functional break (the bundled MCP server never started for anyone who followed the docs). Found by a `security-audit` run; confirmed against the maintainer's working install.
- **code-audit-rigor 1.3.0 → 1.3.1** — `/review-pr` now labels fetched PR comments (anyone can post on a public PR) as untrusted data to analyze, not instructions to execute, and requires a diff review before the Phase 4 commit/push. Defense-in-depth (`security-audit` Finding 2, LOW).

### Fixed

- Aligned `repository`/`homepage` in `multi-agent-debate` (was the non-existent `chinlung/multi-agent-debate`) and added them to `session-learning`, both now pointing at `chinlung/claude-dev-workflow`. Metadata-only; plugin versions unchanged.
- Added a root `.gitignore` (`node_modules/`, `.env*`, `*.pem`/`*.key`, `*.local.md`, `*.log`, OS junk) to guard contributors/forkers against committing local config or secrets.

### Notes
- Marketplace patch bump 1.8.0 → 1.8.1 (two plugin patch releases + repo hygiene).

## [1.8.0] - 2026-06-29

### Added
- **New plugin: security-audit 1.0.0**. Vendored the `security-audit` skill from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT, © Cloudflare, Inc.) at upstream commit `4de1ac8`. A six-phase multi-agent pipeline (recon → hunt → validate → report → structured output → independent verification) that actively hunts exploitable vulnerabilities with real impact, complementing `code-audit-rigor`'s review-discipline frameworks. Vendored files are copied verbatim; the wrapper adds only `plugin.json` + `README.md`, which document the Claude Code platform mapping (research → `Explore`, general → `general-purpose`) and the upstream-sync procedure (see CONTRIBUTING §7).

### Notes
- Marketplace minor bump 1.7.5 → 1.8.0 (new plugin added).

## [1.7.5] - 2026-06-24

### Added
- **code-audit-rigor 1.2.1 → 1.3.0**: Added `/audit-review-fix`, an automated adversarial batch audit-and-fix Workflow folded in as the plugin's third layer (migrated from user-level `~/.claude/`, same portability pattern as the 1.2.0 command migration). The command reads its script via `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js` (no hardcoded home path): 9-angle review + EV triage + safety-gated auto-fix + test verification + report. The "auto-fix-free" positioning is now scoped to the rigor skill only — auto-fix is provided solely by `/audit-review-fix` under safety gates and adversarial verification.

### Notes
- Marketplace patch bump 1.7.4 → 1.7.5.

## [1.7.4] - 2026-06-17

### Changed
- **openspec-superpowers-workflow 1.0.1 → 1.1.0**: Aligned Phase 4 with superpowers v6.0.0, which rewrote subagent-driven-development's per-task review. The two-stage review (separate spec + quality reviewers) became a single `task-reviewer` returning both verdicts at once, plus one end-of-branch whole-branch review using the strongest model. Documented the v6 worktree relocation: the global `~/.config/superpowers/worktrees/` was removed in favor of an in-project `.worktrees/` root (must be git-ignored). Added a reviewer-integrity rule (no suppressing findings, no defaulting severity) and a dependency note: superpowers >= 6.0.0.

### Notes
- Marketplace patch bump 1.7.3 → 1.7.4.

## [1.7.3] - 2026-06-08

### Changed
- **code-audit-rigor 1.2.0 → 1.2.1**: Codegraph-aware call-chain tracing. Review sub-agents follow dispatch prompts literally, and those prompts hardcoded "use Grep" — so codegraph indexes were never used even when present, missing dynamic-dispatch call sites. `/review-branch` Phase 2 and `SKILL.md` Principle 3 now prefer `codegraph_callers`/`codegraph_impact` when `.codegraph/` exists, with Grep fallback. Quoted-code anchoring deliberately stays on Grep (literal string matching, not structural). No hard dependency — graceful degradation without codegraph.

### Notes
- Marketplace patch bump 1.7.2 → 1.7.3.

## [1.7.2] - 2026-06-08

### Changed
- **code-audit-rigor 1.1.0 → 1.2.0**: Migrated `/review-branch` and `/review-pr` from user-level `~/.claude/commands/` into the plugin. Motivation: `/review-branch`'s built-in rules layer previously fell back to a hardcoded absolute path that only resolved on one machine; inside the plugin it now uses `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json`, which is machine-independent and ships with every install. Plugin scope widened to "review & audit toolkit" (routine commands + rigor skill sharing the same rule packs).

### Notes
- Marketplace patch bump 1.7.1 → 1.7.2.

## [1.7.1] - 2026-06-07

### Changed
- **code-audit-rigor 1.0.1 → 1.1.0**: Added three deterministic engineering guarantees adapted from [alibaba/open-code-review](https://github.com/alibaba/open-code-review)'s "deterministic engineering + LLM" hybrid design (Apache-2.0). Gap analysis: the skill was strong on depth rigor (EV math, steel-manning, STRIDE+CWE) but coverage, rule specificity, and reference accuracy relied on LLM self-discipline — exactly the three things OCR solves with engineering.
  - **Phase 1b path-matched rule packs**: new `rules/manifest.json` (glob → doc, first-match) + 8 `rule_docs/*.md` (TS/JS/React, PHP/Laravel, Python, Go, SQL/mapper, YAML/IaC/Dockerfile, package.json, default), each with a Review-focus hunt list and a file-type-scoped "Do NOT report" suppression list. Layered overrides: project `.reviewrules/` → user `~/.claude/review-rules/` → plugin built-in.
  - **Mechanical scope + coverage reconciliation**: Phase 1 scope must come from `git diff --name-only` / `git show` / Glob output; Phase 5 reconciles every scope file into Read or Skipped with a mandatory `Unaccounted` row that invalidates the audit if non-empty.
  - **Quoted-code reference anchoring**: Framework 4 crossReferences now require a verbatim `quotedCode` field; Phase 4 Step 1 greps it mechanically before steel-manning (found at claimed lines ±10 → anchored; elsewhere → re-locate; absent → `UNVERIFIED_REFERENCE`, confidence −30).
  - Deliberate exclusions documented: no three-zone memory compression (harness compacts natively); suppression lists are file-type-scoped, not the global hard-exclusion lists the skill rejects.

### Notes
- Marketplace patch bump 1.7.0 → 1.7.1 reflects the existing-plugin content change.

## [1.7.0] - 2026-05-30

### Added
- **CodeGraph Plugin** (1.0.0): Single-skill plugin teaching structural-code-intelligence-before-grep discipline for projects with a `.codegraph/` index.
  - **Bundled MCP server** (`.mcp.json` → `codegraph serve --mcp`): install once and the MCP tools are available in every project — a new project then needs only `codegraph init -i`, no per-project `codegraph install` or `.mcp.json`. Plugin-provided tools are prefixed `mcp__plugin_codegraph_codegraph__<tool>`; requires the `codegraph` CLI on `PATH` globally.
  - **Entry-point split**: documents the non-obvious fact that `codegraph serve --mcp` exposes only `trace`/`node`/`explore`/`search`/`context` as `codegraph_*` MCP tools, while `impact`/`callers`/`callees`/`affected`/`status`/`files` are Bash-CLI only (verified on codegraph 0.9.7). Neither surface is a superset — calling `codegraph_impact` as an MCP tool fails.
  - **Proactive triggers** tied to actions (edit/rename/remove → `impact`; change a method → `callers`/`node`; unfamiliar code → `context`; flow → `trace`) rather than only phrased questions.
  - **Reliability fallback**: when a capability isn't an MCP tool, use the CLI — never silently degrade to a half-grep that misses dynamic-dispatch call sites.
  - Progressive-disclosure `reference.md`: 4-step new-project setup, read-only `settings.json` allowlist, and known gotchas (tool-managed `CODEGRAPH_START/END` block overwrites on re-sync, that block's table over-promising CLI commands as MCP tools, `daemon.pid` absent from the default gitignore).

### Notes
- Marketplace minor bump 1.6.1 → 1.7.0 for the new plugin.

## [1.6.1] - 2026-05-09

### Changed
- **code-audit-rigor 1.0.0 → 1.0.1**: Add Phase 5b zero-findings handling guidance to `SKILL.md`. Surfaced during first real-world test on `bin/tg-fallback-send.sh` where 8 candidates → 0 confirmed exposed the absence of explicit instructions for clean-audit reports. New Phase 5b mandates: (1) full report production even with zero confirmed findings, (2) executive-summary phrasing that explicitly states the negative result as valuable, (3) dismissed-findings body with original-vs-re-evaluated confidence and steel-manning rationale, (4) total dismissed prior score sanity check, (5) encouraged skill self-evaluation paragraph. Added explicit "save to disk" requirement to Phase 5 (no chat-only output for audits) and one new anti-pattern.

### Notes
- Marketplace patch bump 1.6.0 → 1.6.1 reflects the SKILL.md content change. Users on 1.6.0 still have the four quantitative frameworks but lack guidance on the most common outcome (zero confirmed findings) — they should update.

## [1.6.0] - 2026-05-09

### Added
- **Code Audit Rigor Plugin**: Single-skill plugin providing quantitative review discipline for high-stakes audits where intuition is insufficient (security-critical, crypto, payment, IaC, untrusted-input parsers).
  - **Five core review-discipline principles**: (1) Read first / score later, (2) "Have I actually read this, or am I guessing?" self-check, (3) Verify the source (not the diff), (4) Multi-agent consensus is not verification, (5) Wrongful dismissal costs 2× the score
  - **Four quantitative frameworks**:
    1. Score-based calibration (+10 / +5 / +3 / +1 vs −3 false-positive penalty)
    2. Expected-Value (EV) decision threshold: `EV = confidence% × points − (100 − confidence%) × 2 × points`, ≥67% confidence breakeven
    3. STRIDE + CWE classification with 16-CWE quick-reference table
    4. Mandatory cross-reference contract (every finding includes `file:line` evidence; empty array rejected)
  - **End-to-end audit workflow**: 5 phases (scope, literal pass, findings draft, adversarial sweep, aggregate report) with explicit Phase 4 corrective steel-manning to defuse multi-agent false-confidence amplification
  - **Self-contained**: All rules and reference tables ship in `SKILL.md`; works on any machine without depending on host project's CLAUDE.md
  - **Inspired by** `codexstar69/bug-hunter` adversarial Hunter / Skeptic / Referee flow, but **deliberately excludes** auto-fix with canary rollout (too aggressive for production code), hard-exclusion lists for "settled false-positive classes" (creates blind spots), and LLM-readable instruction files outside `SKILL.md` (minimizes prompt-injection surface area)
- Updated marketplace version to 1.6.0

## [1.5.1] - 2026-04-10

### Changed
- **openspec-superpowers-workflow 1.0.0 → 1.0.1**: Strengthen auto-trigger. Rewrite `SKILL.md` frontmatter `description` with imperative "MUST use" wording, expanded trigger list (now matches `openspec` CLI commands and the presence of `openspec/changes/<name>/` folders), and explicit forbidden-behaviour enumeration. Add "Activation reminder" note at the top of `SKILL.md` body anchoring non-negotiable rules before any action. Removes the need for users to maintain a separate "must call this skill" reminder in their own `~/.claude/CLAUDE.md` — the same meta-instruction now ships with the plugin. `phases.md` unchanged.

### Fixed
- **dev-workflow 1.0.1 → 1.0.2**: Correct `plugin.json` description from "6 specialized agents" to "7 specialized agents: ..., quality assurance, and documentation". The mismatch was a leftover from the 2026-03-12 `35c0a9c` refactor commit that reverted the version string to match `CHANGELOG [1.0.1]` but also reverted the description text to the 1.0.0-era wording, even though the `documentation-specialist` agent file was never removed. No behavioural or file changes — metadata fix only.

### Documentation
- `README.md` / `README.zh-TW.md`: Add `Session Learning Plugin` table row, install command, and full plugin section (previously missing despite shipping since 1.4.0).
- `CHANGELOG.zh-TW.md`: Translate `[1.5.0]` and `[1.4.0]` entries from the English changelog (Chinese changelog previously stopped at `[1.3.0]`).
- `marketplace.json`: Bump `dev-workflow` entry version to `1.0.1` then `1.0.2` to match `plugins/dev-workflow/plugin.json` (leftover drift from the earlier version-alignment refactor).

### Notes
- Marketplace version bump from 1.5.0 → 1.5.1 reflects that `HEAD` contains multiple plugin-content changes beyond the initial 1.5.0 commit. Users on 1.5.0 who do not update will miss the stronger auto-trigger and the dev-workflow description fix.

## [1.5.0] - 2026-04-10

### Added
- **OpenSpec + Superpowers Workflow Plugin**: Six-phase feature development workflow enforcing strict role separation between OpenSpec (spec lifecycle, WHAT) and Superpowers (dev discipline, HOW)
  - Single skill with progressive disclosure: `SKILL.md` (58 lines, always loaded) + `phases.md` (290+ lines, loaded on demand)
  - **Phase 1 — Spec Definition** (OpenSpec leads): propose + specs as user-reviewed artifacts; design/tasks as placeholder drafts
  - **Phase 2 — Design Refinement** (Superpowers `brainstorming` → overwrites `design.md` in place)
  - **Phase 3 — Task Planning** (Superpowers `writing-plans` → overwrites `tasks.md` in place)
  - **Phase 4 — Implementation** (Superpowers `subagent-driven-development` + mandatory TDD)
  - **Phase 5 — Review & Feedback**: `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag taxonomy with Y/N classification, recorded in `review-notes.md`; spec files are never modified during review
  - **Phase 6 — Reconcile & Archive** (OpenSpec): clean-rewrite discipline (not incremental patches), `tasks.md` frozen as execution history, `[CONSTITUTION]` items routed to `openspec/config.yaml` instead of feature spec
  - Prerequisites section documenting OpenSpec CLI vs `/opsx:*` slash-command alternatives and the `openspec init .` (no `--here` flag) gotcha
  - Validator strictness gotcha: every `### Requirement:` block must have `SHALL`/`MUST` in the first paragraph
  - Archive folder date-prefix behaviour: `openspec/changes/archive/<YYYY-MM-DD>-<name>/`
  - Decision quick-reference table (13 situations) and 8-item anti-patterns list
- Updated marketplace version to 1.5.0

## [1.4.0] - 2026-03-12

### Added
- **Session Learning Plugin**: 經驗學習系統，漸進式保存對話模式
  - `/save-session` 命令：分析對話並保存有價值的模式為 memory 或 skill
    - 5 Phase 分析流程：掃描 → 層級判斷 → 去重合併 → 執行 → 報告
    - 自動區分全域 vs 專案層級保存位置
    - 更新優先於新建，避免記憶膨脹
    - 每次最多 1-2 項變更，精簡克制
  - Stop hook：在實質工作階段結束時輕量提醒執行 `/save-session`
    - Command 類型（非 prompt），不觸發額外 LLM 呼叫
    - Flag file 機制防止同一 session 重複提醒
    - 自動跳過短工作階段（< 10 行 transcript）
- Updated marketplace version to 1.4.0

## [1.3.0] - 2026-03-06

### Added
- **High-Precision Dev Plugin**: Multi-agent development mode for safety-critical code
  - `/high-precision-dev:init` command to scaffold SPEC.md and CONSENSUS.md
  - `/high-precision-dev:start` command to run the 4-phase verification workflow
  - 5 specialized agents:
    - Implementer A/B: Independent defensive implementation in isolated worktrees
    - Critic: Systematic bug finding with severity 1-5 scale
    - Adversary: 3-round red team attack (boundary, semantic, assumption)
    - Verifier: Final integration with SPEC.md coverage verification
  - Error rate compression from p to p^4 through epistemic division of labor
  - Phase 3 fix cycle limit (max 3 iterations) with adversary re-attack
  - Verifier Step Zero: checks CRITIQUE.md/ATTACKS.md before integration
  - Three-level intensity spectrum documentation (single agent → /debate → /start)
- Updated marketplace version to 1.1.0
- Updated README with High-Precision Dev plugin documentation (EN + zh-TW)

## [1.2.0] - 2025-12-19

### Added
- **Multi-Agent Debate Plugin**: A dialectical system for multi-perspective decision making
  - `/debate` command for initiating debates
  - 5 specialized agents:
    - Orchestrator: Analyzes requirements and configures perspectives
    - Perspective A/B/C: Proposes solutions from different angles
    - Critic: Reviews proposals and provides quantitative scoring
  - Smart perspective configuration based on requirement type
  - Quantitative scoring system (30-point scale)
  - Consensus-driven decision making (≥2 agents must agree)
  - Iterative refinement through multiple debate rounds
  - User participation at key decision points
- Updated README to document both plugins in the collection
- Traditional Chinese documentation for multi-agent-debate

## [1.1.0] - 2025-12-11

### Added
- **Documentation Specialist** agent (step 7): Handles documentation updates, CHANGELOG maintenance, and PR description generation
- **handoff.md mechanism**: Central state management document for seamless context transfer between agents
- Language agnostic design: works with any programming language
- Traditional Chinese documentation (README.zh-TW.md, CHANGELOG.zh-TW.md)

### Changed
- Generalized all agents to be language/framework agnostic
- Improved Implementation Specialist with better code pattern recognition
- Enhanced Quality Assurance with more comprehensive checks
- Updated Solution Architect with broader technology considerations
- Refined Test Engineer for multi-language test frameworks

### Fixed
- Repository field format in package.json (should be string not object)
- Corrected GitHub repository URL

### Documentation
- Added tutorial video link by Pahud Hsieh
- Added contributor credits
- Renumbered development workflow documents for sequence consistency

## [1.0.0] - 2024-12-11

### Added
- Initial release of dev-workflow plugin
- 6 specialized agents:
  - Issue Analyst: Requirements analysis and user stories
  - Code Archaeologist: Codebase exploration and pattern identification
  - Solution Architect: Architecture design and solution comparison
  - Implementation Specialist: Code implementation following best practices
  - Test Engineer: Test planning and execution
  - Quality Assurance: Code quality verification and build validation
- Main command `/dev-workflow` with support for:
  - Full workflow execution
  - Single step execution (`--step`)
  - Resume from checkpoint (`--resume`)
- Progress tracking with TodoWrite
- Pause point after architecture design for user confirmation
- Comprehensive documentation output in `docs/task-{timestamp}/` directory
