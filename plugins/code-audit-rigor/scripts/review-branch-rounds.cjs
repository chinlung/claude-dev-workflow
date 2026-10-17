#!/usr/bin/env node
'use strict';

/**
 * review-branch-rounds — the cross-round memory of /review-branch (2.1.0).
 *
 * A re-review after fixes used to re-read the whole scope, regenerate the same suggestions,
 * re-verify each one with a fresh sub-agent, and could re-post a finding already dismissed as a
 * false positive — which an agent author then "fixes", costing another commit and another round.
 * Most of what a reviewer flags on round N+1 was already there on round 1. This script makes the
 * two halves of convergence mechanical, so neither depends on the reviewer remembering:
 *
 *   plan      before Phase 1. Reads the previous round's results file (same branch), hashes every
 *             scoped file, and reports: `unchanged` (byte-identical to a file the previous round
 *             reviewed → skip it), `carried` (verified-but-unfixed suggestions on unchanged files →
 *             report, do not re-verify), `dismissed` (anchors judged false positives in earlier
 *             rounds → must not be proposed again), the round number and the scope mode. Written to
 *             <gitdir>/review-branch-plan.json so `annotate` finds it after the results file has been
 *             overwritten (`--no-write` prints only; pass the saved JSON to `annotate --plan`).
 *   annotate  after Phase 2. Fills `introduced` on every suggestion (is its line inside this
 *             change? — committed branch diff ∪ working tree ∪ untracked; whole-file, binary and
 *             untracked changes count), `blob` and `unchangedSince` on every scoped file, `round`,
 *             `scopeMode`, `dismissed` (previous ∪ this round's FAIL verdicts), `carried`, and `risk`
 *             (from resolve-rules when present); REFUSES to write a results file that re-posts an
 *             anchor dismissed in an earlier round, or that skips a file as "unchanged" the plan did
 *             not report as such.
 *
 *   node review-branch-rounds.cjs plan --root <repo> --files <list|-> [--base <sha>] [--full] [--previous <json>]
 *   node review-branch-rounds.cjs annotate <results.json> --root <repo> --base <sha> [--plan <json>] [--rules <json>]
 *
 * Exit 0 on success; 1 when `annotate` refuses (re-posted dismissed anchor); 2 on usage / IO errors.
 * Zero dependencies. The diff parsing mirrors scope-ledger's scope-facts.cjs on purpose (same author,
 * same conventions) but is not shared: plugins install independently.
 */

const cp = require('child_process');
const fs = require('fs');
const path = require('path');

const PLAN_FILE = 'review-branch-plan.json';
const RULES_FILE = 'review-branch-rules.json';
const RESULTS_FILE = 'review-branch-results.json';
// The skipReason the command writes for a file that `plan` reported as unchanged.
const UNCHANGED_SKIP_RE = /^unchanged since r\d+ \(blob match\)/;

function die(msg, code = 2) {
  process.stderr.write(`review-branch-rounds: ${msg}\n`);
  process.exit(code);
}

function git(root, args, opts = {}) {
  const r = cp.spawnSync('git', ['-C', root, '-c', 'core.fsmonitor=false', '-c', 'core.quotePath=false', ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.error) throw r.error;
  if (r.status !== 0 && !(opts.ok || []).includes(r.status)) {
    const err = new Error((r.stderr || '').trim() || `git ${args.join(' ')} exited ${r.status}`);
    err.status = r.status;
    throw err;
  }
  return r.stdout;
}

function parseArgs(list) {
  const opts = { _: [] };
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a === '--full' || a === '--no-write') { opts[a.slice(2)] = true; continue; }
    if (a.startsWith('--')) {
      const v = list[i + 1];
      if (v === undefined) die(`${a} needs a value`);
      opts[a.slice(2)] = v;
      i++;
      continue;
    }
    opts._.push(a);
  }
  return opts;
}

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; }
}

