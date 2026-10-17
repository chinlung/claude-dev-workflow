#!/usr/bin/env node
'use strict';

/**
 * scope-facts — the mechanical half of a finding's triage, computed instead of judged.
 *
 * The converge policy's first question about a finding is "does it belong to this change?". That is
 * not a judgement: it is whether the finding's file:line sits inside a hunk of the branch diff. The
 * other adoption exceptions lean on facts too — the same defect elsewhere (sibling), a project MUST
 * rule that names it, the size of the change. This script reads a list of findings and attaches those
 * facts to each one, so the ledger line can be prefilled from them and so the same JSON can be handed
 * to a calibrated classifier (jev_decide) as a neutral `state` without writing it by hand — the cost
 * of writing that state is what made the classifier get skipped.
 *
 *   node scope-facts.cjs [--repo <dir>] [--base <ref>] [--findings <file>]
 *
 * Input (stdin, or --findings <file>): a JSON array of findings, or {"findings": [...]}. Each finding:
 *   path (required; repo-relative or absolute), line (optional, 1-based), claim, evidence, id (any
 *   other field is passed through untouched).
 * Base: --base <ref>; else the merge-base of HEAD and origin/HEAD when origin/HEAD exists; else HEAD
 * (reported as base_fallback and warned about on stderr: a branch's commits then read as pre-existing).
 * The diff is `git diff -U0 <base>` — committed changes since the base AND the working tree — plus
 * untracked files, which count as wholly added.
 * Output (stdout): {root, base, head, guideline_files, findings: [{...finding, path: <relative>,
 * facts: {...}}], summary}. Exit 2 with a one-line reason on stderr when the input is not JSON, the
 * repo is not a git work tree or the base ref does not resolve. Zero dependencies.
 *
 * facts per finding:
 *   file_in_diff        the diff touches the file (any kind below), or it is untracked
 *   change_kind         untracked | added | deleted | binary | mode | modified | typechange | null
 *   untracked           the file is untracked (wholly new)
 *   line_invalid        the finding's line was neither an integer nor a digit string; such a finding
 *                       is never counted as in the diff
 *   in_diff             the line is inside an added/changed hunk; an untracked, added, deleted or
 *                       binary file: every line; a mode-only change: no line (only a finding with no
 *                       line); a finding with no line in a changed file: true
 *   nearest_hunk_distance  0 inside a hunk, otherwise lines to the nearest one; null when the file
 *                       has no hunk
 *   adjacent_to_deletion   a deletion-only hunk sits at this line or the one before it
 *   hunks               [[start, count], ...] on the new side
 *   patch_lines         {added, deleted} for the whole file
 *   sibling             {key, count, matches[]}: other places in the repo (tracked + untracked) that
 *                       contain the same text — the evidence's first `backticked` snippet, else the
 *                       source line itself; the finding's own line is excluded
 *   must_rules          lines of the project's guideline files (AGENTS.md, CLAUDE.md, .claude/CLAUDE.md,
 *                       CONTRIBUTING.md, docs/CONTRIBUTING.md) that read as a rule (MUST / 必須 / 一律 /
 *                       禁止 / 不得 / 絕不) and share words with the claim or evidence — candidates for
 *                       the "project MUST rule" exception, to be read, not trusted
 * None of this says whether the finding is real. That stays a judgement.
 */

const cp = require('child_process');
const fs = require('fs');
const path = require('path');

