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
 *   plan      before Phase 1. Reads the previous round's state (same branch), hashes every scoped
 *             file, and reports: `unchanged` (identical in content and mode to a file the previous round reviewed
 *             → skip it), `carried` (verified-but-unfixed suggestions on unchanged files → report,
 *             do not re-verify), `dismissed` (anchors judged false positives in earlier rounds →
 *             must not be proposed again), the round number and the scope mode. Written to
 *             <gitdir>/review-branch-plan.json so `annotate` finds it after the results file has been
 *             overwritten (`--no-write` prints only; pass the saved JSON to `annotate --plan`).
 *             With --base it first refuses (exit 2) a file list naming any path outside the change
 *             (2.1.2): the list is a file the caller wrote, and a shared one was once overwritten by
 *             another session's run on another repository.
 *   annotate  after Phase 2. Fills `introduced` on every suggestion (is its line inside this
 *             change? — committed branch diff ∪ working tree ∪ untracked; whole-file, binary and
 *             untracked changes count), `blob` and `unchangedSince` on every scoped file, `round`,
 *             `scopeMode`, `dismissed` (previous ∪ this round's FAIL verdicts), `carried`, and `risk`
 *             (from resolve-rules when present); REFUSES to write a results file that re-posts an
 *             anchor dismissed in an earlier round, or that skips a file as "unchanged" the plan did
 *             not report as such. Saves a copy of the annotated results to
 *             <gitdir>/review-branch-last.json — the state the next `plan` reads.
 *
 * Where the previous round comes from (2.1.1): <gitdir>/review-branch-last.json, written by
 * `annotate`, or the file named by --previous. Never <root>/review-branch-results.json: the work
 * tree belongs to the branch under review, and a results file shipped with it (under that name or
 * any name a case-folding file system maps to it) would mark the branch's own files unchanged, pre-
 * dismiss the findings it fears and inject text through `carried`. The git dir is not something a
 * branch can write to. When annotate cannot write there (sandbox), it says so and the next plan
 * takes --previous <that results file>.
 *
 *   node review-branch-rounds.cjs plan --root <repo> --files <list|-> [--base <sha>] [--full] [--previous <json>]
 *   node review-branch-rounds.cjs annotate <results.json> --root <repo> --base <sha> [--plan <json>] [--rules <json>]
 *
 * Exit 0 on success; 1 when `annotate` refuses (re-posted dismissed anchor); 2 on usage / IO errors,
 * when `plan` refuses a file list that is not this change's, and when `annotate` refuses its inputs (2.1.3):
 * a results file that is already annotated or written for another branch, or a plan and a rules file that
 * read different file lists. All of those come before anything is written.
 * Zero dependencies. The diff parsing mirrors scope-ledger's scope-facts.cjs on purpose (same author,
 * same conventions) but is not shared: plugins install independently.
 */

const cp = require('child_process');
const fs = require('fs');
const path = require('path');

const PLAN_FILE = 'review-branch-plan.json';
const RULES_FILE = 'review-branch-rules.json';
const LAST_FILE = 'review-branch-last.json';
const RESULTS_FILE = 'review-branch-results.json';
// The skipReason the command writes for a file that `plan` reported as unchanged.
const UNCHANGED_SKIP_RE = /^unchanged since r\d+ \(blob match\)/;

function die(msg, code = 2) {
  process.stderr.write(`review-branch-rounds: ${msg}\n`);
  process.exit(code);
}

