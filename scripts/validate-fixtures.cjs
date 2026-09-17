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

// ── helpers ───────────────────────────────────────────────────────────────────

/** Run a validator against a fixture; assert exit code matches expectation. */
function run(validator, fixture, expectValid) {
  const label = `${path.relative(ROOT, validator)} ← ${path.relative(ROOT, fixture)}`;
  if (!fs.existsSync(validator)) {
    console.error(`  ✗  ${label}: validator not found`);
    failed++;
    failures.push(label);
    return;
  }
  // Fail fast on a missing fixture regardless of expectValid. Without this, an
  // expected-invalid case would pass spuriously: the validator exits non-zero
  // simply because it cannot read the fixture, masking the missing test case.
  if (!fs.existsSync(fixture)) {
    console.error(`  ✗  ${label}: fixture not found`);
    failed++;
    failures.push(label);
    return;
  }
  let exitCode = 0;
  try {
    execFileSync(process.execPath, [validator, fixture], { stdio: 'pipe' });
    exitCode = 0;
  } catch (e) {
    exitCode = typeof e.status === 'number' ? e.status : 1;
  }
  const ok = expectValid ? exitCode === 0 : exitCode !== 0;
  if (ok) {
    console.log(`  ✓  ${label}`);
    passed++;
  } else {
    const expected = expectValid ? 'exit 0 (VALID)' : 'exit non-zero (INVALID)';
    console.error(`  ✗  ${label}`);
    console.error(`     expected ${expected}, got exit ${exitCode}`);
    failed++;
    failures.push(label);
  }
}

let tmpCounter = 0;

/**
 * Run a validator CLI against an in-memory object via a temp file. Returns the exit
 * code (0, or the process's non-zero status). THROWS for spawn/setup failures (write
 * error, validator missing/uncallable) — the caller MUST treat a throw as a harness
 * error, never as a validator rejection (that was the old fail-open).
 */
function execValidatorOnObject(validator, obj) {
  const tmp = path.join(os.tmpdir(), `validate-fixtures-mut-${process.pid}-${tmpCounter++}.json`);
  // Write OUTSIDE the exit-capturing try: a write failure is a harness/environment
  // error, not a validator rejection — it must propagate, never be scored as a pass.
  fs.writeFileSync(tmp, JSON.stringify(obj));
  try {
    execFileSync(process.execPath, [validator, tmp], { stdio: 'pipe' });
    return 0;
  } catch (e) {
    if (typeof e.status === 'number') return e.status; // validator ran and exited non-zero
    throw e;                                            // could not even execute the validator
  } finally {
    try { fs.unlinkSync(tmp); } catch (e) { /* ignore cleanup errors */ }
  }
}

/**
 * Generator-based coverage for the required-field / type / enum long tail.
 * Loads a KNOWN-VALID base fixture, applies exactly one mutation, and asserts the
 * validator rejects it (exit non-zero). Isolation is guaranteed by construction: a
 * valid base plus a single-field change means a non-zero exit can only come from that
 * field's rule. A validator that cannot be executed (missing / mis-pathed / write
 * failure) is scored as a FAILURE, never a spurious pass.
 */