const GUIDELINE_FILES = ['AGENTS.md', 'CLAUDE.md', '.claude/CLAUDE.md', 'CONTRIBUTING.md', 'docs/CONTRIBUTING.md'];
// A line that reads as a rule. Recall over precision: these are candidates the reader checks.
const RULE_RE = /\b(must|never|do not|don't)\b|必須|須|一律|禁止|不得|絕不|不可/i;
const STOP = new Set(['the', 'and', 'for', 'not', 'are', 'but', 'has', 'was', 'its', 'our', 'can', 'may', 'use', 'new', 'one', 'two', 'all', 'any', 'you', 'this', 'that', 'with', 'when', 'from', 'have', 'been', 'will', 'would', 'should', 'could', 'into', 'only', 'also', 'then', 'than', 'does', 'which', 'what', 'where', 'there', 'their', 'they', 'them', 'were', 'your', 'about', 'after', 'before', 'because', 'while', 'each', 'other', 'same', 'such', 'here', 'line', 'lines', 'file', 'files', 'code', 'issue', 'finding', 'missing', 'wrong', 'thing', 'appears', 'elsewhere', 'still', 'never', 'always', 'these', 'those', 'being', 'under', 'over', 'through', 'without', 'within', 'must']);
const MAX_SIBLINGS = 10;
const MAX_RULES = 5;

function die(msg) {
  process.stderr.write(`scope-facts: ${msg}\n`);
  process.exit(2);
}

function argv() {
  const out = { repo: process.cwd(), base: null, findings: null };
  const a = process.argv.slice(2);
  for (let i = 0; i < a.length; i++) {
    const k = a[i];
    const v = a[i + 1];
    if (k === '--repo' && v !== undefined) { out.repo = v; i++; }
    else if (k === '--base' && v !== undefined) { out.base = v; i++; }
    else if (k === '--findings' && v !== undefined) { out.findings = v; i++; }
    else if (k === '-h' || k === '--help') { process.stdout.write('usage: scope-facts.cjs [--repo <dir>] [--base <ref>] [--findings <file>]\n'); process.exit(0); }
    else die(`unknown argument ${k}`);
  }
  return out;
}

// git <args> in <root>; {ok: [codes]} lists non-zero statuses that are answers, not failures.
function git(root, args, opts = {}) {
  // core.quotePath=false: with the default (true) git prints a non-ASCII path as "\346\226\260…" in
  // diff headers, `ls-files` and `grep` output, and no finding path would ever match it.
  const r = cp.spawnSync('git', ['-C', root, '-c', 'core.fsmonitor=false', '-c', 'core.quotePath=false', ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.error) throw r.error;
  if (r.status !== 0 && !(opts.ok || []).includes(r.status)) {
    const err = new Error((r.stderr || '').trim() || `git ${args.join(' ')} exited ${r.status}`);
    err.status = r.status;
    throw err;
  }
  return r.stdout;
}

function readInput(file) {
  let text;
  if (!(file && file !== '-') && process.stdin.isTTY) die('no findings: pass them on stdin or with --findings <file> (usage: scope-facts.cjs [--repo <dir>] [--base <ref>] [--findings <file>])');
  try {
    text = file && file !== '-' ? fs.readFileSync(file, 'utf8') : fs.readFileSync(0, 'utf8');
  } catch (e) {
    die(`cannot read findings: ${e.message}`);
  }
  if (text.trim() === '') die('no input: findings must arrive on stdin or via --findings <file>');
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    die(`input is not valid JSON: ${e.message}`);
  }
  const list = Array.isArray(parsed) ? parsed : parsed && Array.isArray(parsed.findings) ? parsed.findings : null;
  if (!list) die('input must be a JSON array of findings or {"findings": [...]}');
  list.forEach((f, i) => {
    if (!f || typeof f !== 'object' || typeof f.path !== 'string' || f.path === '') die(`findings[${i}] needs a string "path"`);
  });
  return list;
}

// git prints a path C-quoted when it contains `"`, `\`, a control character, or (with core.quotePath
// on) any non-ASCII byte: `"b/q\"uo.txt"`, `"b/tab\tf.txt"`, `"b/\346\226\260.php"`. Decode the
// escapes `\\ \" \a \b \f \n \r \t \v` and `\NNN` (octal, one byte) into bytes, then UTF-8.
function unquoteGitPath(p) {
  if (!(p.length >= 2 && p.startsWith('"') && p.endsWith('"'))) return p;
  const chars = Array.from(p.slice(1, -1));
  const simple = { '\\': 92, '"': 34, a: 7, b: 8, f: 12, n: 10, r: 13, t: 9, v: 11 };
  const bytes = [];
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (c !== '\\') { for (const b of Buffer.from(c, 'utf8')) bytes.push(b); continue; }
    const n = chars[i + 1];
    if (n !== undefined && /^[0-7]$/.test(n)) {
      let oct = '';
      while (oct.length < 3 && i + 1 < chars.length && /^[0-7]$/.test(chars[i + 1])) { oct += chars[i + 1]; i++; }
      bytes.push(parseInt(oct, 8) & 0xff);
      continue;
    }
    if (n !== undefined && Object.prototype.hasOwnProperty.call(simple, n)) { bytes.push(simple[n]); i++; continue; }
    bytes.push(92);
  }
  return Buffer.from(bytes).toString('utf8');
}