function git(root, args, opts = {}) {
  const r = cp.spawnSync('git', ['-C', root, '-c', 'core.fsmonitor=false', '-c', 'core.quotePath=false', ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, input: opts.input });
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

function isAncestor(root, maybeAncestor, commit) {
  const r = cp.spawnSync('git', ['-C', root, '-c', 'core.fsmonitor=false', 'merge-base', '--is-ancestor', maybeAncestor, commit], { encoding: 'utf8' });
  return !r.error && r.status === 0;
}

function resolveCommit(root, rev) {
  try { return git(root, ['rev-parse', '--verify', `${rev}^{commit}`]).trim(); } catch (e) { return null; }
}

function currentBranch(root) {
  return git(root, ['rev-parse', '--abbrev-ref', 'HEAD']).trim();
}

// git C-quotes a path with non-ASCII or special bytes when core.quotePath is on: `"auth/s\303\251.ts"`.
// A list built from such output must be decoded, or the path matches nothing, lstat fails and the file
// hashes as "deleted" on every round. A line without the surrounding quotes is returned as is.
function unquoteC(s) {
  if (s.length < 2 || s[0] !== '"' || s[s.length - 1] !== '"') return s;
  const body = s.slice(1, -1);
  const bytes = [];
  const simple = { n: 10, t: 9, r: 13, a: 7, b: 8, f: 12, v: 11, '\\': 92, '"': 34 };
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c !== '\\') { for (const b of Buffer.from(c, 'utf8')) bytes.push(b); continue; }
    const oct = body.slice(i + 1, i + 4);
    if (/^[0-7]{3}$/.test(oct)) { bytes.push(parseInt(oct, 8)); i += 3; continue; }
    const n = body[i + 1];
    if (n !== undefined && Object.prototype.hasOwnProperty.call(simple, n)) { bytes.push(simple[n]); i += 1; continue; }
    bytes.push(92);
  }
  return Buffer.from(bytes).toString('utf8');
}