function runMutations(validator, baseFixture, group, mutations) {
  const rel = path.relative(ROOT, baseFixture);
  if (!fs.existsSync(validator)) {
    console.error(`  ✗  ${group}: validator not found — ${path.relative(ROOT, validator)}`);
    failed++;
    failures.push(group);
    return;
  }
  let base;
  try {
    base = JSON.parse(fs.readFileSync(baseFixture, 'utf8'));
  } catch (e) {
    console.error(`  ✗  ${group}: cannot load valid base ${rel} — ${e.message}`);
    failed++;
    failures.push(group);
    return;
  }
  for (const m of mutations) {
    const obj = JSON.parse(JSON.stringify(base));
    m.mutate(obj);
    const label = `${group} ← mutate: ${m.label}`;
    let exitCode;
    try {
      exitCode = execValidatorOnObject(validator, obj);
    } catch (e) {
      console.error(`  ✗  ${label}: validator could not be executed — ${e.message}`);
      failed++;
      failures.push(label);
      continue;
    }
    if (exitCode !== 0) {
      console.log(`  ✓  ${label}`);
      passed++;
    } else {
      console.error(`  ✗  ${label}: expected rejection (exit non-zero), got exit 0`);
      failed++;
      failures.push(label);
    }
  }
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

function checkSchemaConsistency(schemaPaths, validatorPath, group) {
  const label = `${group} (schema ↔ validator)`;
  const { drift, error } = computeSchemaDrift(schemaPaths, validatorPath);
  if (error) {
    console.error(`  ✗  ${label}: ${error}`);
    failed++;
    failures.push(label);
    return;
  }
  if (drift.length === 0) {
    console.log(`  ✓  ${label}`);
    passed++;
  } else {
    console.error(`  ✗  ${label}`);
    drift.forEach(d => console.error(`     - ${d}`));
    failed++;
    failures.push(label);
  }
}

// ── repo-structure gates (plugin layout + version bookkeeping) ────────────────
//
// Both are pure: they take a directory / parsed data and return a list of problem
// strings, so the self-test canaries can feed them a planted defect without touching
// the real repo.

/**
 * A plugin's `commands/<X>.md` and a skill whose effective name is `<X>` resolve to the
 * same qualified name `<plugin>:<X>`; the command shadows the skill and the skill body
 * never loads (session-reflect 1.0.0 shipped exactly this; `claude plugin validate`
 * does not catch it). Effective skill name = SKILL.md frontmatter `name`, else dir name.
 */
function findCommandSkillCollisions(pluginDir) {
  const ls = (d) => (fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }) : []);
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
    const heads = [...text.matchAll(/^## \[([^\]]+)\]/gm)].map((m) => m[1]);
    if (heads.length === 0) { problems.push(`${label}: no "## [x.y.z]" heading`); continue; }
    if (heads[0] !== meta) problems.push(`${label}: top heading [${heads[0]}] != marketplace metadata.version ${meta}`);
    for (let i = 0; i < heads.length; i++) {
      if (!SEMVER.test(heads[i])) { problems.push(`${label}: heading [${heads[i]}] is not x.y.z`); continue; }
      if (i > 0 && SEMVER.test(heads[i - 1]) && cmpSemver(heads[i - 1], heads[i]) <= 0) {
        problems.push(`${label}: heading [${heads[i - 1]}] is followed by [${heads[i]}] (must be strictly decreasing, no duplicates)`);
      }
    }
  }
  return problems;
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
  {
    // (a) consistency gate MUST report drift for a deliberately mismatched schema/validator pair.
    const { drift, error } = computeSchemaDrift(
      [P('plugins/code-audit-rigor/schema/finding.schema.json')],
      P('plugins/multi-agent-debate/validators/validate-debate-output.cjs'),
    );
    const label = 'canary: consistency gate detects a mismatched schema/validator pair';
    if (!error && Array.isArray(drift) && drift.length > 0) { console.log(`  ✓  ${label}`); passed++; }
    else { console.error(`  ✗  ${label}: gate did NOT report drift (error=${error || 'none'})`); failed++; failures.push(label); }
  }
  {
    // (b) mutation harness discrimination: a no-op (still-valid) object → exit 0 (the
    //     harness scores exit 0 as FAILURE), and a real single-field mutation → non-zero.
    const findV0 = P('plugins/code-audit-rigor/validators/validate-finding.cjs');
    const base = JSON.parse(fs.readFileSync(P('plugins/code-audit-rigor/tests/fixtures/code-audit-rigor/finding-valid.json'), 'utf8'));
    const noop = 'canary: no-op mutation leaves object valid (exit 0 → harness flags as non-rejection)';
    const real = 'canary: a real single-field mutation is rejected (exit non-zero)';
    try {
      const okExit = execValidatorOnObject(findV0, base);
      if (okExit === 0) { console.log(`  ✓  ${noop}`); passed++; }
      else { console.error(`  ✗  ${noop}: expected exit 0, got ${okExit}`); failed++; failures.push(noop); }
    } catch (e) { console.error(`  ✗  ${noop}: ${e.message}`); failed++; failures.push(noop); }
    try {
      const bad = JSON.parse(JSON.stringify(base)); bad.severity = 'NOT-A-SEVERITY';
      const badExit = execValidatorOnObject(findV0, bad);
      if (badExit !== 0) { console.log(`  ✓  ${real}`); passed++; }
      else { console.error(`  ✗  ${real}: expected non-zero, got 0`); failed++; failures.push(real); }
    } catch (e) { console.error(`  ✗  ${real}: ${e.message}`); failed++; failures.push(real); }
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
      if (findCommandSkillCollisions(path.join(tmp, 'bad')).length === 1) { console.log(`  ✓  ${planted}`); passed++; }
      else { console.error(`  ✗  ${planted}: planted collision NOT reported`); failed++; failures.push(planted); }
      if (findCommandSkillCollisions(path.join(tmp, 'clean')).length === 0) { console.log(`  ✓  ${quiet}`); passed++; }
      else { console.error(`  ✗  ${quiet}: false positive`); failed++; failures.push(quiet); }
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
      if (got === want) { console.log(`  ✓  ${label}`); passed++; }
      else { console.error(`  ✗  ${label}: expected ${want} problem(s), got ${got}`); failed++; failures.push(label); }
    }
  }

  // ── Repo structure ───────────────────────────────────────────────────────────
  console.log('\n## Repo structure — command/skill name collisions + version bookkeeping');
  {
    const pluginDirs = fs.readdirSync(P('plugins'), { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name);
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
    // Resolve each entry's manifest through its own `source`, not by assuming dir name === entry
    // name, so "no plugin.json found" means what it says. Object-form sources (git/url) have no
    // local manifest to compare — say so rather than crash in path.resolve.
    const pluginVersions = {};
    for (const entry of (marketplace && marketplace.plugins) || []) {
      if (typeof entry.source !== 'string') { loadErrors.push(`marketplace entry "${entry.name}": non-path source, version not checkable here`); continue; }
      const manifest = path.resolve(ROOT, entry.source, '.claude-plugin', 'plugin.json');
      if (!fs.existsSync(manifest)) continue; // versionProblems reports the missing manifest
      const parsed = load(manifest, JSON.parse);
      if (parsed !== undefined) pluginVersions[entry.name] = parsed.version;
    }
    // Never feed partial data to versionProblems: a missing marketplace would make it report
    // nothing (a misleading green) and a missing manifest would cascade into a second, wrong message.
    expectNoProblems(versionLabel, loadErrors.length > 0 ? loadErrors : versionProblems(marketplace, pluginVersions, changelogs));
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
  console.log('\n## Security Audit — findings validator (vendored)');
  const saV = P('plugins/security-audit/skills/security-audit/validate-findings.cjs');
  const saF = P('plugins/security-audit/tests/fixtures/security-audit');
  run(saV, path.join(saF, 'valid-basic.json'), true);
  runMutations(saV, path.join(saF, 'valid-basic.json'), 'security-audit-findings', [
    { label: 'confirmed missing title', mutate: o => { delete o[0].title; } },
    { label: 'confirmed bad overall_severity enum', mutate: o => { o[0].severity.overall_severity = 'SEV'; } },
    { label: 'bad verdict discriminator', mutate: o => { o[0].verdict = 'maybe'; } },
    { label: 'confirmed missing execution', mutate: o => { delete o[0].execution; } },
    { label: 'trace first step not entrypoint (semantic)', mutate: o => { o[0].trace[0].kind = 'propagation'; } },
    { label: 'trace last step not sink (semantic)', mutate: o => { o[0].trace[o[0].trace.length - 1].kind = 'propagation'; } },
    { label: 'rejected missing reason', mutate: o => { delete o[1].reason; } },
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