// `git diff -U0` → Map(relative path → {hunks: [{start, count, oldCount}], added, deleted}).
function parseDiff(text) {
  const files = new Map();
  let cur = null;
  // A `+++ ` line names a file only in the header, between `diff --git` and the first `@@`: inside a
  // hunk the same prefix is an added line whose content starts with `++ ` (`+++ counter;`), and
  // taking it as a header would hand the rest of the file's hunks to a file that does not exist.
  let inHeader = false;
  for (const line of text.split('\n')) {
    if (line.startsWith('diff --git ')) { cur = null; inHeader = true; continue; }
    if (inHeader && line.startsWith('+++ ')) {
      // git ends the header path with a tab when the name contains a space (`+++ b/a b.c\t`); a
      // name that really ends in a tab is C-quoted instead, so a bare trailing tab is never part of it.
      const p = unquoteGitPath(line.slice(4).replace(/\t$/, ''));
      if (p === '/dev/null') { cur = null; continue; }
      cur = p.replace(/^b\//, '');
      if (!files.has(cur)) files.set(cur, { hunks: [], added: 0, deleted: 0 });
      continue;
    }
    if (line.startsWith('@@ ')) {
      inHeader = false;
      if (!cur) continue;
      const m = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line);
      if (!m) continue;
      const oldCount = m[2] === undefined ? 1 : Number(m[2]);
      const start = Number(m[3]);
      const count = m[4] === undefined ? 1 : Number(m[4]);
      const f = files.get(cur);
      f.hunks.push({ start, count, oldCount });
      f.added += count;
      f.deleted += oldCount;
    }
  }
  return files;
}

// realpath when the path exists; otherwise realpath of its directory plus the basename (a finding
// may name a file that is gone). `git rev-parse --show-toplevel` returns the real path, while a
// caller may pass one through a symlink (/tmp → /private/tmp on macOS).
function realish(p) {
  try { return fs.realpathSync(p); } catch (e) { /* fall through */ }
  try { return path.join(fs.realpathSync(path.dirname(p)), path.basename(p)); } catch (e) { return path.resolve(p); }
}

function relPath(root, p) {
  let rel = p;
  if (path.isAbsolute(p)) {
    const r = path.relative(realish(root), realish(p));
    if (r && !r.startsWith('..')) rel = r;
  }
  rel = rel.replace(/^\.\//, '');
  return rel.split(path.sep).join('/');
}

function countLines(file) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return 0; }
  if (text === '') return 0;
  const n = text.split('\n').length;
  return text.endsWith('\n') ? n - 1 : n;
}

function sourceLine(file, line) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
  const lines = text.split('\n');
  return line >= 1 && line <= lines.length ? lines[line - 1] : null;
}