function repoRoot(dir) {
  try { return git(dir, ['rev-parse', '--show-toplevel']).trim(); } catch (e) { die(`${dir} is not inside a git work tree`); }
  return null;
}

function gitDir(root) {
  const d = git(root, ['rev-parse', '--git-dir']).trim();
  return path.resolve(root, d);
}

function currentBranch(root) {
  return git(root, ['rev-parse', '--abbrev-ref', 'HEAD']).trim();
}

function readList(spec) {
  let text;
  if (spec === '-' || spec === undefined) {
    if (process.stdin.isTTY) die('--files <list> is required (one repo-relative path per line, or - for stdin)');
    text = fs.readFileSync(0, 'utf8');
  } else {
    try { text = fs.readFileSync(spec, 'utf8'); } catch (e) { die(`cannot read file list ${spec}: ${e.message}`); }
  }
  const seen = new Set();
  const out = [];
  for (const raw of text.split('\n')) {
    const f = raw.trim().replace(/^\.\//, '');
    if (!f || f === RESULTS_FILE || seen.has(f)) continue;
    seen.add(f);
    out.push(f);
  }
  return out;
}

// Content hash of the file as it is on disk — the same identity `git hash-object` gives a blob, so
// an unchanged file produces the same value on every round, tracked or not. A missing file is a
// deletion under review and hashes as the literal "deleted".
function blobOf(root, rel) {
  const abs = path.join(root, rel);
  let st;
  try { st = fs.lstatSync(abs); } catch (e) { return 'deleted'; }
  if (!st.isFile() && !st.isSymbolicLink()) return 'deleted';
  try { return git(root, ['hash-object', '--', rel]).trim(); } catch (e) { return 'deleted'; }
}

const anchorKey = (s) => `${s.file}\u0000${s.quotedCode}`;

function verdictByIndex(results) {
  const m = new Map();
  for (const v of Array.isArray(results.verifications) ? results.verifications : []) {
    if (Number.isInteger(v.suggestion) && v.suggestion >= 0 && !m.has(v.suggestion)) m.set(v.suggestion, v.verdict);
  }
  return m;
}

function mergeDismissed(...lists) {
  const seen = new Map();
  for (const list of lists) {
    for (const d of list || []) {
      if (!d || typeof d.file !== 'string' || typeof d.quotedCode !== 'string') continue;
      const k = anchorKey(d);
      if (!seen.has(k)) seen.set(k, { file: d.file, quotedCode: d.quotedCode, round: Number.isInteger(d.round) ? d.round : 1 });
    }
  }
  return [...seen.values()];
}

// ---------------------------------------------------------------------------------------- plan

function plan(opts) {
  const root = repoRoot(opts.root || process.cwd());
  const files = readList(opts.files);
  if (files.length === 0) die('the file list is empty — nothing to plan');
  const branch = currentBranch(root);
  const previousPath = opts.previous || path.join(root, RESULTS_FILE);
  const previous = readJson(previousPath);
  const sameWork = !!(previous && typeof previous === 'object' && previous.branch === branch && Array.isArray(previous.scopedFiles));
  const prevRound = sameWork ? (Number.isInteger(previous.round) && previous.round >= 1 ? previous.round : 1) : 0;
  const round = prevRound + 1;
  const full = !!opts.full || !sameWork;

  const blobs = files.map((file) => ({ file, blob: blobOf(root, file) }));
  const prevByFile = new Map();
  if (sameWork) for (const e of previous.scopedFiles) if (e && typeof e.file === 'string') prevByFile.set(e.file, e);

  // A file counts as unchanged when the previous round either reviewed it or skipped it BECAUSE it was
  // unchanged — the latter is the `unchangedSince` flag that `annotate` writes from its plan, never the
  // skipReason text (which the reviewer writes and could get wrong). Accepting only `reviewed` made files
  // alternate between skipped and re-reviewed every other round and dropped their carried findings on
  // round 3. A skip for any other reason (docs only, out of focus) is re-decided every round.
  const unchanged = [];
  if (!full) {
    for (const { file, blob } of blobs) {
      const p = prevByFile.get(file);
      if (!p || typeof p.blob !== 'string' || p.blob === '' || p.blob !== blob) continue;
      const settled = p.status === 'reviewed' || (p.status === 'skipped' && Number.isInteger(p.unchangedSince));
      if (settled) unchanged.push(file);
    }
  }
  const unchangedSet = new Set(unchanged);

  let dismissed = [];
  let carried = [];
  if (sameWork) {
    const verdict = verdictByIndex(previous);
    const suggestions = Array.isArray(previous.suggestions) ? previous.suggestions : [];
    const failed = [];
    const passedOnUnchanged = [];
    suggestions.forEach((s, i) => {
      if (!s || typeof s.file !== 'string' || typeof s.quotedCode !== 'string') return;
      const v = verdict.get(i);
      if (v === 'FAIL') failed.push({ file: s.file, quotedCode: s.quotedCode, round: prevRound });
      else if (v === 'PASS' && unchangedSet.has(s.file)) passedOnUnchanged.push({ ...s, round: prevRound });
    });
    dismissed = mergeDismissed(previous.dismissed, failed);
    const prevCarried = (Array.isArray(previous.carried) ? previous.carried : []).filter((c) => c && unchangedSet.has(c.file));
    const seen = new Set();
    for (const c of [...prevCarried, ...passedOnUnchanged]) {
      const k = anchorKey(c);
      if (seen.has(k)) continue;
      seen.add(k);
      carried.push(c);
    }
  }

  const out = {
    root,
    branch,
    base: opts.base || null,
    head: git(root, ['rev-parse', 'HEAD']).trim(),
    round,
    scopeMode: full ? 'full' : 'since-last',
    previous: sameWork ? { path: previousPath, round: prevRound } : null,
    files: blobs,
    unchanged,
    carried,
    dismissed,
  };
  if (!opts['no-write']) {
    const target = path.join(gitDir(root), PLAN_FILE);
    fs.writeFileSync(target, JSON.stringify(out, null, 2) + '\n');
    out.planFile = target;
  }
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
}

// ------------------------------------------------------------------------------------ annotate

// `git diff -U0` → Map(relative path → [{start, count}]) on the new side. The `+++ ` header is read
// only between `diff --git` and the first `@@`: inside a hunk the same prefix is an added line.
function parseDiff(text) {
  const files = new Map();
  let cur = null;
  let inHeader = false;
  for (const line of text.split('\n')) {
    if (line.startsWith('diff --git ')) { cur = null; inHeader = true; continue; }
    if (inHeader && line.startsWith('+++ ')) {
      const p = line.slice(4).replace(/\t$/, '');
      if (p === '/dev/null') { cur = null; continue; }
      cur = p.replace(/^b\//, '');
      if (!files.has(cur)) files.set(cur, []);
      continue;
    }
    if (line.startsWith('@@ ')) {
      inHeader = false;
      if (!cur) continue;
      const m = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line);
      if (!m) continue;
      files.get(cur).push({ start: Number(m[3]), count: m[4] === undefined ? 1 : Number(m[4]) });
    }
  }
  return files;
}

function nameStatus(root, base) {
  const parts = git(root, ['diff', '--name-status', '-z', '--no-renames', '--no-textconv', base, '--', '.']).split('\0');
  const m = new Map();
  for (let i = 0; i + 1 < parts.length; i += 2) if (parts[i] && parts[i + 1]) m.set(parts[i + 1], parts[i][0]);
  return m;
}

// Files git shows as binary (`-` in --numstat): a modified one has status M and no text hunk, exactly
// like a mode-only change, so without numstat the two cannot be told apart. `.gitattributes -diff`
// files (lockfiles, generated files) land here too, and a reviewer does read those.
function binaryFiles(root, base) {
  const bin = new Set();
  for (const rec of git(root, ['diff', '--numstat', '-z', '--no-renames', '--no-textconv', base, '--', '.']).split('\0')) {
    if (!rec) continue;
    const t = rec.split('\t');
    if (t.length >= 3 && (t[0] === '-' || t[1] === '-')) bin.add(t.slice(2).join('\t'));
  }
  return bin;
}

function changeFacts(root, base) {
  const diffText = git(root, ['diff', '-U0', '--no-color', '--no-ext-diff', '--no-textconv', '--no-renames', '--src-prefix=a/', '--dst-prefix=b/', base, '--', '.']);
  const hunks = parseDiff(diffText);
  const status = nameStatus(root, base);
  const binary = binaryFiles(root, base);
  const untracked = new Set(git(root, ['ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean));
  return { hunks, status, binary, untracked };
}

// Introduced = the suggestion points at something this change wrote: a wholly new, deleted, binary or
// rewritten file, or a line inside an added hunk. A line in a changed file but outside every hunk is
// pre-existing — the reviewer read the whole file, and that is exactly the case the tag exists for.
function introducedOf(facts, file, line) {
  if (facts.untracked.has(file)) return true;
  const st = facts.status.get(file);
  if (st === 'A' || st === 'D') return true;
  if (st && facts.binary.has(file)) return true;
  const h = facts.hunks.get(file);
  if (!h || h.length === 0) return false;
  if (!Number.isInteger(line)) return true; // the diff touched the file and the suggestion names no line
  return h.some((x) => x.count > 0 && line >= x.start && line <= x.start + x.count - 1);
}

function annotate(opts) {
  const resultsPath = opts._[0];
  if (!resultsPath) die('annotate needs the results file: annotate <results.json> --root <repo> --base <sha>');
  const root = repoRoot(opts.root || path.dirname(path.resolve(resultsPath)));
  if (!opts.base) die('--base <merge-base sha> is required for annotate (it defines what "introduced" means)');
  let base;
  try { base = git(root, ['rev-parse', '--verify', `${opts.base}^{commit}`]).trim(); } catch (e) { die(`--base ${opts.base} does not resolve to a commit`); }
  const results = readJson(path.resolve(resultsPath));
  if (!results || typeof results !== 'object' || Array.isArray(results)) die(`${resultsPath} is not a JSON object`);
  if (!Array.isArray(results.suggestions) || !Array.isArray(results.scopedFiles)) die(`${resultsPath} lacks suggestions[] / scopedFiles[]`);

  const gd = gitDir(root);
  const planData = readJson(opts.plan || path.join(gd, PLAN_FILE));
  const planOk = !!(planData && typeof planData === 'object' && planData.branch === currentBranch(root));
  const priorDismissed = planOk ? mergeDismissed(planData.dismissed) : [];
  const priorKeys = new Set(priorDismissed.map(anchorKey));

  // Refuse before writing anything: a re-posted dismissed finding is the exact waste this exists to stop.
  const reposted = results.suggestions.filter((s) => s && priorKeys.has(anchorKey(s)));
  if (reposted.length) {
    process.stderr.write(`review-branch-rounds: ${reposted.length} suggestion(s) re-post an anchor dismissed in an earlier round — drop them (or argue the dismissal was wrong in the report, with new evidence):\n`);
    for (const s of reposted) process.stderr.write(`  - ${s.file}:${s.line} ${JSON.stringify(String(s.quotedCode).slice(0, 80))}\n`);
    process.exit(1);
  }

  const facts = changeFacts(root, base);
  for (const s of results.suggestions) {
    if (!s || typeof s.file !== 'string') continue;
    s.introduced = introducedOf(facts, s.file, s.line);
  }

  const planBlob = new Map();
  if (planOk) for (const f of planData.files || []) if (f && typeof f.file === 'string') planBlob.set(f.file, f.blob);
  // The "unchanged" fact is the plan's, not the reviewer's: a scoped file the plan reported unchanged gets
  // `unchangedSince` (the round that last settled it), which the next `plan` reads instead of the
  // skipReason text. A skipReason that CLAIMS unchanged for a file the plan did not report is refused —
  // otherwise a file nobody reviewed could be skipped on every later round on the strength of a sentence.
  const planUnchanged = new Set(planOk && Array.isArray(planData.unchanged) ? planData.unchanged : []);
  const previousRound = planOk && planData.previous && Number.isInteger(planData.previous.round) ? planData.previous.round : null;
  const falseClaims = [];
  for (const e of results.scopedFiles) {
    if (!e || typeof e.file !== 'string') continue;
    e.blob = planBlob.has(e.file) ? planBlob.get(e.file) : blobOf(root, e.file);
    if (planUnchanged.has(e.file)) {
      if (previousRound !== null) e.unchangedSince = previousRound;
    } else {
      delete e.unchangedSince;
      if (e.status === 'skipped' && UNCHANGED_SKIP_RE.test(String(e.skipReason || ''))) falseClaims.push(e.file);
    }
  }
  if (falseClaims.length) {
    process.stderr.write(`review-branch-rounds: ${falseClaims.length} scoped file(s) are skipped as "unchanged since …" but the plan did not report them unchanged — review them (or re-run plan):\n`);
    for (const f of falseClaims) process.stderr.write(`  - ${f}\n`);
    process.exit(1);
  }

  const verdict = verdictByIndex(results);
  const failedNow = [];
  results.suggestions.forEach((s, i) => {
    if (s && verdict.get(i) === 'FAIL' && typeof s.file === 'string' && typeof s.quotedCode === 'string') failedNow.push({ file: s.file, quotedCode: s.quotedCode });
  });
  const round = planOk ? planData.round : (Number.isInteger(results.round) && results.round >= 1 ? results.round : 1);
  results.round = round;
  results.scopeMode = planOk ? planData.scopeMode : (results.scopeMode || 'full');
  results.dismissed = mergeDismissed(priorDismissed, failedNow.map((d) => ({ ...d, round })));
  results.carried = planOk ? (planData.carried || []) : (Array.isArray(results.carried) ? results.carried : []);

  const rules = readJson(opts.rules || path.join(gd, RULES_FILE));
  if (rules && rules.risk && (rules.risk.tier === 'standard' || rules.risk.tier === 'deep')) {
    results.risk = { tier: rules.risk.tier, hits: Array.isArray(rules.risk.hits) ? rules.risk.hits : [] };
  }

  fs.writeFileSync(path.resolve(resultsPath), JSON.stringify(results, null, 2) + '\n');
  const introduced = results.suggestions.filter((s) => s && s.introduced === true).length;
  const summary = {
    round,
    scopeMode: results.scopeMode,
    suggestions: results.suggestions.length,
    introduced,
    preExisting: results.suggestions.length - introduced,
    dismissedTotal: results.dismissed.length,
    dismissedThisRound: failedNow.length,
    carried: results.carried.length,
    risk: results.risk ? results.risk.tier : null,
  };
  process.stdout.write(JSON.stringify(summary) + '\n');
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd === '-h' || cmd === '--help' || !cmd) {
    process.stdout.write('usage: review-branch-rounds.cjs plan --root <repo> --files <list|-> [--base <sha>] [--full] [--previous <json>] [--no-write]\n' +
      '       review-branch-rounds.cjs annotate <results.json> --root <repo> --base <sha> [--plan <json>] [--rules <json>]\n');
    process.exit(cmd ? 0 : 2);
  }
  const opts = parseArgs(rest);
  try {
    if (cmd === 'plan') plan(opts);
    else if (cmd === 'annotate') annotate(opts);
    else die(`unknown subcommand ${cmd}`);
  } catch (e) {
    if (e && e.status !== undefined && e.message) die(`git failed: ${e.message}`);
    throw e;
  }
}

main();
