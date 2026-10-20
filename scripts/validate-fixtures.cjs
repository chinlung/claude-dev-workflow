#!/usr/bin/env node
'use strict';

/**
 * validate-fixtures.cjs
 *
 * Zero-dependency repo-root fixture runner.
 * Runs all plugin validators against their test fixtures and reports results.
 *
 * Usage (from repo root):
 *   node scripts/validate-fixtures.cjs
 *
 * Exit codes:
 *   0 — all fixture checks passed
 *   1 — one or more checks failed
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;
let failed = 0;
const failures = [];
// Every script this runner spawns, recorded AT THE SPAWN SITES rather than re-derived by
// scanning this file's source: the denyWrite gate needs what is actually executed, and a
// regex over `P('…')` literals would silently miss a validator path built any other way.
const spawned = new Set();

// ── helpers ───────────────────────────────────────────────────────────────────

/**
 * Run a validator against a fixture and judge whether its exit code matches the
 * expectation; returns `{label, ok, msg}` and leaves printing and scoring to run().
 * Two cases that would otherwise pass an expected-invalid fixture spuriously are
 * failures regardless of expectValid: a missing fixture (the validator exits non-zero
 * simply because it cannot read it) and a validator that could not be executed at all
 * (no exit status — not a rejection). `execFile` is injectable so a canary can produce
 * that second case, which a real node spawn never does.
 */
function runOutcome(validator, fixture, expectValid, execFile = execFileSync) {
  const label = `${path.relative(ROOT, validator)} ← ${path.relative(ROOT, fixture)}`;
  if (!fs.existsSync(validator)) return { label, ok: false, msg: 'validator not found' };
  if (!fs.existsSync(fixture)) return { label, ok: false, msg: 'fixture not found' };
  let exitCode = 0;
  spawned.add(validator);
  try {
    execFile(process.execPath, [validator, fixture], { stdio: 'pipe' });
  } catch (e) {
    if (typeof e.status !== 'number') return { label, ok: false, msg: `validator could not be executed — ${e.message}` };
    exitCode = e.status;
  }
  if (expectValid ? exitCode === 0 : exitCode !== 0) return { label, ok: true };
  const expected = expectValid ? 'exit 0 (VALID)' : 'exit non-zero (INVALID)';
  return { label, ok: false, msg: `expected ${expected}, got exit ${exitCode}` };
}

/** Print and score one `{label, ok, msg}` outcome (from runOutcome / mutationOutcomes). */
function reportOutcome(o, report = expectNoProblems) {
  report(o.label, o.ok ? [] : [o.msg]);
}

function run(validator, fixture, expectValid) {
  reportOutcome(runOutcome(validator, fixture, expectValid));
}

let tmpCounter = 0;

/**
 * Run a validator CLI against an in-memory object via a temp file. Returns `{status,
 * output}`: the exit code (0, or the process's non-zero status) and stdout+stderr, so
 * a mutation can check WHICH rule rejected it (runMutations' optional `expect`).
 * THROWS for spawn/setup failures (write error, validator missing/uncallable) — the
 * caller MUST treat a throw as a harness error, never as a validator rejection (that
 * was the old fail-open). `execFile` is injectable for the same reason as runOutcome's.
 */
function execValidatorCapture(validator, obj, execFile = execFileSync) {
  spawned.add(validator);
  const tmp = path.join(os.tmpdir(), `validate-fixtures-mut-${process.pid}-${tmpCounter++}.json`);
  // Write OUTSIDE the exit-capturing try: a write failure is a harness/environment
  // error, not a validator rejection — it must propagate, never be scored as a pass.
  fs.writeFileSync(tmp, JSON.stringify(obj));
  try {
    const out = execFile(process.execPath, [validator, tmp], { stdio: 'pipe' });
    return { status: 0, output: String(out) };
  } catch (e) {
    // validator ran and exited non-zero
    if (typeof e.status === 'number') return { status: e.status, output: `${e.stdout || ''}${e.stderr || ''}` };
    throw e; // could not even execute the validator
  } finally {
    try { fs.unlinkSync(tmp); } catch (e) { /* ignore cleanup errors */ }
  }
}

/**
 * Generator-based coverage for the required-field / type / enum long tail.
 * Loads a base fixture, checks the validator accepts it, applies exactly one mutation,
 * and asserts the validator rejects it (exit non-zero). Isolation is guaranteed by
 * construction: a valid base plus a single-field change means a non-zero exit can only
 * come from that field's rule — which is why the base is checked here rather than relying
 * on the fixture section's separate `run(base, true)` line, which nothing ties to this
 * call: an invalid base makes every mutation exit non-zero and score as a pass. A
 * validator that cannot be executed (missing / mis-pathed / write failure) is scored as
 * a FAILURE, never a spurious pass.
 *
 * Isolation still assumes the mutation hit the field its label names. A mutation that
 * lands on the wrong record or trips a second rule exits non-zero all the same, so a
 * mutation may carry `expect` (a RegExp the validator's output must match) to pin the
 * rule that rejected it. A mutate() that throws (e.g. a lookup helper reporting fixture
 * drift) is scored as a failure and the run continues.
 *
 * Split in two so the judgement can be tested without touching the global counters:
 * mutationOutcomes() runs everything and returns one `{label, ok, msg}` per result (a
 * group-level failure — validator missing, base unloadable or rejected — is a single
 * entry labelled with the group; a rejected base also sets `baseRefused`), and
 * runMutations() prints and scores them.
 */
function mutationOutcomes(validator, baseFixture, group, mutations, execFile = execFileSync) {
  const rel = path.relative(ROOT, baseFixture);
  const groupFailure = (msg, extra) => [{ label: group, ok: false, msg, ...extra }];
  if (!fs.existsSync(validator)) return groupFailure(`validator not found — ${path.relative(ROOT, validator)}`);
  let base;
  try {
    base = JSON.parse(fs.readFileSync(baseFixture, 'utf8'));
  } catch (e) {
    return groupFailure(`cannot load valid base ${rel} — ${e.message}`);
  }
  let baseExit;
  try {
    baseExit = execValidatorCapture(validator, base, execFile).status;
  } catch (e) {
    return groupFailure(`validator could not be executed on base ${rel} — ${e.message}`);
  }
  if (baseExit !== 0) {
    return groupFailure(`base fixture is not valid (${rel} exit ${baseExit}) — mutations skipped`, { baseRefused: true });
  }
  return mutations.map((m) => {
    const obj = JSON.parse(JSON.stringify(base));
    const label = `${group} ← mutate: ${m.label}`;
    try {
      m.mutate(obj);
    } catch (e) {
      return { label, ok: false, msg: `mutation threw — ${e.message}` };
    }
    let result;
    try {
      result = execValidatorCapture(validator, obj, execFile);
    } catch (e) {
      return { label, ok: false, msg: `validator could not be executed — ${e.message}` };
    }
    if (result.status === 0) return { label, ok: false, msg: 'expected rejection (exit non-zero), got exit 0' };
    if (m.expect && !m.expect.test(result.output)) return { label, ok: false, msg: `rejected, but output does not match ${m.expect}` };
    return { label, ok: true };
  });
}

function runMutations(validator, baseFixture, group, mutations) {
  for (const o of mutationOutcomes(validator, baseFixture, group, mutations)) reportOutcome(o);
}

// ── Schema ↔ validator consistency: structural (set-based) enum/pattern drift ──────

/** Recursively collect enum arrays (with the property name they sit under) and regex
 *  patterns from a schema. The property name lets single-value const enums be checked
 *  field-aware (e.g. `suppressNewFindings !== false`, not just `!== false` anywhere). */
function collectSchemaEnums(node, acc, propName) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node.enum)) acc.enumArrays.push({ values: node.enum, prop: propName || '' });
  if (typeof node.pattern === 'string') acc.patterns.add(node.pattern);
  for (const k of Object.keys(node)) {
    if (k === 'properties' && node.properties && typeof node.properties === 'object') {
      for (const pk of Object.keys(node.properties)) collectSchemaEnums(node.properties[pk], acc, pk);
    } else if (node[k] && typeof node[k] === 'object') {
      collectSchemaEnums(node[k], acc, propName);
    }
  }
}

/** Parse `const NAME_ENUM = ['a', 'b', ...]` arrays from validator source into key-sets. */
function parseValidatorEnumSets(src) {
  const sets = [];
  const re = /_ENUM\s*=\s*\[([^\]]*)\]/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const quoted = m[1].match(/'([^']*)'|"([^"]*)"/g) || [];
    if (quoted.length) sets.push(new Set(quoted.map(s => JSON.stringify(s.slice(1, -1)))));
  }
  return sets;
}

const keySet = (values) => new Set(values.map(v => JSON.stringify(v)));
function setsEqual(a, b) {
  if (a.size !== b.size) return false;
  for (const v of a) if (!b.has(v)) return false;
  return true;
}
/** A single-value const enum (e.g. "1.0", false) is enforced via a strict comparison
 *  on its own property, not a *_ENUM array. Confirm the validator compares THAT property
 *  against THAT literal (field-aware — so `suppressNewFindings !== false` counts but an
 *  unrelated `!== false` elsewhere does not). */
function singleEnumEnforced(prop, rawVal, src) {
  const lit = typeof rawVal === 'string' ? `'${rawVal}'` : String(rawVal);
  const litDq = typeof rawVal === 'string' ? `"${rawVal}"` : String(rawVal);
  if (!prop) { // no property context (e.g. top-level anyOf discriminator) — fall back to literal presence
    return src.includes(lit) || src.includes(litDq);
  }
  return src.includes(`${prop} === ${lit}`) || src.includes(`${prop} !== ${lit}`)
      || src.includes(`${prop} === ${litDq}`) || src.includes(`${prop} !== ${litDq}`);
}

/**
 * Pure drift computation (no scoring) so the self-test canary can exercise it.
 * STRUCTURAL, set-based — NOT substring — so short/common tokens (STRIDE letters,
 * "test", booleans) are checked as strongly as distinctive ones:
 *   1. every multi-value schema enum must equal some validator *_ENUM set; every
 *      single-value const enum must be enforced via a strict comparison;
 *   2. every validator *_ENUM set must be declared as a schema enum;
 *   3. every schema regex pattern must appear literally in the validator.
 * Returns { drift: string[] } or { error: string }.
 */
function computeSchemaDrift(schemaPaths, validatorPath) {
  let src;
  try { src = fs.readFileSync(validatorPath, 'utf8'); }
  catch (e) { return { error: `cannot read validator — ${e.message}` }; }

  const acc = { enumArrays: [], patterns: new Set() };
  for (const sp of schemaPaths) {
    try { collectSchemaEnums(JSON.parse(fs.readFileSync(sp, 'utf8')), acc); }
    catch (e) { return { error: `cannot read schema ${path.relative(ROOT, sp)} — ${e.message}` }; }
  }

  const validatorSets = parseValidatorEnumSets(src);
  const schemaSets = acc.enumArrays.map(e => keySet(e.values));
  const drift = [];

  // 1. schema → validator
  for (const { values, prop } of acc.enumArrays) {
    const ks = keySet(values);
    if (ks.size >= 2) {
      if (!validatorSets.some(v => setsEqual(v, ks))) {
        drift.push(`schema enum [${values.map(String).join(', ')}] has no matching *_ENUM set in the validator`);
      }
    } else if (ks.size === 1) {
      const raw = values[0];
      const k = JSON.stringify(raw);
      if (!validatorSets.some(v => v.has(k)) && !singleEnumEnforced(prop, raw, src)) {
        drift.push(`schema const enum ${prop ? prop + ' ' : ''}[${String(raw)}] is not enforced in the validator`);
      }
    }
  }
  // 2. validator → schema
  for (const v of validatorSets) {
    if (!schemaSets.some(s => setsEqual(s, v))) {
      drift.push(`validator *_ENUM [${[...v].map(k => JSON.parse(k)).join(', ')}] is not declared as a schema enum`);
    }
  }
  // 3. patterns
  for (const p of acc.patterns) {
    if (!src.includes(p)) drift.push(`schema pattern "${p}" is not present in the validator`);
  }
  return { drift };
}

function checkSchemaConsistency(schemaPaths, validatorPath, group, report = expectNoProblems) {
  const label = `${group} (schema ↔ validator)`;
  const { drift, error } = computeSchemaDrift(schemaPaths, validatorPath);
  report(label, error ? [error] : drift.map(d => `- ${d}`));
}