function readList(spec) {
  let text;
  if (spec === '-' || spec === undefined) {
    if (process.stdin.isTTY) die('--files <list> is required (one repo-relative path per line, or - for stdin)');
    text = fs.readFileSync(0, 'utf8');
  } else {
    try { text = fs.readFileSync(spec, 'utf8'); } catch (e) { die(`cannot read file list ${spec}: ${e.message}`); }
  }
  // A UTF-8 BOM (some Windows tools write one) is not part of the first file name.
  if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  const seen = new Set();
  const out = [];
  for (const raw of text.split('\n')) {
    // Strip only a CRLF's \r: a leading or trailing space is part of a legal file name, and trimming
    // it made the path match nothing git reports (plan refused the list on every run).
    const line = raw.replace(/\r$/, '');
    if (!line.trim()) continue;
    const f = unquoteC(line).replace(/^\.\//, '');
    if (!f || f === RESULTS_FILE || seen.has(f)) continue;
    seen.add(f);
    out.push(f);
  }
  return out;
}

// Identity of the file as it is on disk, so an unchanged file produces the same value on every round,
// tracked or not. It is the content hash plus the kind git records in the tree entry's mode: git stores
// a regular file and a symlink whose target text equals the file's bytes as ONE blob and tells them apart
// only by mode (100644 / 120000 / 100755). `<hash>` is a regular file, `<hash>+x` an executable one,
// `link:<hash>` a symlink. The hash alone would let a branch turn a file into a link, or make it
// executable, between two rounds and have it skipped as unchanged with its dismissals still in force.
// `--no-filters`: the branch owns `.gitattributes`, and a clean
// filter such as `ident` would hash `$Id: <anything> $` as `$Id$` — an edited file would look
// unchanged and be skipped. A symlink hashes as its raw link target (`hash-object <path>` would
// follow it, and a link to /dev/zero never ends). A missing or special file is a deletion under
// review and hashes as the literal "deleted", which `plan` never treats as unchanged.
function blobOf(root, rel) {
  const abs = path.join(root, rel);
  let st;
  try { st = fs.lstatSync(abs); } catch (e) { return 'deleted'; }
  if (st.isSymbolicLink()) {
    try { return 'link:' + git(root, ['hash-object', '--no-filters', '--stdin'], { input: fs.readlinkSync(abs, { encoding: 'buffer' }) }).trim(); } catch (e) { return 'deleted'; }
  }
  if (!st.isFile()) return 'deleted';
  try { return git(root, ['hash-object', '--no-filters', '--', rel]).trim() + ((st.mode & 0o100) ? '+x' : ''); } catch (e) { return 'deleted'; }
}

const anchorKey = (s) => `${s.file}\u0000${s.quotedCode}`;

function verdictByIndex(results) {
  const m = new Map();
  for (const v of Array.isArray(results.verifications) ? results.verifications : []) {
    if (Number.isInteger(v.suggestion) && v.suggestion >= 0 && !m.has(v.suggestion)) m.set(v.suggestion, v.verdict);
  }
  return m;
}

// A dismissed anchor carries the blob of its file at the time of the dismissal: the verdict was about
// that content. It blocks a re-post only while the file still has that blob; once the file changes,
// the anchor stays in the list as history but no longer stops the reviewer from flagging the line.
// The same anchor dismissed again on new content is a second entry (one per content), so a file that
// changes back to an earlier content is covered by that content's dismissal again.
function mergeDismissed(...lists) {
  const seen = new Map();
  for (const list of lists) {
    for (const d of list || []) {
      if (!d || typeof d.file !== 'string' || typeof d.quotedCode !== 'string') continue;
      const blob = typeof d.blob === 'string' && d.blob ? d.blob : '';
      const k = `${anchorKey(d)}\u0000${blob}`;
      if (!seen.has(k)) {
        const e = { file: d.file, quotedCode: d.quotedCode, round: Number.isInteger(d.round) ? d.round : 1 };
        if (blob) e.blob = blob;
        seen.set(k, e);
      }
    }
  }
  return [...seen.values()];
}

// Does this dismissed anchor still apply to the file as it is now? Without a recorded blob (a
// pre-2.1.1 entry) it is taken to apply.
function dismissalApplies(d, currentBlob) {
  return typeof d.blob !== 'string' || !d.blob || d.blob === currentBlob;
}

// ---------------------------------------------------------------------------------------- plan

// Every path this change touches: committed on the branch (base..HEAD), changed in the work tree
// (base..work tree) and untracked. Both diffs are needed: a committed change reverted in the work tree
// is in the first only, and the command's list includes it.
function changedFiles(root, base) {
  const names = (args) => git(root, args).split('\0').filter(Boolean);
  return new Set([
    ...names(['diff', '--name-only', '-z', '--no-renames', base, 'HEAD', '--', '.']),
    ...names(['diff', '--name-only', '-z', '--no-renames', base, '--', '.']),
    ...names(['ls-files', '--others', '--exclude-standard', '-z']),
  ]);
}

function plan(opts) {
  const root = repoRoot(opts.root || process.cwd());
  const files = readList(opts.files);
  if (files.length === 0) die('the file list is empty — nothing to plan');
  // The list arrives as a file and nothing ties that file to this repository. Local sessions share
  // $TMPDIR: on 2026-10-19 another session's run overwrote a fixed-name list with its own repo's paths
  // mid-review, and plan, resolve-rules and annotate all reported success on it. With --base the
  // change's own file set is computable, so a list naming anything outside it is refused, not planned.
  // A --focus list is a subset and passes.
  if (opts.base) {
    if (!resolveCommit(root, opts.base)) die(`--base ${opts.base} is not a commit in ${root}`);
    const changed = changedFiles(root, opts.base);
    const foreign = files.filter((f) => !changed.has(f));
    if (foreign.length) {
      const shown = foreign.slice(0, 5).join(', ') + (foreign.length > 5 ? `, … (${foreign.length - 5} more)` : '');
      die(`the file list names ${foreign.length} path(s) that are not part of this change against ${opts.base}: ${shown} — rebuild the list from this repository; a shared list file may have been overwritten by another run`);
    }
  }
  const branch = currentBranch(root);
  // The previous round is read from the git dir (see the header), never from the work tree.
  const previousPath = opts.previous || path.join(gitDir(root), LAST_FILE);
  const previous = readJson(previousPath);
  const workTreeResultsIgnored = fs.existsSync(path.join(root, RESULTS_FILE));
  const head = git(root, ['rev-parse', 'HEAD']).trim();
  // Same work = same branch name AND a continuation of the commit the previous round annotated (that
  // head is an ancestor of this one) AND the same base when both are known. A branch name is the
  // branch author's to choose: a later PR checked out under the same name, or any detached review
  // (branch "HEAD"), must not inherit dismissals and skips earned by different code. A rebase or
  // force-push breaks the ancestry and simply starts a full round.
  let previousRejected = null;
  let sameWork = !!(previous && typeof previous === 'object' && previous.branch === branch && Array.isArray(previous.scopedFiles));
  if (sameWork) {
    if (typeof previous.head !== 'string' || !/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/.test(previous.head)) previousRejected = 'no-head'; // SHA-1 or SHA-256 object format
    else if (!isAncestor(root, previous.head, head)) previousRejected = 'not-a-continuation';
    else if (opts.base && typeof previous.base === 'string' && previous.base !== resolveCommit(root, opts.base)) previousRejected = 'different-base';
    if (previousRejected) {
      sameWork = false;
      process.stderr.write(`review-branch-rounds: ${previousPath} is not a previous round of this work (${previousRejected}) — starting a full round without its dismissed/carried\n`);
    }
  }
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
      // "deleted" is the absence of a hash, not a hash: two rounds that both failed to read a file are
      // not evidence that it did not change.
      if (blob === 'deleted' || !p || typeof p.blob !== 'string' || p.blob === '' || p.blob !== blob) continue;
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
    const passedOnUnchanged = [];
    suggestions.forEach((s, i) => {
      if (!s || typeof s.file !== 'string' || typeof s.quotedCode !== 'string') return;
      if (verdict.get(i) === 'PASS' && unchangedSet.has(s.file)) passedOnUnchanged.push({ ...s, round: prevRound });
    });
    // The previous round's FAIL verdicts are already in its `dismissed` (annotate merges them, with the
    // file's blob); nothing to add here.
    dismissed = mergeDismissed(previous.dismissed);
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
    head,
    round,
    scopeMode: full ? 'full' : 'since-last',
    previous: sameWork ? { path: previousPath, round: prevRound, source: opts.previous ? 'explicit' : 'gitdir' } : null,
    previousRejected,
    workTreeResultsIgnored,
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

  // `annotate` takes this round's fresh draft and nothing else. The results file is written by a tool call
  // that can fail (it must have been read first, and annotate itself rewrites it), and annotate used to
  // carry on with whatever was left on disk: on 2026-10-19 it twice annotated and saved as the new round's
  // state a file from an earlier run — another branch's, and one it had already annotated — and the
  // validator and the coverage check passed both. Both refusals come before anything is written.
  if (typeof results.head === 'string' && results.head) {
    die(`${resultsPath} is already annotated (round ${results.round} at ${results.head.slice(0, 7)}): it is the output of an earlier run, not this round's draft — write this round's results file afresh; annotate never re-annotates, since that would save an earlier round's suggestions as this round's state`);
  }
  // plan's "same work" test compares the saved state's branch with the checked-out one, so a wrong
  // branch here silently turns the next round into a full one. A detached HEAD has no branch name to compare.
  const branchNow = currentBranch(root);
  if (branchNow !== 'HEAD' && results.branch !== branchNow) {
    die(`${resultsPath} was written for branch ${JSON.stringify(results.branch)} but ${JSON.stringify(branchNow)} is checked out — write this round's results file for this branch`);
  }

  const gd = gitDir(root);
  const planData = readJson(opts.plan || path.join(gd, PLAN_FILE));
  const planOk = !!(planData && typeof planData === 'object' && planData.branch === branchNow);

  // plan and resolve-rules each read the file list on their own and each save their result in the git dir.
  // When two runs share that dir (two sessions on one repository, or a step skipped this round), the risk
  // block below would be computed from a list the plan never saw. resolve-rules cannot check its list the
  // way plan does (its --base is the base tip, not the merge-base, so "the change's own files" is not
  // computable there), but both files name the paths they read, and those must be the same set. The
  // results file itself is the one difference by design: plan drops it from the list, resolve-rules does not.
  const rules = readJson(opts.rules || path.join(gd, RULES_FILE));
  if (planOk && rules && Array.isArray(rules.files)) {
    const paths = (list) => new Set((Array.isArray(list) ? list : []).map((e) => e && e.file).filter((f) => typeof f === 'string' && f !== RESULTS_FILE));
    const inPlan = paths(planData.files);
    const inRules = paths(rules.files);
    const onlyPlan = [...inPlan].filter((f) => !inRules.has(f));
    const onlyRules = [...inRules].filter((f) => !inPlan.has(f));
    if (onlyPlan.length || onlyRules.length) {
      const some = (a) => a.slice(0, 5).join(', ') + (a.length > 5 ? `, … (${a.length - 5} more)` : '');
      die(`plan and resolve-rules read different file lists (only in the plan: ${onlyPlan.length ? some(onlyPlan) : '-'}; only in the rules: ${onlyRules.length ? some(onlyRules) : '-'}) — re-run plan and resolve-rules on the same list, then annotate; the risk block would otherwise describe files this round did not review`);
    }
  }

  const priorDismissed = planOk ? mergeDismissed(planData.dismissed) : [];
  const priorByKey = new Map();
  for (const d of priorDismissed) {
    const k = anchorKey(d);
    if (!priorByKey.has(k)) priorByKey.set(k, []);
    priorByKey.get(k).push(d);
  }
  const planBlob = new Map();
  if (planOk) for (const f of planData.files || []) if (f && typeof f.file === 'string') planBlob.set(f.file, f.blob);
  const blobNow = (file) => (planBlob.has(file) ? planBlob.get(file) : blobOf(root, file));

  // Refuse before writing anything: a re-posted dismissed finding is the exact waste this exists to stop —
  // as long as the file still has the content the dismissal was about. A dismissal of code that has since
  // changed does not bind: the reviewer may well be right this time.
  const reposted = results.suggestions.filter((s) => {
    if (!s || typeof s.file !== 'string' || typeof s.quotedCode !== 'string') return false;
    const entries = priorByKey.get(anchorKey(s));
    if (!entries) return false;
    const now = blobNow(s.file);
    return entries.some((d) => dismissalApplies(d, now));
  });
  if (reposted.length) {
    process.stderr.write(`review-branch-rounds: ${reposted.length} suggestion(s) re-post an anchor dismissed in an earlier round on a file that has not changed since — drop them (or argue the dismissal was wrong in the report, with new evidence):\n`);
    for (const s of reposted) process.stderr.write(`  - ${s.file}:${s.line} ${JSON.stringify(String(s.quotedCode).slice(0, 80))}\n`);
    process.exit(1);
  }

  const facts = changeFacts(root, base);
  for (const s of results.suggestions) {
    if (!s || typeof s.file !== 'string') continue;
    s.introduced = introducedOf(facts, s.file, s.line);
  }

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
  const scopedBlob = new Map();
  for (const e of results.scopedFiles) if (e && typeof e.file === 'string' && typeof e.blob === 'string') scopedBlob.set(e.file, e.blob);
  const failedNow = [];
  results.suggestions.forEach((s, i) => {
    if (s && verdict.get(i) === 'FAIL' && typeof s.file === 'string' && typeof s.quotedCode === 'string') {
      failedNow.push({ file: s.file, quotedCode: s.quotedCode, blob: scopedBlob.has(s.file) ? scopedBlob.get(s.file) : blobNow(s.file) });
    }
  });
  const round = planOk ? planData.round : (Number.isInteger(results.round) && results.round >= 1 ? results.round : 1);
  results.round = round;
  results.head = git(root, ['rev-parse', 'HEAD']).trim();
  results.base = base;
  results.scopeMode = planOk ? planData.scopeMode : (results.scopeMode || 'full');
  results.dismissed = mergeDismissed(priorDismissed, failedNow.map((d) => ({ ...d, round })));
  results.carried = planOk ? (planData.carried || []) : (Array.isArray(results.carried) ? results.carried : []);

  if (rules && rules.risk && (rules.risk.tier === 'standard' || rules.risk.tier === 'deep')) {
    results.risk = { tier: rules.risk.tier, hits: Array.isArray(rules.risk.hits) ? rules.risk.hits : [] };
  }

  const text = JSON.stringify(results, null, 2) + '\n';
  fs.writeFileSync(path.resolve(resultsPath), text);
  // The round state the next `plan` reads. Unwritable (sandbox) is not an error: the results file
  // still has everything, and the next plan takes it through --previous.
  let stateSaved = false;
  try { fs.writeFileSync(path.join(gd, LAST_FILE), text); stateSaved = true; } catch (e) {
    process.stderr.write(`review-branch-rounds: could not save the round state to ${path.join(gd, LAST_FILE)} (${e.code || e.message}) — pass --previous ${path.resolve(resultsPath)} to the next plan\n`);
  }
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
    stateSaved,
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