function siblingKey(finding, absFile, line) {
  const ev = typeof finding.evidence === 'string' ? finding.evidence : '';
  const m = /`([^`\n]{8,})`/.exec(ev);
  if (m) return m[1].trim();
  if (line === null || absFile === null) return null;
  const src = sourceLine(absFile, line);
  if (src === null) return null;
  const t = src.trim();
  // A line that is only punctuation or shorter than a dozen characters matches everywhere.
  if (t.length < 12 || !/[A-Za-z0-9㐀-鿿]/.test(t)) return null;
  return t;
}

// git grep over tracked and untracked files; returns [{path, line, text}] minus the finding itself.
function siblings(root, key, selfPath, selfLine) {
  if (!key) return { key: null, count: 0, matches: [] };
  let out;
  try {
    // -z: path, line number and text are NUL-separated (records still end in a newline), so a path
    // that itself contains ":" cannot be cut in the wrong place.
    out = git(root, ['grep', '-n', '-F', '-z', '--untracked', '-e', key, '--', '.'], { ok: [1] });
  } catch (e) {
    return { key, count: 0, matches: [], error: e.message };
  }
  const all = [];
  for (const row of out.split('\n')) {
    if (row === '') continue;
    const parts = row.split('\0');
    if (parts.length < 3) continue;
    const p = parts[0];
    const ln = Number(parts[1]);
    if (!Number.isInteger(ln)) continue;
    // The finding itself is not its own sibling; with no line known, nothing in its file is.
    if (p === selfPath && (selfLine === null || ln === selfLine)) continue;
    all.push({ path: p, line: ln, text: parts.slice(2).join('\0').trim().slice(0, 160) });
  }
  return { key, count: all.length, matches: all.slice(0, MAX_SIBLINGS) };
}

// Which files the diff touches and how: `--name-status` gives every changed path with its kind (A, M,
// D, T), including the ones `-U0` text alone would miss — a deleted file (`+++ /dev/null`), a binary
// (no hunks), a mode-only change, an added empty file; `--numstat` gives line counts, `-` for binary.
// Both -z, so paths arrive raw.
function nameStatus(root, base) {
  const parts = git(root, ['diff', '--name-status', '-z', '--no-renames', '--no-textconv', base, '--', '.']).split('\0');
  const m = new Map();
  for (let i = 0; i + 1 < parts.length; i += 2) {
    const st = parts[i];
    const p = parts[i + 1];
    if (st && p) m.set(p, st[0]);
  }
  return m;
}

function numStat(root, base) {
  const m = new Map();
  for (const rec of git(root, ['diff', '--numstat', '-z', '--no-renames', '--no-textconv', base, '--', '.']).split('\0')) {
    if (!rec) continue;
    const t = rec.split('\t');
    if (t.length < 3) continue;
    const binary = t[0] === '-' || t[1] === '-';
    m.set(t.slice(2).join('\t'), { added: binary ? null : Number(t[0]), deleted: binary ? null : Number(t[1]), binary });
  }
  return m;
}

// The finding's line: an integer or a digit string > 0; 0, null and absent mean "no line" (the tree
// workflow's discover emits line 0 for "file changed"); anything else is invalid and reported as such
// rather than read as "no line", which would have made the finding count as in the diff.
function parseLine(v) {
  if (v === undefined || v === null || v === '' || v === 0) return { line: null, invalid: false };
  if (Number.isInteger(v) && v > 0) return { line: v, invalid: false };
  if (typeof v === 'string' && /^\d+$/.test(v) && Number(v) > 0) return { line: Number(v), invalid: false };
  return { line: null, invalid: true };
}

function tokens(text) {
  const ascii = new Set();
  for (const w of (text.match(/[A-Za-z][A-Za-z0-9_]{2,}/g) || [])) {
    const l = w.toLowerCase();
    if (!STOP.has(l)) ascii.add(l);
  }
  const cjk = new Set();
  const chars = (text.match(/[㐀-鿿]/g) || []).join('');
  for (let i = 0; i + 1 < chars.length; i++) cjk.add(chars.slice(i, i + 2));
  return { ascii, cjk };
}

function loadGuidelines(root) {
  const out = [];
  for (const rel of GUIDELINE_FILES) {
    // Same rule as for finding paths: a guideline file that is a symlink out of the tree is not read.
    const real = realish(path.join(root, rel));
    if (real !== root && !real.startsWith(root + path.sep)) continue;
    let text;
    try { text = fs.readFileSync(real, 'utf8'); } catch (e) { continue; }
    const lines = text.split('\n');
    const rules = [];
    lines.forEach((l, i) => { if (RULE_RE.test(l)) rules.push({ file: rel, line: i + 1, text: l.trim(), tok: tokens(l) }); });
    out.push({ file: rel, rules });
  }
  return out;
}

function mustRules(guidelines, finding) {
  const q = tokens(`${finding.claim || ''} ${finding.evidence || ''}`);
  if (q.ascii.size === 0 && q.cjk.size === 0) return [];
  const hits = [];
  for (const g of guidelines) {
    for (const r of g.rules) {
      const matched = [];
      for (const t of q.ascii) if (r.tok.ascii.has(t)) matched.push(t);
      let cjk = 0;
      for (const b of q.cjk) if (r.tok.cjk.has(b)) cjk++;
      if (matched.length > 0 || cjk >= 2) hits.push({ file: r.file, line: r.line, text: r.text.slice(0, 160), matched, cjk_bigrams: cjk });
    }
  }
  hits.sort((a, b) => (b.matched.length + b.cjk_bigrams) - (a.matched.length + a.cjk_bigrams));
  return hits.slice(0, MAX_RULES);
}

function main() {
  const opt = argv();
  let root;
  try {
    root = git(opt.repo, ['rev-parse', '--show-toplevel']).trim();
  } catch (e) {
    die(`${opt.repo} is not inside a git work tree`);
  }
  const findings = readInput(opt.findings);

  let head;
  try { head = git(root, ['rev-parse', '--verify', 'HEAD^{commit}']).trim(); } catch (e) { die('the repository has no commits yet'); }
  let base;
  let baseFallback = null;
  if (opt.base) {
    try { base = git(root, ['rev-parse', '--verify', `${opt.base}^{commit}`]).trim(); } catch (e) { die(`--base ${opt.base} does not resolve to a commit`); }
  } else {
    let originHead = '';
    try { originHead = git(root, ['rev-parse', '--verify', '-q', 'origin/HEAD^{commit}'], { ok: [1] }).trim(); } catch (e) { originHead = ''; }
    if (originHead) {
      base = git(root, ['merge-base', 'HEAD', originHead]).trim();
    } else {
      // Nothing to measure the branch against: only the working tree counts as "this change". Said
      // out loud, because a branch's committed changes then all read as pre-existing.
      base = head;
      baseFallback = 'HEAD';
      process.stderr.write('scope-facts: no origin/HEAD, base falls back to HEAD (working tree only); pass --base <ref> to include the commits of this branch\n');
    }
  }

  let diffText;
  let status;
  let numstat;
  try {
    // Explicit prefixes: diff.mnemonicPrefix / diff.noprefix / diff.dstPrefix would otherwise change
    // the `+++` line and no hunk would be matched to its file.
    diffText = git(root, ['diff', '-U0', '--no-color', '--no-ext-diff', '--no-textconv', '--no-renames', '--src-prefix=a/', '--dst-prefix=b/', base, '--', '.']);
    status = nameStatus(root, base);
    numstat = numStat(root, base);
  } catch (e) {
    die(`git diff failed: ${e.message}`);
  }
  const files = parseDiff(diffText);
  // -z: NUL-separated, so a path with a quote, a tab or a newline arrives raw instead of C-quoted.
  const untracked = new Set(git(root, ['ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean));
  const guidelines = loadGuidelines(root);

  const out = [];
  const summary = { total: findings.length, in_diff: 0, file_in_diff_only: 0, outside_diff: 0, line_invalid: 0, with_sibling_candidates: 0, with_must_rule_candidates: 0 };
  for (const finding of findings) {
    const rel = relPath(root, finding.path);
    // A path that escapes the work tree — "../x", an absolute path elsewhere, or a symlink inside the
    // tree that points outside (a checkout of someone else's PR can contain one) — is kept as given
    // but never read: findings come from review tools, and a crafted path would otherwise have this
    // script echo a line of any readable file back as the sibling key. Resolved through symlinks
    // first, and every read below goes to the resolved path.
    const real = realish(path.resolve(root, rel));
    const outside = real !== root && !real.startsWith(root + path.sep);
    const { line, invalid: lineInvalid } = parseLine(finding.line);
    const f = files.get(rel);
    const st = status.get(rel);
    const ns = numstat.get(rel);
    const isUntracked = untracked.has(rel);
    // What kind of change touched the file; null when the diff does not know it.
    let kind = null;
    if (isUntracked) kind = 'untracked';
    else if (st === 'D') kind = 'deleted';
    else if (st === 'A') kind = ns && ns.binary ? 'binary' : 'added';
    else if (st) kind = ns && ns.binary ? 'binary' : f && f.hunks.length ? (st === 'T' ? 'typechange' : 'modified') : 'mode';
    const fileInDiff = kind !== null;
    let inDiff = false;
    let nearest = null;
    let adjacent = false;
    if (lineInvalid) {
      // Reported, not guessed: an unreadable line must not promote the finding into the diff.
    } else if (kind === 'untracked' || kind === 'deleted' || kind === 'added' || kind === 'binary') {
      // The whole file is the change.
      inDiff = true;
      nearest = 0;
    } else if (kind === 'mode') {
      // Only the mode changed: no line of content did.
      inDiff = line === null;
      nearest = null;
    } else if (f) {
      if (line === null) {
        inDiff = true;
        nearest = 0;
      } else {
        for (const h of f.hunks) {
          if (h.count > 0) {
            const end = h.start + h.count - 1;
            const d = line < h.start ? h.start - line : line > end ? line - end : 0;
            if (nearest === null || d < nearest) nearest = d;
            if (d === 0) inDiff = true;
          } else {
            // A deletion-only hunk is reported at the line before the gap; the finding's line can be
            // that line or the next one.
            const d = Math.min(Math.abs(line - h.start), Math.abs(line - (h.start + 1)));
            if (nearest === null || d < nearest) nearest = d;
            if (d === 0) adjacent = true;
          }
        }
      }
    }
    const patch = ns ? { added: ns.added, deleted: ns.deleted } : isUntracked && !outside ? { added: countLines(real), deleted: 0 } : { added: 0, deleted: 0 };
    const key = outside ? siblingKey(finding, null, null) : siblingKey(finding, real, line);
    const sib = siblings(root, key, rel, line);
    const rules = mustRules(guidelines, finding);

    if (lineInvalid) summary.line_invalid++;
    if (inDiff) summary.in_diff++;
    else if (fileInDiff) summary.file_in_diff_only++;
    else summary.outside_diff++;
    if (sib.count > 0) summary.with_sibling_candidates++;
    if (rules.length > 0) summary.with_must_rule_candidates++;

    out.push({
      ...finding,
      path: rel,
      facts: {
        outside_repo: outside,
        file_in_diff: fileInDiff,
        change_kind: kind,
        untracked: isUntracked,
        line_invalid: lineInvalid,
        in_diff: inDiff,
        nearest_hunk_distance: nearest,
        adjacent_to_deletion: adjacent,
        hunks: f ? f.hunks.map((h) => [h.start, h.count]) : [],
        patch_lines: patch,
        sibling: sib,
        must_rules: rules,
      },
    });
  }

  process.stdout.write(JSON.stringify({
    root,
    base,
    base_fallback: baseFallback,
    head,
    worktree_included: true,
    guideline_files: guidelines.map((g) => g.file),
    findings: out,
    summary,
  }, null, 2) + '\n');
}

main();