// ── repo-structure gates (plugin layout + version + changelog bookkeeping + dir completeness + registration) ──
//
// All are pure: they take a directory / parsed data and return a list of problem
// strings, so the self-test canaries can feed them a planted defect without touching
// the real repo.

/**
 * A plugin's `commands/<X>.md` and a skill whose effective name is `<X>` resolve to the
 * same qualified name `<plugin>:<X>`; the command shadows the skill and the skill body
 * never loads (session-reflect 1.0.0 shipped exactly this; `claude plugin validate`
 * does not catch it). Effective skill name = SKILL.md frontmatter `name`, else dir name.
 */
function findCommandSkillCollisions(pluginDir) {
  // Not existsSync: a FILE named `commands` passes that and makes readdirSync throw ENOTDIR,
  // which aborts the whole run with no Summary and no failure list (the dir-completeness gate
  // would have reported that dir, but never gets to print).
  const ls = (d) => { try { return fs.readdirSync(d, { withFileTypes: true }); } catch { return []; } };
  const commands = new Set(
    ls(path.join(pluginDir, 'commands')).filter((e) => e.isFile() && e.name.endsWith('.md')).map((e) => e.name.slice(0, -3)),
  );
  const problems = [];
  for (const e of ls(path.join(pluginDir, 'skills'))) {
    if (!e.isDirectory()) continue;
    const skillMd = path.join(pluginDir, 'skills', e.name, 'SKILL.md');
    let name = e.name;
    if (fs.existsSync(skillMd)) {
      const fm = /^---\r?\n([\s\S]*?)\r?\n---/.exec(fs.readFileSync(skillMd, 'utf8'));
      const m = fm && /^name:\s*(.+?)\s*$/m.exec(fm[1]);
      if (m) name = m[1].replace(/^(['"])(.*)\1$/, '$2');
    }
    if (commands.has(name)) problems.push(`commands/${name}.md shadows skills/${e.name}/ (both resolve to :${name})`);
  }
  return problems;
}

const SEMVER = /^\d+\.\d+\.\d+$/;
const cmpSemver = (a, b) => {
  const [x, y] = [a, b].map((v) => v.split('.').map(Number));
  return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
};

/**
 * Version bookkeeping. `pluginVersions` maps plugin name → its plugin.json version
 * (undefined = no manifest); `changelogs` maps file label → text.
 *   (1) each marketplace entry version === that plugin's plugin.json version
 *   (2) metadata.version === the top `## [x.y.z]` heading of every changelog
 *   (3) changelog headings are semver, unique and strictly decreasing — (2) alone
 *       misses a merge that keeps two `## [1.10.7]` sections, since the top one still
 *       equals a (wrongly auto-merged) metadata.version.
 * Known residue: two releases folded into ONE section is not statically detectable.
 */
function versionProblems(marketplace, pluginVersions, changelogs) {
  const problems = [];
  for (const entry of marketplace.plugins || []) {
    const pv = pluginVersions[entry.name];
    if (pv === undefined) problems.push(`marketplace entry "${entry.name}": no plugin.json found`);
    else if (entry.version !== pv) problems.push(`marketplace entry "${entry.name}" is ${entry.version} but plugin.json is ${pv}`);
  }
  const meta = marketplace.metadata && marketplace.metadata.version;
  for (const [label, text] of Object.entries(changelogs)) {
    problems.push(...changelogHeadingProblems(label, text, { value: meta, what: 'marketplace metadata.version' }));
  }
  return problems;
}

/**
 * The three heading rules a changelog must satisfy: its top `## [x.y.z]` equals
 * `expected.value`, and every heading is semver, unique and strictly decreasing.
 * Shared by the root changelogs (expected: marketplace `metadata.version`) and by
 * each plugin's own (expected: that plugin's `plugin.json` version) so the two
 * cannot drift apart. `expected.what` names the authority in the message.
 * Known residue (predates this extraction): a non-semver heading makes the decreasing check
 * skip the NEXT comparison, because the guard requires the PREVIOUS heading to be semver —
 * ['2.0.3','Unreleased','2.0.4'] reports the non-semver heading but not the order break.
 */
function changelogHeadingProblems(label, text, expected) {
  const heads = [...text.matchAll(/^## \[([^\]]+)\]/gm)].map((m) => m[1]);
  if (heads.length === 0) return [`${label}: no "## [x.y.z]" heading`];
  const problems = [];
  if (heads[0] !== expected.value) problems.push(`${label}: top heading [${heads[0]}] != ${expected.what} ${expected.value}`);
  for (let i = 0; i < heads.length; i++) {
    if (!SEMVER.test(heads[i])) { problems.push(`${label}: heading [${heads[i]}] is not x.y.z`); continue; }
    if (i > 0 && SEMVER.test(heads[i - 1]) && cmpSemver(heads[i - 1], heads[i]) <= 0) {
      problems.push(`${label}: heading [${heads[i - 1]}] is followed by [${heads[i]}] (must be strictly decreasing, no duplicates)`);
    }
  }
  return problems;
}

/**
 * Plugin-level changelog bookkeeping. `pluginChangelogs` maps plugin dir name →
 * { text, version }, `version` being that plugin's `plugin.json` version.
 *   - a plugin that HAS plugins/<p>/CHANGELOG.md must carry its own version as the
 *     top `## [x.y.z]` heading, with the same semver/unique/decreasing rules the
 *     root changelogs get
 *   - a plugin with NO CHANGELOG.md is absent from the map and unchecked. That is not a
 *     licence to omit one: pluginDirProblems() requires every dir with a manifest to have a
 *     changelog, so the absent case here means "already reported by that gate", not "fine"
 * The root gate cannot cover this — it compares every changelog it is handed
 * against `metadata.version`, which is the marketplace's number, not the plugin's.
 * Before this gate, plugins/<p>/CHANGELOG.md was read by no gate and no hook:
 * bumping plugin.json while forgetting the changelog entry left CI green
 * (dfe8c1b/c920bd9, 2026-03-07 — dev-workflow shipped 1.1.0/1.1.1 against a
 * [1.0.1] top heading; caught by hand 5 days later in 35c0a9c).
 * Scope is `CHANGELOG.md` only: no plugin ships a `CHANGELOG.zh-TW.md` (CONTRIBUTING §3 scopes
 * bilingual docs to the repo root), so there is nothing to check today — but this collection
 * loop and the hook's trigger regex both hard-code the filename and would have to change together.
 */
function pluginChangelogProblems(pluginChangelogs) {
  const problems = [];
  for (const [name, { text, version }] of Object.entries(pluginChangelogs)) {
    problems.push(...changelogHeadingProblems(`plugins/${name}/CHANGELOG.md`, text, { value: version, what: 'plugin.json version' }));
  }
  return problems;
}

/**
 * Plugin directory completeness. `dirs` maps a plugins/<p> dir name to which of its parts exist,
 * as booleans: `{ manifest, changelog, readme, commands, skills, agents, hooks, manifestDir }`.
 *   - `symlinked` lists plugins/ entries that are symlinks. They are NOT in `dirs` at all, which
 *     is the point: `Dirent.isDirectory()` is lstat semantics and false for a symlink, so every
 *     gate walking pluginDirs skips such a plugin silently. Linking a plugin dir in is refused
 *     rather than supported — the hook follows symlinks when it runs plugins/<p>/tests/*.test.sh,
 *     so accepting them would widen an execution surface for no use case this repo has.
 *   - a dir WITH a manifest must also have CHANGELOG.md and README.md. The changelog gate is
 *     opt-in by file existence, so a deleted changelog would disarm it silently — and `rm` runs
 *     through Bash, which the PostToolUse hook (Edit|Write|MultiEdit) never sees. README.md is
 *     required by the same argument that required the changelog: CONTRIBUTING §1's template lists
 *     both, and marks only `.mcp.json` / `reference.md` optional.
 *   - a dir WITHOUT a manifest but carrying any plugin component is a half-built plugin. Nothing
 *     else can see it: the version gate walks marketplace ENTRIES, and the registration gate only
 *     collects dirs that already have a manifest. `hooks/` matters most here — three shipped
 *     plugins are hooks-plus-manifest, and plugins/<p>/hooks/* is exactly what the denyWrite gate
 *     enumerates as EXECUTED, so a manifest-less hooks dir would be run while counting as "not a
 *     plugin". Listing only changelog/commands/skills left the other five components invisible.
 * An empty or incidental directory (no manifest and no component) is not a plugin and is left alone.
 * Finding a component in the half-built branch is NOT a claim that every plugin must have that
 * component; which files are required is answered by the manifest branch above (CHANGELOG.md and
 * README.md), and this branch only fires when the manifest is absent.
 */
function pluginDirProblems(dirs, symlinked = []) {
  const problems = [];
  for (const name of symlinked) {
    problems.push(`plugins/${name} is a symlink — a plugin dir must be a real directory: Dirent.isDirectory() is lstat semantics and returns false for a symlink, so every gate that walks pluginDirs skips it entirely (only the denyWrite gate notices, under a different name). Move the plugin into the repo rather than linking it in`);
  }
  for (const [name, has] of Object.entries(dirs)) {
    if (has.manifest) {
      if (!has.changelog) {
        problems.push(`plugins/${name}/: has a plugin.json but no CHANGELOG.md — every plugin keeps its own (CONTRIBUTING §4), and without the file the changelog gate has nothing to check`);
      }
      if (!has.readme) {
        problems.push(`plugins/${name}/: has a plugin.json but no README.md — CONTRIBUTING §1's template lists it next to CHANGELOG.md (only .mcp.json and reference.md are marked optional), and it is what a user reads after installing`);
      }
      continue;
    }
    const parts = [
      has.changelog && 'CHANGELOG.md',
      has.readme && 'README.md',
      has.commands && 'commands/',
      has.skills && 'skills/',
      has.agents && 'agents/',
      has.hooks && 'hooks/',
      has.manifestDir && '.claude-plugin/ without a plugin.json',
    ].filter(Boolean);
    if (parts.length) {
      problems.push(`plugins/${name}/: has ${parts.join(' + ')} but no .claude-plugin/plugin.json — an unfinished plugin dir that no other gate can see`);
    }
  }
  return problems;
}

/**
 * The coverage floor every gate needs whose canaries drive a pure function with hand-written input:
 * those canaries stay green when the loop that BUILDS that input stops building it, so each gate
 * compares what it shaped against a count taken independently of the loop. Kept as a function so the
 * floor itself is canary-covered — deleting an inline `if` was otherwise a silent way to disarm it.
 */
function shapedCountProblems(shaped, expected, what) {
  if (shaped === expected) return [];
  return [`shaped ${shaped} of ${expected} ${what} — the collection loop is not reading what this gate claims to`];
}

/**
 * The plugins/ inventory the dir-completeness gate judges, plus the wiring, in one testable place.
 * Extracted because canaries that hand `pluginDirProblems` a written-out map cover the JUDGEMENT
 * and not the COLLECTION: four mutations of the inline version — `symlinked` stubbed to `[]`,
 * `isSymbolicLink()` swapped for `isFIFO()`, `readme` hardcoded `true`, and the second argument
 * dropped at the call site — every one left the suite green, because a clean repo gives the
 * judgement nothing to report either way. `pluginDirGateProblems` is what the gate calls, so the
 * wiring is inside the canary's reach too.
 *   - file parts use `statSync().isFile()`: `existsSync` is true for a DIRECTORY named README.md,
 *     and README.md is the one required file with no downstream reader to catch that (a directory
 *     named CHANGELOG.md trips the changelog gate's readFileSync with EISDIR, one named plugin.json
 *     trips the version gate's load()).
 *   - names come from readdir rather than an existsSync probe: on case-insensitive APFS
 *     `existsSync('README.md')` is true for a file named `readme.md`, which would pass here and
 *     fail on the case-sensitive filesystem CI runs on — green locally, red in CI.
 */
function pluginDirInventory(pluginsPath) {
  const isFile = (f) => { try { return fs.statSync(f).isFile(); } catch { return false; } };
  const isDir = (f) => { try { return fs.statSync(f).isDirectory(); } catch { return false; } };
  const entries = fs.readdirSync(pluginsPath, { withFileTypes: true });
  const dirs = entries.filter((e) => e.isDirectory()).map((e) => e.name);
  // Symlinks are absent from `dirs` by isDirectory()'s lstat semantics — which is why they are
  // listed separately: every gate that walks the dir list would skip them silently.
  const symlinked = entries.filter((e) => e.isSymbolicLink()).map((e) => e.name);
  const shapes = Object.create(null);
  for (const name of dirs) {
    const dir = path.join(pluginsPath, name);
    const at = (...rel) => path.join(dir, ...rel);
    const names = new Set(fs.readdirSync(dir));
    const cpNames = isDir(at('.claude-plugin')) ? new Set(fs.readdirSync(at('.claude-plugin'))) : new Set();
    shapes[name] = {
      manifest: cpNames.has('plugin.json') && isFile(at('.claude-plugin', 'plugin.json')),
      manifestDir: isDir(at('.claude-plugin')),
      changelog: names.has('CHANGELOG.md') && isFile(at('CHANGELOG.md')),
      readme: names.has('README.md') && isFile(at('README.md')),
      commands: isDir(at('commands')),
      skills: isDir(at('skills')),
      agents: isDir(at('agents')),
      hooks: isDir(at('hooks')),
    };
  }
  return { entryCount: entries.length, dirs, symlinked, shapes };
}

function pluginDirGateProblems(pluginsPath) {
  const inv = pluginDirInventory(pluginsPath);
  return [
    ...shapedCountProblems(Object.keys(inv.shapes).length, inv.dirs.length, 'plugin dir(s)'),
    ...pluginDirProblems(inv.shapes, inv.symlinked),
  ];
}

/**
 * Marketplace registration. `entries` is [{ name, dir }] — `dir` the ROOT-relative directory
 * an entry's `source` resolves to (null for a non-path source); `manifests` maps each
 * `plugins/<p>` dir that HAS a plugin.json → { name } when it parsed, or { unreadable: true }.
 * (Scope: only dirs directly under plugins/ — an entry whose source points elsewhere gets no
 * name check here; the version gate still covers it.)
 *   (1) orphan: a plugin dir with a manifest that no entry points at. The version gate walks
 *       entries only, so an unregistered plugin is invisible to it — and it is uninstallable.
 *   (2) an entry's name must equal its plugin.json `name`: the entry name is what users
 *       install, the manifest name is what namespaces the plugin's skills/commands.
 * "Unreadable" and "readable but nameless" are deliberately distinct: only the former is
 * skipped. For a REGISTERED dir the version gate has already named the unreadable file; for
 * an ORPHAN nothing reports the broken JSON — the orphan report is the actionable failure,
 * and the JSON error surfaces once the plugin is registered.
 */
function registrationProblems(entries, manifests) {
  const problems = [];
  const registered = new Set(entries.map((e) => e.dir).filter((d) => d !== null));
  for (const dir of Object.keys(manifests)) {
    if (!registered.has(dir)) problems.push(`${dir} has a plugin.json but no marketplace entry's source points at it`);
  }
  for (const entry of entries) {
    const m = entry.dir !== null ? manifests[entry.dir] : undefined;
    if (!m || m.unreadable) continue;
    // Explicit type check, not a bare `!==`: when the entry AND the manifest both lack a name,
    // undefined !== undefined is false and the pair would pass as "equal".
    if (typeof m.name !== 'string' || m.name === '') {
      problems.push(`${entry.dir}/.claude-plugin/plugin.json has no string "name" (marketplace entry "${entry.name}")`);
    } else if (m.name !== entry.name) {
      problems.push(`marketplace entry "${entry.name}" points at ${entry.dir}, whose plugin.json is named "${m.name}"`);
    }
  }
  return problems;
}

/**
 * Sandbox write-protection of the local hook's executed closure. The PostToolUse hook in
 * .claude/settings.json is run by the harness OUTSIDE the agent's Bash sandbox, so every
 * file it ends up executing must be un-writable from inside it (sandbox.filesystem.denyWrite),
 * or an auto-approved sandboxed write buys unsandboxed execution. `executed` is a list of
 * ROOT-relative paths; `patterns` is the denyWrite array.
 *
 * Accepts exactly ONE pattern shape: a root-relative literal path, which covers itself and
 * everything beneath it. Probed against the real sandbox (2026-09-17): the literal `scripts`
 * denies writes to files beneath it, denies creating a new file beneath it, and (from the
 * 2.1.274 rule generator) becomes a Seatbelt `subpath` rule with every ancestor pinned against
 * unlink — so a literal cannot be renamed away, and nothing can be renamed or symlinked in
 * beneath it.
 *
 * Every star entry is REJECTED, not merely unsupported — a policy, backed by two facts:
 *  - On Linux/WSL the same runtime DROPS every glob write pattern ("Skipping glob write pattern
 *    on Linux"), so a star entry protects nothing there while looking configured.
 *  - On macOS a star entry denies only paths matching its regex. Probed 2026-09-17: with the
 *    star-glob over the plugin test dirs in force, `mv <dir-containing-tests>` INTO plugins/
 *    SUCCEEDED — a rename is checked only on its destination path `plugins/<new>`, which no
 *    regex matched, and the whole subtree came along unchecked. A literal has no such hole.
 * Anything else (`**`, braces, `?`, classes, absolute or ~ paths, ./x, x/, `..`) is reported
 * as unverifiable rather than guessed at.
 *
 * A green here verifies the CONFIG lists the path; enforcement itself cannot be tested from
 * here (CI has no sandbox; the hook runs outside one). The live check below additionally
 * reports symlinks on the hook's enumeration path, which the hook follows.
 */
function denyWriteProblems(executed, patterns) {
  const problems = [];
  const matchers = [];
  for (const raw of patterns) {
    if (typeof raw !== 'string' || raw === '') { problems.push(`denyWrite entry ${JSON.stringify(raw)} is not a non-empty string`); continue; }
    // No normalising of ./x or x/ into x: those spellings were never probed against the sandbox.
    const p = raw;
    if (p.includes('*')) {
      problems.push(`denyWrite entry "${raw}" is a glob — globs are dropped on Linux and do not deny renaming a subtree in on macOS; list a literal directory instead`);
      continue;
    }
    if (/^[/~]/.test(p) || /[?{}[\]]/.test(p) || p.split('/').some((s) => s === '' || s === '.' || s === '..')) {
      problems.push(`denyWrite entry "${raw}" uses a form this check cannot verify (only root-relative literal paths are understood)`);
      continue;
    }
    // Literal segments, compared whole (`scripts` ≠ `scripts-extra`).
    matchers.push(p.split('/'));
  }
  for (const file of executed) {
    const segs = file.split('/');
    // Only a clean root-relative path can be matched: `..`, an absolute path or an empty segment
    // would otherwise be swallowed by a leading `*` and reported as covered.
    if (segs.some((s) => s === '' || s === '.' || s === '..')) {
      problems.push(`${file} is not a clean root-relative path, so its coverage cannot be verified`);
      continue;
    }
    // A pattern covers the path it names and everything beneath it: every pattern segment must
    // match the path segment at the same depth (whole segments — `scripts` ≠ `scripts-extra`).
    const covered = matchers.some((m) => m.length <= segs.length && m.every((seg, i) => seg === segs[i]));
    if (!covered) problems.push(`${file} is executed outside the sandbox but no sandbox.filesystem.denyWrite entry covers it`);
  }
  return problems;
}

/**
 * Which repo script does a command hook run? Returns { script } (ROOT-relative) or { problem }.
 * Accepts exactly ONE shape — `node "$CLAUDE_PROJECT_DIR/<path>"` (quotes and ${} optional) —
 * and calls everything else unverifiable. Token-scraping a free-form command is a false-green
 * machine: a second script chained with &&, a .py, a path with a space, or a mistyped path that
 * does not exist yet would all be silently dropped — and "does not exist yet" is the worst case
 * here, not a harmless one: an unprotected path the sandbox can create is a path the hook will run.
 */
function hookScriptOf(command) {
  const m = /^node\s+"?\$\{?CLAUDE_PROJECT_DIR\}?"?\/([\w.@/-]+)"?$/.exec(String(command).trim());
  if (!m || m[1].split('/').some((s) => s === '' || s === '.' || s === '..')) {
    return { problem: `cannot verify what this hook runs (only \`node "$CLAUDE_PROJECT_DIR/<path>"\` is understood): ${command}` };
  }
  return { script: m[1] };
}

/**
 * The plugin-side files the local hook ends up executing, enumerated the way the HOOK does it —
 * by name, following symlinks — not with Dirent.isDirectory(), which is false for a symlink and
 * would skip exactly the entry the hook goes on to run. Returns { files, problems }: `files` are
 * ROOT-relative suites (plugins/<p>/tests/<x>.test.sh) and hook scripts (everything in plugins/<p>/hooks
 * except .json wiring data); a symlink anywhere on those paths is a problem, because what it
 * points at lies outside anything a denyWrite path rule names.
 */
function enumerateHookExecuted(root) {
  const files = [];
  const problems = [];
  const isLink = (p) => { try { return fs.lstatSync(p).isSymbolicLink(); } catch { return false; } };
  const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
  const link = (rel, follows) => problems.push(`${rel} is a symlink — ${follows ? 'the hook follows it, and ' : ''}what it points at is not pinned by a denyWrite literal`);
  const pluginsDir = path.join(root, 'plugins');
  for (const name of isDir(pluginsDir) ? fs.readdirSync(pluginsDir) : []) {
    const pluginDir = path.join(pluginsDir, name);
    if (isLink(pluginDir)) { link(`plugins/${name}`, true); continue; }
    if (!isDir(pluginDir)) continue;
    for (const [sub, keep] of [['tests', (f) => f.endsWith('.test.sh')], ['hooks', (f) => !f.endsWith('.json')]]) {
      const dir = path.join(pluginDir, sub);
      if (isLink(dir)) { link(`plugins/${name}/${sub}`, true); continue; }
      if (!isDir(dir)) continue;
      for (const f of fs.readdirSync(dir)) {
        if (!keep(f)) continue;
        const file = path.join(dir, f);
        if (isLink(file)) link(`plugins/${name}/${sub}/${f}`, false);
        else if (!isDir(file)) files.push(`plugins/${name}/${sub}/${f}`);
      }
    }
  }
  return { files, problems };
}

/** Report a problem list as one check. */
function expectNoProblems(label, problems) {
  if (problems.length === 0) { console.log(`  ✓  ${label}`); passed++; return; }
  console.error(`  ✗  ${label}`);
  problems.forEach((p) => console.error(`     ${p}`));
  failed++;
  failures.push(label);
}

// ── path helpers ──────────────────────────────────────────────────────────────

const P = (...parts) => path.join(ROOT, ...parts);

// ── fixture suite ─────────────────────────────────────────────────────────────

function main() {
  console.log('\n=== validate-fixtures: repo-root fixture runner ===\n');

  // ── Self-test: the checkers must detect a planted defect (else they give false green) ──
  console.log('## Self-test (canaries)');
  // Shared by the canaries below: the code-audit-rigor finding schema, validator and a valid
  // fixture, and the multi-agent-debate output schema and validator (a mismatched pair).
  const findSchema0 = P('plugins/code-audit-rigor/schema/finding.schema.json');
  const findV0 = P('plugins/code-audit-rigor/validators/validate-finding.cjs');
  const findValid0 = P('plugins/code-audit-rigor/tests/fixtures/code-audit-rigor/finding-valid.json');
  const debateSchema0 = P('plugins/multi-agent-debate/schema/debate-output.schema.json');
  const debateV0 = P('plugins/multi-agent-debate/validators/validate-debate-output.cjs');
  {
    // (a) consistency gate MUST report drift for a deliberately mismatched schema/validator pair.
    const { drift, error } = computeSchemaDrift([findSchema0], debateV0);
    const label = 'canary: consistency gate detects a mismatched schema/validator pair';
    expectNoProblems(label, !error && Array.isArray(drift) && drift.length > 0 ? [] : [`gate did NOT report drift (error=${error || 'none'})`]);
  }
  {
    // (a2) checkSchemaConsistency passes that drift on to its report: two mismatched pairs
    //      must report problems and two matched pairs must report none; an unreadable
    //      validator or schema (computeSchemaDrift's `error`) must report problems too. A
    //      check that ignores the drift or the error fails one side.
    const label = 'canary: consistency check reports drift for mismatched pairs and nothing for matched ones';
    const unreadable = P('scripts/no-such-file-for-the-canary.cjs'); // only read, never executed
    const seen = [];
    const sink = (l, problems) => seen.push(problems.length > 0);
    checkSchemaConsistency([findSchema0], debateV0, 'x', sink);
    checkSchemaConsistency([debateSchema0], findV0, 'x', sink);
    checkSchemaConsistency([findSchema0], findV0, 'x', sink);
    checkSchemaConsistency([debateSchema0], debateV0, 'x', sink);
    checkSchemaConsistency([findSchema0], unreadable, 'x', sink);
    checkSchemaConsistency([unreadable], findV0, 'x', sink);
    const got = JSON.stringify(seen);
    const want = JSON.stringify([true, true, false, false, true, true]);
    expectNoProblems(label, got === want ? [] : [`problems reported per pair ${got}, wanted ${want}`]);
  }
  // (b) The fixture and mutation harnesses, driven through runOutcome / mutationOutcomes —
  //     the same paths every run / runMutations call takes.
  {
    // (b1) runOutcome's four verdicts, the missing-file ones with an INVALID expectation
    //      (why that matters: see its docblock).
    const label = 'canary: fixture harness judges valid/invalid both ways and fails fast on a missing fixture or validator';
    // The "missing" paths live in a fresh private dir: at a guessable path, a file someone
    // planted there would be run by node outside the sandbox.
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-missing-'));
    try {
      const cases = [
        runOutcome(findV0, findValid0, true),
        runOutcome(findV0, findValid0, false),
        runOutcome(findV0, path.join(tmp, 'missing.json'), false),
        runOutcome(path.join(tmp, 'missing.cjs'), findValid0, false),
      ];
      const got = JSON.stringify(cases.map(o => o.ok));
      const msgsOk = cases[2].msg === 'fixture not found' && cases[3].msg === 'validator not found';
      expectNoProblems(label, got === JSON.stringify([true, false, false, false]) && msgsOk ? [] : [`ok flags ${got}, wanted [true,false,false,false]; outcomes=${JSON.stringify(cases)}`]);
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  {
    // (b2) runOutcome with an injected execFile: a spawn that never produced an exit status
    //      is a failure whichever way the fixture was expected (the INVALID case is the one
    //      a "treat it as exit 1" shortcut would pass); a real non-zero exit still satisfies
    //      an INVALID expectation and a clean exit does not.
    const label = 'canary: fixture harness fails a validator that could not be executed, even for an expected-invalid fixture';
    const noStatus = () => { throw new Error('spawn failed'); };
    const exit2 = () => { const e = new Error('exit 2'); e.status = 2; throw e; };
    const exit0 = () => Buffer.alloc(0);
    const cases = [
      runOutcome(findV0, findValid0, true, noStatus),
      runOutcome(findV0, findValid0, false, noStatus),
      runOutcome(findV0, findValid0, false, exit2),
      runOutcome(findV0, findValid0, false, exit0),
    ];
    const got = JSON.stringify(cases.map(o => o.ok));
    const msgsOk = cases.slice(0, 2).every(o => /^validator could not be executed/.test(o.msg));
    expectNoProblems(label, got === JSON.stringify([false, false, true, false]) && msgsOk ? [] : [`ok flags ${got}, wanted [false,false,true,false]; outcomes=${JSON.stringify(cases)}`]);
  }
  {
    // (b3) reportOutcome hands a failed outcome's message to its report and a passed one
    //      an empty list — two of each, so a report that drops ok (always [] or always
    //      [msg]) fails. run() and runMutations score only through it.
    const label = 'canary: reportOutcome reports a failed outcome as a problem and a passed one as none';
    const seen = [];
    const sink = (l, problems) => seen.push([l, problems]);
    for (const o of [
      { label: 'a', ok: false, msg: 'm1' }, { label: 'b', ok: true },
      { label: 'c', ok: false, msg: 'm2' }, { label: 'd', ok: true },
    ]) reportOutcome(o, sink);
    const got = JSON.stringify(seen);
    const want = JSON.stringify([['a', ['m1']], ['b', []], ['c', ['m2']], ['d', []]]);
    expectNoProblems(label, got === want ? [] : [`report saw ${got}, wanted ${want}`]);
  }
  {
    // (b4) mutationOutcomes MUST refuse a base the validator rejects, and must not run
    //      the mutations (see its docblock). A dropped `return` or a check moved after the
    //      loop fails this too: the mutation below exits non-zero on the invalid base and
    //      would score a pass.
    const label = 'canary: mutation harness refuses an invalid base fixture and skips its mutations';
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-base-'));
    try {
      const badBase = path.join(tmp, 'bad-base.json');
      fs.writeFileSync(badBase, JSON.stringify({ severity: 'NOT-A-SEVERITY' }));
      let mutateCalls = 0;
      const outcomes = mutationOutcomes(findV0, badBase, 'canary-base', [
        { label: 'would pass on an invalid base', mutate: o => { mutateCalls++; delete o.severity; } },
      ]);
      expectNoProblems(label, outcomes.length === 1 && !outcomes[0].ok && outcomes[0].baseRefused && mutateCalls === 0
        ? []
        : [`mutateCalls=${mutateCalls} outcomes=${JSON.stringify(outcomes)}`]);
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  {
    // (b5) mutationOutcomes scores each mutation on a valid base: a throwing mutate(), a
    //      no-op (the object stays valid, exit 0), and an `expect` that does not match the
    //      validator's output are all failures; a real mutation with a matching `expect`
    //      passes (so the base itself must validate). The four verdicts are asserted
    //      together so a branch that always returns ok (or never does) fails.
    const label = 'canary: mutation harness scores throw / no-op / wrong-expect as failures and a matched mutation as a pass';
    const outcomes = mutationOutcomes(findV0, findValid0, 'canary-score', [
      { label: 'throws', mutate: () => { throw new Error('drift'); } },
      { label: 'no-op', mutate: () => {} },
      { label: 'wrong expect', expect: /no such rule/, mutate: o => { o.severity = 'NOT-A-SEVERITY'; } },
      { label: 'matched', expect: /severity/i, mutate: o => { o.severity = 'NOT-A-SEVERITY'; } },
    ]);
    const got = JSON.stringify(outcomes.map(o => o.ok));
    expectNoProblems(label, got === JSON.stringify([false, false, false, true])
      ? []
      : [`ok flags ${got}, wanted [false,false,false,true]; outcomes=${JSON.stringify(outcomes)}`]);
  }
  {
    // (b6) Every other way mutationOutcomes can fail must yield exactly one ok:false entry,
    //      without baseRefused, whose msg names the path taken — so none of them can score
    //      a pass or pose as a rejected base. The BigInt case makes JSON.stringify throw
    //      before the spawn: the temp-file write is where a harness error must surface.
    const label = 'canary: mutation harness fails a missing validator, an unloadable base, and a validator it cannot run or feed';
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-mutfail-'));
    try {
      const badJson = path.join(tmp, 'not-json.json');
      fs.writeFileSync(badJson, '{ not json');
      const noStatus = () => { throw new Error('spawn failed'); };
      let calls = 0;
      const baseOkThenNoStatus = () => { if (calls++ === 0) return Buffer.alloc(0); throw new Error('spawn failed'); };
      const real = [{ label: 'real', mutate: o => { o.severity = 'NOT-A-SEVERITY'; } }];
      const cases = [
        ['missing validator', mutationOutcomes(path.join(tmp, 'missing.cjs'), findValid0, 'g', real), /^validator not found/],
        ['unloadable base', mutationOutcomes(findV0, badJson, 'g', real), /^cannot load valid base/],
        ['base cannot run', mutationOutcomes(findV0, findValid0, 'g', real, noStatus), /^validator could not be executed on base/],
        ['mutation cannot run', mutationOutcomes(findV0, findValid0, 'g', real, baseOkThenNoStatus), /^validator could not be executed — spawn failed/],
        ['mutation cannot be written', mutationOutcomes(findV0, findValid0, 'g', [{ label: 'bigint', mutate: o => { o.n = 1n; } }]), /^validator could not be executed — .*BigInt/],
      ];
      const problems = cases
        .filter(([, out, re]) => !(out.length === 1 && out[0].ok === false && !out[0].baseRefused && re.test(out[0].msg)))
        .map(([what, out]) => `${what}: ${JSON.stringify(out)}`);
      expectNoProblems(label, problems);
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  {
    // (c) collision gate MUST flag a planted commands/<X>.md ↔ skill-named-<X> pair — incl. a
    //     skill whose frontmatter name differs from its directory — and stay quiet on a clean plugin.
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-collision-'));
    try {
      const mk = (rel, body) => { const f = path.join(tmp, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body); };
      mk('bad/commands/reflect.md', 'x');
      mk('bad/skills/some-dir/SKILL.md', '---\nname: reflect\ndescription: d\n---\n');
      mk('clean/commands/run.md', 'x');
      mk('clean/skills/reflect/SKILL.md', '---\nname: reflect\ndescription: d\n---\n');
      const planted = 'canary: collision gate detects a command shadowing a skill (frontmatter name ≠ dir name)';
      const quiet = 'canary: collision gate stays quiet on a plugin with distinct command/skill names';
      expectNoProblems(planted, findCommandSkillCollisions(path.join(tmp, 'bad')).length === 1 ? [] : ['planted collision NOT reported']);
      expectNoProblems(quiet, findCommandSkillCollisions(path.join(tmp, 'clean')).length === 0 ? [] : ['false positive']);
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  {
    // (d) version gate MUST flag each planted drift, and exactly that drift.
    const ok = { metadata: { version: '1.2.0' }, plugins: [{ name: 'p', version: '0.1.0' }] };
    const log = '## [1.2.0] - d\n\n## [1.1.0] - d\n';
    const cases = [
      ['consistent data → no problems', ok, { p: '0.1.0' }, { CL: log }, 0],
      ['entry version ≠ plugin.json', ok, { p: '0.1.1' }, { CL: log }, 1],
      ['metadata.version ≠ top changelog heading', ok, { p: '0.1.0' }, { CL: '## [1.3.0] - d\n\n## [1.2.0] - d\n' }, 1],
      ['duplicate changelog heading (two releases claiming one number)', ok, { p: '0.1.0' }, { CL: '## [1.2.0] - d\n\n## [1.2.0] - d\n\n## [1.1.0] - d\n' }, 1],
      ['entry without a plugin.json', ok, {}, { CL: log }, 1],
    ];
    for (const [what, mp, pv, cl, want] of cases) {
      const label = `canary: version gate — ${what}`;
      const got = versionProblems(mp, pv, cl).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want} problem(s), got ${got}`]);
    }
  }

  {
    // (i) plugin changelog gate MUST flag each planted drift, and exactly that drift.
    //     Counts alone are weak — a version that names the wrong file, or credits
    //     metadata.version instead of plugin.json, still returns exactly 1 — so the last check
    //     asserts the whole message. The "no changelog" decision lives in main()'s collection
    //     loop, not here; the coverage floor there guards it, a canary on this pure function cannot.
    const log = (...vs) => vs.map((v) => `## [${v}] - d\n`).join('\n');
    const cases = [
      ['top heading = plugin.json version → no problems', { p: { text: log('2.0.3', '2.0.2'), version: '2.0.3' } }, 0],
      ['plugin.json bumped, changelog entry forgotten (the 2026-03-07 defect)', { p: { text: log('2.0.2', '2.0.1'), version: '2.0.3' } }, 1],
      ['duplicate heading (two releases claiming one number)', { p: { text: log('2.0.3', '2.0.3', '2.0.2'), version: '2.0.3' } }, 1],
      ['non-semver top heading — flagged twice (≠ version AND not x.y.z)', { p: { text: '## [Unreleased] - d\n', version: '2.0.3' } }, 2],
      ['a changelog with no heading at all', { p: { text: '# Changelog\n', version: '2.0.3' } }, 1],
      ['an empty map does not throw', {}, 0],
      ['one plugin drifting does not mask another that is clean', { a: { text: log('1.0.0'), version: '1.0.0' }, b: { text: log('1.0.0'), version: '2.0.0' } }, 1],
    ];
    for (const [what, input, want] of cases) {
      const label = `canary: plugin changelog gate — ${what}`;
      const got = pluginChangelogProblems(input).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want} problem(s), got ${got}`]);
    }
    const msgLabel = 'canary: plugin changelog gate — the message names the file and the authority';
    const msgGot = pluginChangelogProblems({ a: { text: '## [1.0.0] - d\n', version: '2.0.0' } });
    const msgWant = 'plugins/a/CHANGELOG.md: top heading [1.0.0] != plugin.json version 2.0.0';
    expectNoProblems(msgLabel, msgGot.length === 1 && msgGot[0] === msgWant ? [] : [`got ${JSON.stringify(msgGot)}`]);
  }


  {
    // (j) plugin dir completeness MUST flag a manifest without a changelog or README, a half-built
    //     dir, and a symlinked plugin dir (which no other gate can see at all).
    const d = (o) => ({ manifest: false, manifestDir: false, changelog: false, readme: false, commands: false, skills: false, agents: false, hooks: false, ...o });
    const cases = [
      ['a complete plugin dir → no problems', { p: d({ manifest: true, manifestDir: true, changelog: true, readme: true, commands: true }) }, 0],
      ['manifest but no CHANGELOG (deleting one would disarm the changelog gate)', { p: d({ manifest: true, readme: true, commands: true }) }, 1],
      ['manifest but no README', { p: d({ manifest: true, changelog: true, commands: true }) }, 1],
      ['manifest missing both CHANGELOG and README → both reported', { p: d({ manifest: true, commands: true }) }, 2],
      ['two dirs each missing README (a break in that branch would hide one)', { a: d({ manifest: true, changelog: true }), b: d({ manifest: true, changelog: true, commands: true }) }, 2],
      ['half-built: CHANGELOG but no manifest', { p: d({ changelog: true }) }, 1],
      ['half-built: commands/ but no manifest', { p: d({ commands: true }) }, 1],
      ['half-built: skills/ but no manifest', { p: d({ skills: true }) }, 1],
      ['half-built: agents/ but no manifest', { p: d({ agents: true }) }, 1],
      ['half-built: hooks/ but no manifest (and hooks/* is what denyWrite calls EXECUTED)', { p: d({ hooks: true }) }, 1],
      ['half-built: README.md but no manifest', { p: d({ readme: true }) }, 1],
      ['half-built: a .claude-plugin/ dir holding no plugin.json', { p: d({ manifestDir: true }) }, 1],
      ['an unrelated empty dir is not a plugin', { p: d({}) }, 0],
      // TWO of each kind of breakage, plus a clean dir. One of each is not enough: a `break` after
      // the half-built push still reports the earlier missing-changelog dir, so the total stays 2
      // and the mutant survives. With two per branch, any push-then-break / early-return /
      // report-only-the-first mutation drops a count and gets caught.
      ['one broken dir does not mask another', {
        a: d({ manifest: true, readme: true }),
        b: d({ manifest: true, readme: true, commands: true }),
        c: d({ changelog: true }),
        e: d({ commands: true }),
        f: d({ manifest: true, changelog: true, readme: true }),
      }, 4],
    ];
    for (const [what, input, want] of cases) {
      const label = `canary: plugin dir gate — ${what}`;
      const got = pluginDirProblems(input).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want} problem(s), got ${got}`]);
    }
    // Both branches get a whole-message assertion. Counting alone let the half-built message be
    // replaced by the OPPOSITE failure mode ("has a plugin.json but no CHANGELOG.md") and stay green.
    // The symlink branch gets the same treatment: two entries so a break shows, plus a message
    // assertion. These dirs are absent from `dirs` entirely, so only the second argument exercises them.
    const symCases = [
      ['no symlinked dirs → silent', [{}, []], 0],
      ['one symlinked plugin dir', [{}, ['ghost']], 1],
      ['two symlinked dirs (a break in that loop would hide one)', [{}, ['ghost', 'phantom']], 2],
      ['a symlink alongside a broken real dir — both reported', [{ a: d({ manifest: true, changelog: true }) }, ['ghost']], 2],
    ];
    for (const [what, args, want] of symCases) {
      const label = `canary: plugin dir gate — ${what}`;
      const got = pluginDirProblems(...args).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want} problem(s), got ${got}`]);
    }
    const msgCases = [
      ['the missing-changelog message names the dir and what is missing', { a: d({ manifest: true, readme: true }) },
        'plugins/a/: has a plugin.json but no CHANGELOG.md — every plugin keeps its own (CONTRIBUTING §4), and without the file the changelog gate has nothing to check'],
      ['the missing-README message names the dir and what is missing', { a: d({ manifest: true, changelog: true }) },
        "plugins/a/: has a plugin.json but no README.md — CONTRIBUTING §1's template lists it next to CHANGELOG.md (only .mcp.json and reference.md are marked optional), and it is what a user reads after installing"],
      ['the half-built message names the dir and every part it found', { a: d({ changelog: true, commands: true, skills: true }) },
        'plugins/a/: has CHANGELOG.md + commands/ + skills/ but no .claude-plugin/plugin.json — an unfinished plugin dir that no other gate can see'],
    ];
    for (const [what, input, want] of msgCases) {
      const label = `canary: plugin dir gate — ${what}`;
      const got = pluginDirProblems(input);
      expectNoProblems(label, got.length === 1 && got[0] === want ? [] : [`got ${JSON.stringify(got)}`]);
    }
    const symMsgLabel = 'canary: plugin dir gate — the symlink message names the dir and why it is invisible';
    const symMsgGot = pluginDirProblems({}, ['ghost']);
    expectNoProblems(symMsgLabel, symMsgGot.length === 1 && symMsgGot[0].startsWith('plugins/ghost is a symlink — a plugin dir must be a real directory') ? [] : [`got ${JSON.stringify(symMsgGot)}`]);
    // The floor guards the collection loops; these guard the floor. Deleting it, or making its
    // condition always-false, was otherwise invisible because the real repo has nothing to report.
    const floorCases = [
      ['floor: shaped everything the loop was given → silent', [9, 9, 'plugin dir(s)'], 0],
      ['floor: shaped fewer than exist → named failure', [0, 9, 'plugin dir(s)'], 1],
      ['floor: shaped more than exist is also wrong', [10, 9, 'plugin dir(s)'], 1],
    ];
    for (const [what, args, want] of floorCases) {
      const label = `canary: ${what}`;
      const got = shapedCountProblems(...args).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want}, got ${got}`]);
    }
    const floorMsgLabel = 'canary: floor message carries both counts';
    const floorMsgGot = shapedCountProblems(3, 9, 'plugin dir(s)');
    expectNoProblems(floorMsgLabel, floorMsgGot.length === 1 && floorMsgGot[0].startsWith('shaped 3 of 9 plugin dir(s) —') ? [] : [`got ${JSON.stringify(floorMsgGot)}`]);
  }

  {
    // (k) the inventory AND the wiring must see what is on disk. The (j) canaries hand
    //     pluginDirProblems a written-out map, so they cannot catch a collection that stops
    //     collecting — and a clean repo reports nothing either way, which is why four mutations of
    //     the previous inline version all stayed green (pluginDirInventory's docblock lists them).
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-plugindirs-'));
    try {
      const mk = (rel, body) => { const f = path.join(tmp, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body === undefined ? 'x' : body); };
      mk('complete/.claude-plugin/plugin.json', '{"name":"complete","version":"1.0.0"}');
      mk('complete/CHANGELOG.md'); mk('complete/README.md');
      mk('noreadme/.claude-plugin/plugin.json', '{"name":"noreadme","version":"1.0.0"}');
      mk('noreadme/CHANGELOG.md');
      mk('readmedir/.claude-plugin/plugin.json', '{"name":"readmedir","version":"1.0.0"}');
      mk('readmedir/CHANGELOG.md');
      fs.mkdirSync(path.join(tmp, 'readmedir', 'README.md')); // a DIRECTORY wearing a file's name
      mk('halfbuilt/commands/c.md');
      mk('loose.txt'); // neither a dir nor a symlink — not a plugin, must be ignored
      fs.symlinkSync(path.join(tmp, 'complete'), path.join(tmp, 'linked'));
      fs.symlinkSync(path.join(tmp, 'does-not-exist'), path.join(tmp, 'dangling'));

      const inv = pluginDirInventory(tmp);
      const invChecks = [
        ['inventory: dirs exclude symlinks and loose files', [...inv.dirs].sort().join(','), 'complete,halfbuilt,noreadme,readmedir'],
        ['inventory: both symlinks listed, dangling included', [...inv.symlinked].sort().join(','), 'dangling,linked'],
        ['inventory: entryCount accounts for every plugins/ entry', String(inv.entryCount), '7'],
        ['inventory: a DIRECTORY named README.md is not a README', String(inv.shapes.readmedir.readme), 'false'],
        ['inventory: a real README.md is one', String(inv.shapes.complete.readme), 'true'],
        ['inventory: a manifest under .claude-plugin/ is found', String(inv.shapes.complete.manifest), 'true'],
        ['inventory: a dir with no manifest reports none', String(inv.shapes.halfbuilt.manifest), 'false'],
      ];
      for (const [what, got, want] of invChecks) {
        const label = `canary: ${what}`;
        expectNoProblems(label, got === want ? [] : [`expected ${want}, got ${got}`]);
      }
      // End to end through the wiring: five problems, one per planted defect, and no others.
      const probs = pluginDirGateProblems(tmp);
      const wired = [
        ['wiring: exactly one problem per planted defect', String(probs.length), '5'],
        ['wiring: the missing README is reported', String(probs.some((s) => s.startsWith('plugins/noreadme/: has a plugin.json but no README.md'))), 'true'],
        ['wiring: a README.md that is a directory counts as missing', String(probs.some((s) => s.startsWith('plugins/readmedir/: has a plugin.json but no README.md'))), 'true'],
        ['wiring: the half-built dir is reported', String(probs.some((s) => s.startsWith('plugins/halfbuilt/: has commands/'))), 'true'],
        ['wiring: both symlinked dirs are reported', String(probs.filter((s) => s.includes('is a symlink')).length), '2'],
        ['wiring: the complete dir is not reported', String(probs.some((s) => s.includes('plugins/complete'))), 'false'],
      ];
      for (const [what, got, want] of wired) {
        const label = `canary: ${what}`;
        expectNoProblems(label, got === want ? [] : [`expected ${want}, got ${got} — ${JSON.stringify(probs)}`]);
      }
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }

  {
    // (f) denyWrite gate MUST flag an executed file no literal covers, and MUST reject every glob —
    //     a star entry is dropped on Linux and, on macOS, does not deny renaming a subtree in (probed 2026-09-17).
    const pats = ['scripts', 'plugins', 'plugins/x/skills/x/validate.cjs'];
    const cases = [
      ['a literal dir covers everything beneath it; a literal file covers itself', ['scripts/a.cjs', 'scripts/hooks/b.cjs', 'plugins/p/tests/t.test.sh', 'plugins/p/deep/er/h.sh', 'plugins/x/skills/x/validate.cjs'], pats, 0],
      ['an executed file outside every literal', ['tools/v.cjs'], pats, 1],
      ['a literal must match whole segments (scripts does not cover scripts-extra/)', ['scripts-extra/x.cjs'], pats, 1],
      ['a single-segment star entry is rejected even though it would have matched', ['plugins/p/tests/t.test.sh'], ['scripts', 'plugins/*/tests'], 2],
      ['a ** entry is rejected', ['scripts/a.cjs'], ['scripts', 'plugins/**/tests'], 1],
      ['an absolute or ~ pattern is unsupported in project settings', ['scripts/a.cjs'], ['scripts', '~/x', '/abs/y'], 2],
      ['no denyWrite at all', ['scripts/a.cjs', 'plugins/p/tests/t.test.sh'], [], 2],
      ['executed path escaping the root, absolute, or with an empty segment is unverifiable', ['../outside.sh', '/abs/x.sh', 'a//b.sh'], ['scripts'], 3],
      ['un-probed spellings of a pattern (./x, x/) are unverifiable, not normalised into a pass', ['scripts/a.cjs'], ['./scripts', 'scripts/'], 3],
    ];
    for (const [what, ex, pt, want] of cases) {
      const label = `canary: denyWrite gate — ${what}`;
      const got = denyWriteProblems(ex, pt).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want} problem(s), got ${got}`]);
    }
  }
  {
    // (h) enumeration MUST find real suites/hook scripts and MUST report a symlinked plugin dir,
    //     a symlinked tests/ dir and a symlinked suite — the three places the hook would follow one.
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-enum-'));
    try {
      const mk = (rel, body) => { const f = path.join(tmp, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body); };
      mk('repo/plugins/real/tests/a.test.sh', 'x');
      mk('repo/plugins/real/tests/fixtures/data.json', '{}');
      mk('repo/plugins/real/hooks/h.sh', 'x');
      mk('repo/plugins/real/hooks/hooks.json', '{}');
      mk('repo/plugins/second/.keep', '');
      mk('elsewhere/tests/x.test.sh', 'x');
      fs.symlinkSync(path.join(tmp, 'elsewhere'), path.join(tmp, 'repo/plugins/linked-plugin'));
      fs.symlinkSync(path.join(tmp, 'elsewhere/tests'), path.join(tmp, 'repo/plugins/second/tests'));
      fs.symlinkSync(path.join(tmp, 'elsewhere/tests/x.test.sh'), path.join(tmp, 'repo/plugins/real/tests/linked.test.sh'));
      const got = enumerateHookExecuted(path.join(tmp, 'repo'));
      const files = 'canary: hook enumeration finds exactly the real suite and hook script (not fixtures, not hooks.json)';
      const links = 'canary: hook enumeration reports a symlinked plugin dir, tests/ dir and suite file';
      const wantFiles = ['plugins/real/hooks/h.sh', 'plugins/real/tests/a.test.sh'];
      expectNoProblems(files, JSON.stringify([...got.files].sort()) === JSON.stringify(wantFiles) ? [] : [`got ${JSON.stringify(got.files)}`]);
      expectNoProblems(links, got.problems.length === 3 ? [] : [`expected 3 problems, got ${JSON.stringify(got.problems)}`]);
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  {
    // (g) hook-command parsing MUST accept only the one verifiable shape, and keep a path that does not exist.
    const cases = [
      ['node "$CLAUDE_PROJECT_DIR/scripts/hooks/h.cjs"', 'scripts/hooks/h.cjs'],
      ['node ${CLAUDE_PROJECT_DIR}/scripts/hooks/h.cjs', 'scripts/hooks/h.cjs'],
      ['node "$CLAUDE_PROJECT_DIR"/scripts/hooks/h.cjs', 'scripts/hooks/h.cjs'],
      ['node "$CLAUDE_PROJECT_DIR/tools/not-created-yet.cjs"', 'tools/not-created-yet.cjs'],
      ['node "$CLAUDE_PROJECT_DIR/scripts/h.cjs" && node "$CLAUDE_PROJECT_DIR/tools/second.cjs"', null],
      ['python3 "$CLAUDE_PROJECT_DIR/tools/x.py"', null],
      ['node scripts/hooks/h.cjs', null],
      ['node "$CLAUDE_PROJECT_DIR/../elsewhere/h.cjs"', null],
      ['make validate', null],
    ];
    for (const [cmd, want] of cases) {
      const label = `canary: hook command — ${want ? `accepts and keeps "${want}"` : `rejects as unverifiable: ${cmd}`}`;
      const r = hookScriptOf(cmd);
      const ok = want ? r.script === want : typeof r.problem === 'string' && r.script === undefined;
      expectNoProblems(label, ok ? [] : [`got ${JSON.stringify(r)}`]);
    }
  }
  {
    // (e) registration gate MUST flag a planted orphan dir and a planted name mismatch.
    const entries = [{ name: 'a', dir: 'plugins/a' }, { name: 'remote', dir: null }];
    const cases = [
      ['every manifest dir registered, names equal → no problems', entries, { 'plugins/a': { name: 'a' } }, 0],
      ['orphan: a plugin dir with a manifest and no entry', entries, { 'plugins/a': { name: 'a' }, 'plugins/b': { name: 'b' } }, 1],
      ['entry name ≠ plugin.json name', entries, { 'plugins/a': { name: 'not-a' } }, 1],
      ['unreadable manifest of a REGISTERED dir is left to the version gate, not double-reported', entries, { 'plugins/a': { unreadable: true } }, 0],
      ['readable manifest with no "name" key (or a mistyped one) is a problem, not a skip', entries, { 'plugins/a': {} }, 1],
      // guards the typeof check: with a plain `!==`, undefined !== undefined is false and this slips through
      ['entry AND manifest both lack a name', [{ name: undefined, dir: 'plugins/a' }], { 'plugins/a': { name: undefined } }, 1],
    ];
    for (const [what, en, mf, want] of cases) {
      const label = `canary: registration gate — ${what}`;
      const got = registrationProblems(en, mf).length;
      expectNoProblems(label, got === want ? [] : [`expected ${want} problem(s), got ${got}`]);
    }
  }

  // ── Repo structure ───────────────────────────────────────────────────────────
  console.log('\n## Repo structure — command/skill name collisions + version + plugin changelog bookkeeping + dir completeness + marketplace registration');
  {
    const pluginEntries = fs.readdirSync(P('plugins'), { withFileTypes: true });
    const pluginDirs = pluginEntries.filter((e) => e.isDirectory()).map((e) => e.name);
    // Symlinks are absent from pluginDirs by isDirectory()'s lstat semantics — which is exactly why
    // they must be listed separately: every gate below walks pluginDirs and would skip them.
    const symlinkedPluginDirs = pluginEntries.filter((e) => e.isSymbolicLink()).map((e) => e.name);
    const collisions = [];
    for (const name of pluginDirs) findCommandSkillCollisions(P('plugins', name)).forEach((c) => collisions.push(`${name}: ${c}`));
    expectNoProblems(`no command shadows a same-named skill (${pluginDirs.length} plugins)`, collisions);

    // Load errors are reported as a named ✗ and the run continues (same convention as
    // computeSchemaDrift / runMutations): this block sits ahead of every fixture check, and
    // the local hook fires it on manifest edits — exactly when a JSON typo is likeliest. An
    // uncaught throw would still exit non-zero but drop the summary and every later check,
    // and a bare SyntaxError does not say WHICH of the plugin.json files broke.
    const versionLabel = 'marketplace ↔ plugin.json ↔ CHANGELOG versions agree; headings strictly decreasing';
    const loadErrors = [];
    const load = (file, parse) => {
      try { return parse(fs.readFileSync(file, 'utf8')); }
      catch (e) { loadErrors.push(`cannot read ${path.relative(ROOT, file)} — ${e.message}`); return undefined; }
    };
    const marketplace = load(P('.claude-plugin', 'marketplace.json'), JSON.parse);
    const changelogs = {};
    for (const f of ['CHANGELOG.md', 'CHANGELOG.zh-TW.md']) { const t = load(P(f), String); if (t !== undefined) changelogs[f] = t; }
    // Shape, not just syntax: valid JSON of the wrong shape (`plugins` an object, a null element,
    // a manifest that is `null`) would otherwise throw a TypeError below — the same summary-dropping
    // crash the load() helper exists to prevent. Normalise ONCE here for both gates. A malformed
    // element is REPORTED, never silently dropped: a filtered-out entry would mean one fewer thing
    // checked under a green light.
    const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
    const entryList = [];
    let marketplaceUsable = false;
    if (marketplace !== undefined) {
      if (!isObj(marketplace)) loadErrors.push('.claude-plugin/marketplace.json is not a JSON object');
      else if (!Array.isArray(marketplace.plugins)) loadErrors.push('.claude-plugin/marketplace.json: "plugins" is not an array');
      else {
        marketplaceUsable = true;
        marketplace.plugins.forEach((e, i) => {
          if (isObj(e)) entryList.push(e);
          else loadErrors.push(`.claude-plugin/marketplace.json: plugins[${i}] is not an object`);
        });
      }
    }
    // Resolve each entry's manifest through its own `source`, not by assuming dir name === entry
    // name, so "no plugin.json found" means what it says. Object-form sources (git/url) have no
    // local manifest to compare — say so rather than crash in path.resolve.
    const pluginVersions = {};
    for (const entry of entryList) {
      if (typeof entry.source !== 'string') { loadErrors.push(`marketplace entry "${entry.name}": non-path source, version not checkable here`); continue; }
      const manifest = path.resolve(ROOT, entry.source, '.claude-plugin', 'plugin.json');
      if (!fs.existsSync(manifest)) continue; // versionProblems reports the missing manifest
      const parsed = load(manifest, JSON.parse);
      if (parsed === undefined) continue; // load() already named the file
      if (isObj(parsed)) pluginVersions[entry.name] = parsed.version;
      else loadErrors.push(`${path.relative(ROOT, manifest)} is not a JSON object`);
    }
    // Never feed partial data to versionProblems: a missing marketplace would make it report
    // nothing (a misleading green) and a missing manifest would cascade into a second, wrong message.
    expectNoProblems(versionLabel, loadErrors.length > 0 ? loadErrors : versionProblems(marketplace, pluginVersions, changelogs));


    // Directory completeness: the three rules no other gate can express. Runs BEFORE the changelog
    // gate so "you deleted the changelog" is reported as such rather than as silence.
    // One call: collection, floor and judgement all live in pluginDirGateProblems, so canary (k)
    // covers the wiring too. Nothing here is left to mutate silently.
    const pluginDirLabel = 'every plugin dir is a real dir with a manifest, its own CHANGELOG and README; no half-built dirs';
    expectNoProblems(pluginDirLabel, pluginDirGateProblems(P('plugins')));

    // Each plugin's OWN changelog, anchored to its OWN plugin.json version — the gate above
    // compares against metadata.version, so it structurally cannot cover this. Walks DIRECTORIES
    // (like registration, not like the version gate) because a dir name need not equal an entry
    // name. A missing or unparseable manifest is deferred, NOT dropped: for a REGISTERED plugin the
    // version gate names the file, and for an unregistered dir the registration gate says "orphan"
    // (it reports "not registered", not "broken JSON" — see registrationProblems' docstring).
    const pluginChangelogLabel = 'each plugin CHANGELOG top heading = its own plugin.json version; headings strictly decreasing';
    // Counted BEFORE and INDEPENDENTLY of the loop below: a floor computed inside the loop would be
    // skipped by the same mutation it is meant to catch. The canaries exercise the pure function on
    // hand-written maps, so they stay green even if this loop stops collecting — mutating the guard
    // to `if (true) continue` left all 175 checks passing (verified 2026-09-18). Every changelog on
    // disk must end up either checked or explicitly deferred, or the gate says so instead of ✓.
    const changelogsOnDisk = pluginDirs.filter((name) => fs.existsSync(P('plugins', name, 'CHANGELOG.md')));
    const pluginChangelogs = {};
    const clLoadErrors = [];
    const clDeferred = [];
    for (const name of pluginDirs) {
      const clPath = P('plugins', name, 'CHANGELOG.md');
      if (!fs.existsSync(clPath)) continue; // no changelog — the dir-completeness gate reports it
      const manifestPath = P('plugins', name, '.claude-plugin', 'plugin.json');
      let m;
      try { m = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
      catch { clDeferred.push(name); continue; } // missing or unparseable — owned by the two gates above
      // A non-string version is NOT deferrable: the version gate compares entry vs manifest with
      // `!==`, so a single regex bump that drops the quotes on BOTH sides (CONTRIBUTING §4 has you
      // edit both in one pass) compares equal and passes, leaving this changelog unchecked by anyone.
      if (!isObj(m) || typeof m.version !== 'string') {
        clLoadErrors.push(`plugins/${name}/.claude-plugin/plugin.json: "version" is not a string — the version gate compares with !== and stays green when the marketplace entry holds the same non-string value`);
        clDeferred.push(name);
        continue;
      }
      try { pluginChangelogs[name] = { text: fs.readFileSync(clPath, 'utf8'), version: m.version }; }
      catch (e) { clLoadErrors.push(`cannot read plugins/${name}/CHANGELOG.md — ${e.message}`); clDeferred.push(name); }
    }
    const clAccounted = new Set([...Object.keys(pluginChangelogs), ...clDeferred]);
    const clUnread = changelogsOnDisk.filter((n) => !clAccounted.has(n));
    if (clUnread.length) {
      clLoadErrors.push(`never read ${clUnread.length} of ${changelogsOnDisk.length} plugin changelog(s) on disk (${clUnread.join(', ')}) — the collection loop is not reading what this gate claims to`);
    }
    // Concatenated, not short-circuited: one plugin's unreadable changelog does not make another
    // plugin's data partial, so hiding every real drift behind one ENOENT would just cost a round trip.
    expectNoProblems(pluginChangelogLabel, [...clLoadErrors, ...pluginChangelogProblems(pluginChangelogs)]);

    // Registration walks the DIRECTORIES (the version gate above walks entries, so a plugin
    // nobody registered never reaches it). Without a usable marketplace every dir would look
    // orphaned — report that once instead of nine cascading orphans, and never pass silently.
    const registrationLabel = 'every plugin dir is registered in the marketplace; entry names match plugin.json';
    if (!marketplaceUsable) {
      expectNoProblems(registrationLabel, ['cannot evaluate — .claude-plugin/marketplace.json unreadable or malformed (see the version check above)']);
    } else {
      const rel = (abs) => path.relative(ROOT, abs).split(path.sep).join('/');
      const entries = entryList.map((e) => ({
        name: e.name,
        dir: typeof e.source === 'string' ? rel(path.resolve(ROOT, e.source)) : null,
      }));
      const manifests = {};
      for (const name of pluginDirs) {
        const manifest = P('plugins', name, '.claude-plugin', 'plugin.json');
        if (!fs.existsSync(manifest)) continue;
        // Unparseable / non-object → { unreadable: true }, which registrationProblems skips for the
        // NAME check only (its docstring says who reports the file in the registered vs orphan case).
        let m = { unreadable: true };
        try { const p = JSON.parse(fs.readFileSync(manifest, 'utf8')); if (isObj(p)) m = { name: p.name }; } catch { /* stays unreadable */ }
        manifests[`plugins/${name}`] = m;
      }
      expectNoProblems(registrationLabel, registrationProblems(entries, manifests));
    }
  }

  // ── Multi-Agent Debate ───────────────────────────────────────────────────────
  console.log('## Multi-Agent Debate — debate-output validator');
  const debateV = P('plugins/multi-agent-debate/validators/validate-debate-output.cjs');
  const debateF = P('plugins/multi-agent-debate/tests/fixtures/debate-output');
  run(debateV, path.join(debateF, 'valid-basic.json'), true);
  run(debateV, path.join(debateF, 'invalid-missing-consensus.json'), false);
  run(debateV, path.join(debateF, 'invalid-bad-verdict.json'), false);
  run(debateV, path.join(debateF, 'invalid-score-out-of-range.json'), false);
  run(debateV, path.join(debateF, 'invalid-bad-severity.json'), false);
  run(debateV, path.join(debateF, 'invalid-noninteger-round.json'), false);
  run(debateV, path.join(debateF, 'invalid-consensus-not-boolean.json'), false);
  run(debateV, path.join(debateF, 'invalid-empty-critique-rounds.json'), false);

  console.log('\n## Multi-Agent Debate — prior-debate validator');
  const priorV = P('plugins/multi-agent-debate/validators/validate-prior-debate.cjs');
  const priorF = P('plugins/multi-agent-debate/tests/fixtures/prior-debate');
  run(priorV, path.join(priorF, 'valid-prior-debate.json'), true);
  run(priorV, path.join(priorF, 'invalid-suppresses-new-findings.json'), false);
  run(priorV, path.join(priorF, 'invalid-suppresses-new-decisions.json'), false);
  run(priorV, path.join(priorF, 'invalid-missing-applicability-note.json'), false);
  run(priorV, path.join(priorF, 'invalid-missing-required.json'), false);
  run(priorV, path.join(priorF, 'invalid-bad-schemaversion.json'), false);
  run(priorV, path.join(priorF, 'invalid-reuseconstraint-not-object.json'), false);

  // ── OpenSpec + Superpowers ─────────────────────────────────────────────────
  console.log('\n## OpenSpec + Superpowers Workflow — change-folder validator');
  const openV = P('plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs');
  const openF = P('plugins/openspec-superpowers-workflow/tests/fixtures/openspec-workflow');
  run(openV, path.join(openF, 'valid-change'), true);
  run(openV, path.join(openF, 'invalid-missing-shall'), false);
  run(openV, path.join(openF, 'invalid-missing-file'), false);
  run(openV, path.join(openF, 'invalid-no-spec'), false);

  // ── Code Audit Rigor: finding ──────────────────────────────────────────────
  console.log('\n## Code Audit Rigor — finding validator');
  const carF = P('plugins/code-audit-rigor/tests/fixtures/code-audit-rigor');
  const findV = P('plugins/code-audit-rigor/validators/validate-finding.cjs');
  run(findV, path.join(carF, 'finding-valid.json'), true);
  run(findV, path.join(carF, 'finding-invalid-no-crossrefs.json'), false);
  run(findV, path.join(carF, 'finding-invalid-crossref-incomplete.json'), false);
  run(findV, path.join(carF, 'finding-invalid-bad-security.json'), false);
  run(findV, path.join(carF, 'finding-invalid-empty-crossrefs.json'), false);
  run(findV, path.join(carF, 'finding-invalid-bad-decision.json'), false);
  run(findV, path.join(carF, 'finding-invalid-bad-confidence.json'), false);

  // ── Code Audit Rigor: review-branch-results ────────────────────────────────
  console.log('\n## Code Audit Rigor — review-branch-results validator');
  const rbV = P('plugins/code-audit-rigor/validators/validate-review-branch-results.cjs');
  run(rbV, path.join(carF, 'review-branch-valid.json'), true);
  run(rbV, path.join(carF, 'review-branch-invalid-skip-no-reason.json'), false);
  run(rbV, path.join(carF, 'review-branch-invalid-noninteger-line.json'), false);
  // 2.0.1: scope = committed ∪ working-tree ∪ untracked; each scoped file carries `source`.
  run(rbV, path.join(carF, 'review-branch-valid-working-tree.json'), true);
  run(rbV, path.join(carF, 'review-branch-invalid-bad-source.json'), false);
  // 2.1.0: round memory — `introduced` is required on every suggestion, and an anchor dismissed in an
  // EARLIER round cannot be posted again (a same-round dismissed entry is this round's own FAIL verdict).
  run(rbV, path.join(carF, 'review-branch-valid-round2.json'), true);
  run(rbV, path.join(carF, 'review-branch-invalid-reposted-dismissed.json'), false);
  // Look entries up by path, not by index, so a reordered fixture cannot silently retarget a mutation.
  const rbEntry = (o, file) => {
    const e = o.scopedFiles.find(f => f.file === file);
    if (!e) throw new Error(`review-branch-valid-working-tree.json drifted: no scopedFiles entry for ${file}`);
    return e;
  };
  runMutations(rbV, path.join(carF, 'review-branch-valid-working-tree.json'), 'review-branch-results', [
    { label: 'scopedFiles.source outside enum', mutate: o => { rbEntry(o, 'src/export.ts').source = 'staged'; } },
    { label: 'scopedFiles.source wrong type', mutate: o => { rbEntry(o, 'src/utils/csv.ts').source = 3; } },
    { label: 'scopedFiles entry loses source', mutate: o => { delete rbEntry(o, 'src/utils/csv-escape.ts').source; } },
    { label: 'suggestion loses introduced (2.1.0: required)', mutate: o => { delete o.suggestions[0].introduced; } },
    { label: 'suggestion introduced not boolean', mutate: o => { o.suggestions[0].introduced = 'yes'; } },
    { label: 'verification.suggestion out of range', mutate: o => { o.verifications[0].suggestion = 7; } },
  ]);
  runMutations(rbV, path.join(carF, 'review-branch-valid-round2.json'), 'review-branch-results (round memory)', [
    { label: 'round 0', mutate: o => { o.round = 0; } },
    { label: 'scopeMode outside enum', mutate: o => { o.scopeMode = 'partial'; } },
    { label: 'dismissed entry missing quotedCode', mutate: o => { delete o.dismissed[0].quotedCode; } },
    { label: 'dismissed entry round 0', mutate: o => { o.dismissed[0].round = 0; } },
    { label: 'carried entry missing round', mutate: o => { delete o.carried[0].round; } },
    { label: 'risk.tier outside enum', mutate: o => { o.risk.tier = 'critical'; } },
    { label: 'risk.hits not an array', mutate: o => { o.risk.hits = 'x'; } },
    { label: 'class empty string', mutate: o => { o.suggestions[0].class = ''; } },
    { label: 'blob empty string', mutate: o => { o.scopedFiles[0].blob = ''; } },
    { label: 'unchangedSince 0', mutate: o => { o.scopedFiles[1].unchangedSince = 0; } },
    { label: 'verification.suggestion negative', mutate: o => { o.verifications[0].suggestion = -1; } },
    { label: 'an anchor dismissed in an earlier round is posted again', mutate: o => { o.suggestions.push({ ...o.suggestions[0], file: o.dismissed[0].file, quotedCode: o.dismissed[0].quotedCode }); } },
    // 2.1.1: a dismissal binds only while the file keeps the blob it had when dismissed. The fixture
    // re-posts a deploy.yml anchor whose round-1 dismissal blob differs from the file's current blob
    // (valid); making the two equal, or dropping the blob, turns that same re-post into a violation.
    { label: 'a re-posted anchor whose dismissal blob equals the current blob', mutate: o => { const d = o.dismissed.find(x => x.file === '.github/workflows/deploy.yml'); d.blob = o.scopedFiles.find(f => f.file === '.github/workflows/deploy.yml').blob; } },
    { label: 'a re-posted anchor whose dismissal has no blob (binds)', mutate: o => { delete o.dismissed.find(x => x.file === '.github/workflows/deploy.yml').blob; } },
    { label: 'a re-posted anchor on a file with no current blob (binds)', mutate: o => { delete o.scopedFiles.find(f => f.file === '.github/workflows/deploy.yml').blob; } },
    { label: 'dismissed blob empty string', mutate: o => { o.dismissed.find(x => x.file === '.github/workflows/deploy.yml').blob = ''; } },
  ]);

  // ── Code Audit Rigor: review-pr-comments ──────────────────────────────────
  console.log('\n## Code Audit Rigor — review-pr-comments validator');
  const prV = P('plugins/code-audit-rigor/validators/validate-review-pr-comments.cjs');
  run(prV, path.join(carF, 'review-pr-comments-valid.json'), true);
  run(prV, path.join(carF, 'review-pr-comments-valid-block.json'), true);
  run(prV, path.join(carF, 'review-pr-comments-invalid-block-no-rationale.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-fix-no-evidence.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-missing-endpoint.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-negative-prnumber.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-skip-no-rationale.json'), false);

  // ── Code Audit Rigor: coverage-reconcile ──────────────────────────────────
  console.log('\n## Code Audit Rigor — coverage-reconcile validator');
  const covV = P('plugins/code-audit-rigor/validators/coverage-reconcile.cjs');
  run(covV, path.join(carF, 'coverage-reconcile-valid.json'), true);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-duplicate.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-missing-status.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-skip-no-reason.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-suggestion-no-file.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-scoped-no-file.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-empty-scoped.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-not-array.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-unknown-status.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-unaccounted.json'), false);

  // ── Security Audit (vendored) ──────────────────────────────────────────────
  // Smoke coverage for the vendored cloudflare/security-audit-skill validator.
  // NOTE: no schema↔validator consistency check here — validate-findings.cjs is a
  // runtime-generic schema interpreter with no `*_ENUM` constants to compare, so the
  // drift checker (which parses those constants) does not apply. Fixtures + single-field
  // mutations guard against the vendored file or Node behavior drifting on re-vendor.
  // Upstream's own suites (validate-findings + validate-coverage-ledger) run separately
  // via plugins/security-audit/tests/upstream.test.sh.
  console.log('\n## Security Audit — findings validator (vendored)');
  const saV = P('plugins/security-audit/skills/security-audit/validate-findings.cjs');
  const saF = P('plugins/security-audit/tests/fixtures/security-audit');
  run(saV, path.join(saF, 'valid-basic.json'), true);
  // Look records up by verdict, not by index: inserting a record shifts every index
  // after it, and an index-based mutation then lands on a different record. The 2.0.0
  // fixture put needs_validation at [1], so `delete o[1].reason` deleted nothing (the
  // suite caught that one: the object stayed valid). `expect` pins the rule each
  // mutation must trip, which also catches a misaimed mutation that still exits non-zero.
  const saRec = (o, verdict) => {
    const e = o.find(f => f.verdict === verdict);
    if (!e) throw new Error(`security-audit valid-basic.json drifted: no ${verdict} record`);
    return e;
  };
  runMutations(saV, path.join(saF, 'valid-basic.json'), 'security-audit-findings', [
    { label: 'confirmed missing title', expect: /missing required field "title"/, mutate: o => { delete saRec(o, 'confirmed').title; } },
    { label: 'confirmed missing fingerprint', expect: /missing required field "fingerprint"/, mutate: o => { delete saRec(o, 'confirmed').fingerprint; } },
    { label: 'confirmed missing evidence', expect: /missing required field "evidence"/, mutate: o => { delete saRec(o, 'confirmed').evidence; } },
    { label: 'confirmed bad overall_severity enum', expect: /overall_severity: invalid value "SEV"/, mutate: o => { saRec(o, 'confirmed').severity.overall_severity = 'SEV'; } },
    { label: 'bad verdict discriminator', expect: /must match exactly one schema in oneOf; matched 0/, mutate: o => { saRec(o, 'confirmed').verdict = 'maybe'; } },
    { label: 'confirmed missing execution', expect: /missing required field "execution"/, mutate: o => { delete saRec(o, 'confirmed').execution; } },
    { label: 'confirmed pre-2.0.0 expected_result instead of observed_result', expect: /execution: unexpected field "expected_result"/, mutate: o => { const x = saRec(o, 'confirmed').execution; x.expected_result = x.observed_result; delete x.observed_result; } },
    { label: 'overall_severity above demonstrated impact (semantic)', expect: /cannot exceed demonstrated impact/, mutate: o => { saRec(o, 'confirmed').severity.impact.score = 'medium'; } },
    { label: 'trace first step not entrypoint (semantic)', expect: /trace\[0\]\.kind: must be "entrypoint"/, mutate: o => { saRec(o, 'confirmed').trace[0].kind = 'propagation'; } },
    { label: 'trace last step not sink (semantic)', expect: /\.kind: must be "sink"/, mutate: o => { const t = saRec(o, 'confirmed').trace; t[t.length - 1].kind = 'propagation'; } },
    { label: 'evidence path not repository-relative (semantic)', expect: /must be a safe repository-relative source path/, mutate: o => { saRec(o, 'confirmed').evidence[0].file = '/etc/passwd'; } },
    { label: 'needs_validation carries a severity', expect: /needs_validation finding must not contain "severity"/, mutate: o => { saRec(o, 'needs_validation').severity = saRec(o, 'confirmed').severity; } },
    { label: 'needs_validation missing blockers', expect: /missing required field "blockers"/, mutate: o => { delete saRec(o, 'needs_validation').blockers; } },
    { label: 'rejected missing reason', expect: /missing required field "reason"/, mutate: o => { delete saRec(o, 'rejected').reason; } },
    // needs_validation, not rejected: fingerprints must also be sorted, and the adjacent
    // record taking the confirmed fingerprint keeps the order valid, so only the
    // duplicate rule fires.
    { label: 'duplicate fingerprint across records (semantic)', expect: /fingerprint: duplicate of/, mutate: o => { saRec(o, 'needs_validation').fingerprint = saRec(o, 'confirmed').fingerprint; } },
  ]);

  // ── Long-tail required-field / type / enum coverage (generated mutations) ────
  console.log('\n## Required-field / type / enum coverage (single-field mutations off valid bases)');

  runMutations(debateV, path.join(debateF, 'valid-basic.json'), 'debate-output', [
    { label: 'delete metadata', mutate: o => { delete o.metadata; } },
    { label: 'metadata.sessionId empty', mutate: o => { o.metadata.sessionId = ''; } },
    { label: 'requirement empty', mutate: o => { o.requirement = ''; } },
    { label: 'proposals empty', mutate: o => { o.proposals = []; } },
    { label: 'proposal missing id', mutate: o => { delete o.proposals[0].id; } },
    { label: 'proposal missing source', mutate: o => { delete o.proposals[0].source; } },
    { label: 'proposal missing title', mutate: o => { delete o.proposals[0].title; } },
    { label: 'proposal missing summary', mutate: o => { delete o.proposals[0].summary; } },
    { label: 'proposal missing rationale', mutate: o => { delete o.proposals[0].rationale; } },
    { label: 'proposal missing scores', mutate: o => { delete o.proposals[0].scores; } },
    { label: 'criticism missing proposalId', mutate: o => { delete o.critiqueRounds[0].criticisms[0].proposalId; } },
    { label: 'criticism missing issue', mutate: o => { delete o.critiqueRounds[0].criticisms[0].issue; } },
    { label: 'consensus.summary empty', mutate: o => { o.consensus.summary = ''; } },
    { label: 'consensus.agreedProposals not array', mutate: o => { o.consensus.agreedProposals = 'x'; } },
    { label: 'finalDecision missing selectedProposal', mutate: o => { delete o.finalDecision.selectedProposal; } },
    { label: 'finalDecision missing reasoning', mutate: o => { delete o.finalDecision.reasoning; } },
    { label: 'delete validation', mutate: o => { delete o.validation; } },
    { label: 'selectedProposal not in proposals (cross-ref)', mutate: o => { o.finalDecision.selectedProposal = 'p9'; } },
    { label: 'agreedProposals references unknown proposal (cross-ref)', mutate: o => { o.consensus.agreedProposals = ['p9']; } },
    { label: 'delete coverage', mutate: o => { delete o.coverage; } },
    { label: 'coverage.covered not array', mutate: o => { o.coverage.covered = 'x'; } },
    { label: 'coverage.covered missing aspect', mutate: o => { delete o.coverage.covered[0].aspect; } },
    { label: 'coverage.notCovered missing reason', mutate: o => { delete o.coverage.notCovered[0].reason; } },
  ]);

  runMutations(findV, path.join(carF, 'finding-valid.json'), 'finding', [
    { label: 'severity bad enum', mutate: o => { o.severity = 'SEV'; } },
    { label: 'confidence out of range', mutate: o => { o.confidence = 150; } },
    { label: 'ev not number', mutate: o => { o.ev = 'high'; } },
    { label: 'decision bad enum', mutate: o => { o.decision = 'MAYBE'; } },
    { label: 'crossRef missing file', mutate: o => { delete o.crossReferences[0].file; } },
    { label: 'crossRef missing lines', mutate: o => { delete o.crossReferences[0].lines; } },
  ]);

  runMutations(rbV, path.join(carF, 'review-branch-valid.json'), 'review-branch-results', [
    { label: 'branch empty', mutate: o => { o.branch = ''; } },
    { label: 'scopedFiles empty', mutate: o => { o.scopedFiles = []; } },
    { label: 'scopedFile missing file', mutate: o => { delete o.scopedFiles[0].file; } },
    { label: 'scopedFile bad status', mutate: o => { o.scopedFiles[0].status = 'wip'; } },
    { label: 'suggestion missing quotedCode', mutate: o => { delete o.suggestions[0].quotedCode; } },
    { label: 'suggestion missing description', mutate: o => { delete o.suggestions[0].description; } },
    { label: 'suggestion bad severity', mutate: o => { o.suggestions[0].severity = 'SEV'; } },
    { label: 'verification missing id', mutate: o => { delete o.verifications[0].id; } },
    { label: 'verification bad verdict', mutate: o => { o.verifications[0].verdict = 'MAYBE'; } },
  ]);

  runMutations(prV, path.join(carF, 'review-pr-comments-valid.json'), 'review-pr-comments', [
    { label: 'comments not array', mutate: o => { o.comments = 'x'; } },
    { label: 'comment missing id', mutate: o => { delete o.comments[0].id; } },
    { label: 'comment missing author', mutate: o => { delete o.comments[0].author; } },
    { label: 'comment missing body', mutate: o => { delete o.comments[0].body; } },
    { label: 'comment bad classification', mutate: o => { o.comments[0].classification = 'weird'; } },
    { label: 'comment bad decision', mutate: o => { o.comments[0].decision = 'maybe'; } },
  ]);

  runMutations(priorV, path.join(priorF, 'valid-prior-debate.json'), 'prior-debate', [
    { label: 'validatorVerdict bad enum', mutate: o => { o.validatorVerdict = 'APPROVED'; } },
    { label: 'priorDecision.confidenceLevel bad enum', mutate: o => { o.priorDecision.confidenceLevel = 'VERY_HIGH'; } },
    { label: 'priorDecision missing selectedProposal', mutate: o => { delete o.priorDecision.selectedProposal; } },
    { label: 'unresolvedRisks bad severity', mutate: o => { o.unresolvedRisks[0].severity = 'blocker'; } },
    { label: 'rejectedAlternatives missing proposal', mutate: o => { delete o.rejectedAlternatives[0].proposal; } },
    { label: 'coverage.covered missing aspect', mutate: o => { delete o.coverage.covered[0].aspect; } },
    { label: 'coverage.notCovered missing reason', mutate: o => { delete o.coverage.notCovered[0].reason; } },
    { label: 'priorDecision missing reasoning', mutate: o => { delete o.priorDecision.reasoning; } },
    { label: 'rejectedAlternatives missing rejectionReason', mutate: o => { delete o.rejectedAlternatives[0].rejectionReason; } },
    { label: 'unresolvedRisks missing description', mutate: o => { delete o.unresolvedRisks[0].description; } },
    { label: 'coverage.covered missing summary', mutate: o => { delete o.coverage.covered[0].summary; } },
    { label: 'coverage.notCovered missing aspect', mutate: o => { delete o.coverage.notCovered[0].aspect; } },
    { label: 'priorDecision not an object', mutate: o => { o.priorDecision = 'x'; } },
    { label: 'rejectedAlternatives not an array', mutate: o => { o.rejectedAlternatives = 'x'; } },
    { label: 'unresolvedRisks not an array', mutate: o => { o.unresolvedRisks = 'x'; } },
    { label: 'coverage not an object', mutate: o => { o.coverage = 'x'; } },
    { label: 'coverage.covered not an array', mutate: o => { o.coverage.covered = 'x'; } },
    { label: 'coverage.notCovered not an array', mutate: o => { o.coverage.notCovered = 'x'; } },
    { label: 'rejectedAlternatives item is null', mutate: o => { o.rejectedAlternatives = [null]; } },
  ]);

  // ── Schema ↔ validator consistency (makes the schema a live, checked layer) ──
  console.log('\n## Schema ↔ validator consistency (enum/pattern drift detection)');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/finding.schema.json')], findV, 'finding');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/review-branch-results.schema.json')], rbV, 'review-branch-results');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/review-pr-comments.schema.json')], prV, 'review-pr-comments');
  checkSchemaConsistency([P('plugins/multi-agent-debate/schema/debate-output.schema.json')], debateV, 'debate-output');
  checkSchemaConsistency([P('plugins/multi-agent-debate/schema/prior-debate.schema.json')], priorV, 'prior-debate');

  // ── Sandbox write-protection of the hook's executed closure ──────────────────
  // LAST on purpose: `spawned` is only complete once every validator above has run.
  console.log('\n## Sandbox — denyWrite covers everything the local hook executes');
  {
    const label = 'every file the out-of-sandbox hook executes is covered by sandbox.filesystem.denyWrite';
    const rel = (abs) => path.relative(ROOT, abs).split(path.sep).join('/');
    const settingsFile = P('.claude', 'settings.json');
    let settings;
    try { settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8')); } catch (e) { settings = e; }
    if (settings instanceof Error) {
      expectNoProblems(label, [`cannot read ${rel(settingsFile)} — ${settings.message}`]);
    } else {
      const problems = [];
      // 1. what the harness runs directly: the script(s) named by each command hook.
      const hookScripts = [];
      let commandHooks = 0;
      const events = settings && typeof settings.hooks === 'object' && settings.hooks !== null ? Object.values(settings.hooks) : [];
      for (const groups of events) {
        for (const group of Array.isArray(groups) ? groups : []) {
          for (const h of Array.isArray(group && group.hooks) ? group.hooks : []) {
            if (!h || h.type !== 'command' || typeof h.command !== 'string') continue;
            commandHooks++;
            // Fail closed, and keep a script that does not exist yet (see hookScriptOf).
            const r = hookScriptOf(h.command);
            if (r.problem) problems.push(r.problem); else hookScripts.push(r.script);
          }
        }
      }
      if (commandHooks === 0) {
        // Says only what was checked: other settings keys (statusLine.command, apiKeyHelper, …) and
        // .mcp.json also launch processes outside the sandbox and are NOT examined here.
        expectNoProblems(`${label} (no command hooks in ${rel(settingsFile)} — this check had nothing to verify)`, []);
      } else {
        // 2. what that hook goes on to execute. scripts/hooks/validate-on-plugin-edit.cjs spawns this
        //    runner and every plugins/*/tests/*.test.sh; the suites invoke the plugin hook scripts;
        //    this runner spawns the validators recorded in `spawned`. That the hook spawns exactly
        //    those is knowledge written down here, not derived — change the hook, change this.
        const pluginSide = enumerateHookExecuted(ROOT);
        problems.push(...pluginSide.problems);
        const executed = new Set([...hookScripts, rel(__filename), ...[...spawned].map(rel), ...pluginSide.files]);
        const fsCfg = settings.sandbox && settings.sandbox.filesystem;
        const patterns = fsCfg && Array.isArray(fsCfg.denyWrite) ? fsCfg.denyWrite : [];
        expectNoProblems(`${label} (${executed.size} files)`, [...problems, ...denyWriteProblems([...executed].sort(), patterns)]);
      }
    }
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log(`\n=== Summary: ${passed} passed, ${failed} failed ===`);
  if (failed > 0) {
    console.error('\nFailed checks:');
    failures.forEach(f => console.error(`  - ${f}`));
    process.exit(1);
  }
  console.log('All fixture checks passed.');
  process.exit(0);
}

main();
