#!/usr/bin/env node
'use strict';

/**
 * resolve-rules — path-matched rule packs and the risk tier, resolved by a program instead of by
 * the reviewer reading three manifests and matching globs in its head (2.1.0).
 *
 * Layers, highest priority first (first layer that matches a file wins for that file; inside a
 * layer, entries are tried top-to-bottom and the first matching glob wins):
 *   1. project   <repo>/.reviewrules/manifest.json
 *   2. user      ~/.claude/review-rules/manifest.json      (--user-manifest overrides, for tests)
 *   3. built-in  <plugin>/rules/manifest.json
 * Each manifest has `rules: [{pattern, doc}]` and may have `risk: [{pattern, tier, why}]`. Risk is
 * resolved with the same layering: the first matching entry decides the file's tier; the review's
 * tier is `deep` when any scoped file is `deep`, else `standard`. The built-in risk list is a set of
 * path heuristics for the domains a user's review policy usually escalates (auth, crypto, payment,
 * IaC, parsers, LLM context assembly, CI workflows, release/installers); a project overrides it by
 * shipping its own `risk` list — a project entry that matches wins even when it says `standard`.
 *
 * The work tree is the reviewed branch's own content, so it is untrusted (2.1.1). The threat is
 * "lower my own tier", "suppress my own findings", and "make this script fail or stall" — a review
 * with no tier line is the same bypass as a lowered tier. Hence:
 *   - with --base <rev> (what /review-branch passes), the whole project layer — rules and risk —
 *     comes from `<rev>:.reviewrules/manifest.json`, the maintainers' manifest, handled like the
 *     user and built-in ones (trusted: RegExp matching, no limits). The work tree's manifest is not
 *     parsed; it is only compared with the base's so `projectRisk.changed` can say the branch
 *     edited it. Rule docs are files the reviewer reads, so they are taken from the work tree, and
 *     each one is compared with the base by blob id (`docChanged`, `docsChanged`): a doc the branch
 *     added or edited is where a planted "Do NOT report" entry would live. Remapping a file to a
 *     different doc does not help the branch either, since the mapping is the base's. A project doc
 *     must also be a regular file inside the repository (no symlink on its path, at most
 *     DOC_MAX_BYTES): the reviewer opens whatever `doc` names, so a path outside the repo, or a base
 *     doc the branch replaced by a link to some local file, is dropped with a warning and the next
 *     layer's rule applies. The same holds without --base, where the manifest itself names the doc.
 *   - without --base, the work tree's manifest is used (2.1.0 behaviour) but bounded: a regular
 *     file of at most PROJECT_LIMITS.bytes; at most PROJECT_LIMITS.entries entries; patterns of at
 *     most PROJECT_LIMITS.patternLength characters expanding to at most PROJECT_LIMITS.alternatives
 *     sequences; expansion and matching share one work budget (PROJECT_LIMITS.work steps). Once the
 *     budget is spent the project entries stop matching, and because the project risk list could
 *     not be fully evaluated the tier is forced to `deep`.
 *   - anything wrong in the work tree's manifest (not JSON, bad shape, over a limit, an entry that
 *     throws) is a warning in `warnings[]` and is skipped; the script never exits non-zero because
 *     of it. Warning texts carry only a short excerpt of untrusted values with everything that is
 *     not a letter, digit, punctuation, symbol or space replaced, and nothing from the manifest is
 *     re-serialised (a deeply nested value parses fine and overflows JSON.stringify). The user and
 *     built-in manifests are the operator's own: errors there still exit 2.
 *
 * Globs: `**` matches any number of path segments (so `** /x` also matches a top-level `x`), `*` any
 * run of characters within one segment, `?` one character, `{a,b}` alternatives. Patterns are matched
 * against the whole repo-relative path with forward slashes. Trusted layers compile to a RegExp (as
 * 2.1.0 did; fast on long file lists). The untrusted work tree manifest is matched by a state-set
 * simulation over deduplicated brace expansions, whose cost is path length × live states and never
 * exponential — 2.1.0's RegExp of nested `[^/]*` alternations took 7 s per file on a 36-character
 * project glob. File lists are read as git prints them: a C-quoted name (`"auth/s\303\251.ts"`,
 * from core.quotePath) is decoded, otherwise non-ASCII paths would match no pattern at all.
 *
 *   node resolve-rules.cjs --root <repo> --files <list|-> [--base <rev>] [--plugin-root <dir>] [--user-manifest <path>] [--no-write]
 *
 * Output (stdout): {root, layers, files: [{file, doc, docChanged, layer, risk}], docs: [...],
 * docsChanged: [...], risk: {tier, hits}, projectRisk: {source, base, changed}, warnings: [...]};
 * also written to <gitdir>/review-branch-rules.json (review-branch-rounds.cjs annotate embeds `risk`
 * from it) unless --no-write. Warnings are echoed to stderr. Exit 2 on usage / IO errors and on a
 * broken user or built-in manifest. Zero dependencies.
 */

const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const RULES_FILE = 'review-branch-rules.json';
const PROJECT_MANIFEST = '.reviewrules/manifest.json';
const TIERS = ['standard', 'deep'];
const PROJECT_LIMITS = { bytes: 64 * 1024, entries: 128, patternLength: 256, alternatives: 64, work: 20000000 };
const DOC_MAX_BYTES = 1024 * 1024;

function die(msg) {
  process.stderr.write(`resolve-rules: ${msg}\n`);
  process.exit(2);
}

function parseArgs(list) {
  const opts = {};
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a === '--no-write') { opts.noWrite = true; continue; }
    if (a === '-h' || a === '--help') {
      process.stdout.write('usage: resolve-rules.cjs --root <repo> --files <list|-> [--base <rev>] [--plugin-root <dir>] [--user-manifest <path>] [--no-write]\n');
      process.exit(0);
    }
    if (!a.startsWith('--') || list[i + 1] === undefined) die(`unexpected argument ${a}`);
    opts[a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = list[i + 1];
    i++;
  }
  return opts;
}

function git(root, args) {
  const r = cp.spawnSync('git', ['-C', root, '-c', 'core.fsmonitor=false', ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.error || r.status !== 0) throw new Error((r.stderr || '').trim() || `git ${args.join(' ')} failed`);
  return r.stdout;
}

// git C-quotes a path with non-ASCII or special bytes when core.quotePath is on: `"auth/s\303\251.ts"`.
// Decode it back to the real path; a line without the surrounding quotes is returned as is.
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
  const out = [];
  const seen = new Set();
  for (const raw of text.split('\n')) {
    const f = unquoteC(raw.trim()).replace(/^\.\//, '').split(path.sep).join('/');
    if (f && !seen.has(f)) { seen.add(f); out.push(f); }
  }
  return out;
}

// A short, printable excerpt of an untrusted value for a warning. Never JSON.stringify the value
// itself: a deeply nested array parses fine and overflows the stack on the way back out. Everything
// that is not a letter, digit, punctuation, symbol or plain space is replaced — that covers C0/C1
// controls, format characters (bidi, zero-width, tags, soft hyphen), separators, combining marks
// and variation selectors — since the text reaches a terminal and a report.
const UNPRINTABLE = /[^\p{L}\p{N}\p{P}\p{S}\p{Zs}]/gu;
function excerpt(v, max = 60) {
  if (typeof v === 'string') return JSON.stringify(v.slice(0, max).replace(UNPRINTABLE, '?')) + (v.length > max ? '…' : '');
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'an array';
  return typeof v;
}

// ------------------------------------------------------------------------------------- globs

// Trusted layers: glob → anchored RegExp (the 2.1.0 compiler). Brace groups are expanded to
// alternations first so that `*` and `**` inside them are translated like everywhere else.
function globToRegExp(glob) {
  let re = '';
  let i = 0;
  while (i < glob.length) {
    const c = glob[i];
    if (c === '{') {
      const close = glob.indexOf('}', i);
      if (close === -1) { re += '\\{'; i++; continue; }
      const alts = glob.slice(i + 1, close).split(',').map((a) => globToRegExp(a).source.slice(1, -1));
      re += `(?:${alts.join('|')})`;
      i = close + 1;
      continue;
    }
    if (c === '*') {
      if (glob[i + 1] === '*') {
        if (glob[i + 2] === '/') { re += '(?:.*/)?'; i += 3; } else { re += '.*'; i += 2; }
        continue;
      }
      re += '[^/]*';
      i++;
      continue;
    }
    if (c === '?') { re += '[^/]'; i++; continue; }
    re += c.replace(/[.+^$()|[\]\\]/g, '\\$&');
    i++;
  }
  return new RegExp(`^${re}$`, 's');
}

// Untrusted manifest: one brace-free glob → tokens: lit (one character), one (`?`), star (`*`,
// within a segment), any (`**` not followed by `/`, anything), segs (`**/`, zero or more segments).
function tokenize(s) {
  const out = [];
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === '*') {
      if (s[i + 1] === '*') {
        if (s[i + 2] === '/') { out.push({ t: 'segs' }); i += 3; } else { out.push({ t: 'any' }); i += 2; }
        continue;
      }
      out.push({ t: 'star' });
    } else if (c === '?') {
      out.push({ t: 'one' });
    } else {
      out.push({ t: 'lit', c });
    }
    i++;
  }
  return out;
}

function charge(budget, units) {
  budget.left -= units;
  if (budget.left < 0) { budget.exhausted = true; return false; }
  return true;
}

// Brace groups expand into separate token sequences. Each alternative and each run between groups is
// tokenized on its own, so a `*` next to a group never fuses with one inside it into `**`. Identical
// sequences are dropped; more than `maxAlternatives` is an error. A `{` without a closing `}` is literal.
// Expansion work (sequences × alternatives × their length) is charged to the budget like matching is.
function expandGlob(glob, maxAlternatives, budget) {
  let seqs = [[]];
  let run = '';
  const flush = () => {
    if (!run) return;
    const t = tokenize(run);
    seqs = seqs.map((s) => s.concat(t));
    run = '';
  };
  let i = 0;
  while (i < glob.length) {
    const close = glob[i] === '{' ? glob.indexOf('}', i) : -1;
    if (close === -1) { run += glob[i]; i++; continue; }
    flush();
    const alts = glob.slice(i + 1, close).split(',').map(tokenize);
    const longest = seqs.reduce((m, s) => Math.max(m, s.length), 0) + 1;
    if (!charge(budget, seqs.length * alts.length * longest)) throw new Error('hit the work budget while expanding');
    const next = new Map();
    for (const s of seqs) {
      for (const a of alts) {
        const seq = s.concat(a);
        next.set(JSON.stringify(seq), seq);
        if (next.size > maxAlternatives) throw new Error(`expands to more than ${maxAlternatives} alternatives`);
      }
    }
    seqs = [...next.values()];
    i = close + 1;
  }
  flush();
  return seqs;
}

// State-set simulation. A state is a token position p, encoded p << 1, or "inside a `**/` at p",
// encoded (p << 1) | 1. Every input character maps the whole set to the next one, so the cost of one
// sequence is path length × live states, whatever the pattern's ambiguity. The budget is charged one
// unit per live state per character; when it runs out the match fails and the budget is marked
// exhausted (every later test of this layer then fails fast).
function matchSeq(seq, str, budget) {
  const n = seq.length;
  const closure = (set) => {
    const stack = [...set];
    while (stack.length) {
      const s = stack.pop();
      if (s & 1) continue;
      const p = s >> 1;
      if (p < n && (seq[p].t === 'star' || seq[p].t === 'any' || seq[p].t === 'segs')) {
        const z = (p + 1) << 1;
        if (!set.has(z)) { set.add(z); stack.push(z); }
      }
    }
    return set;
  };
  let cur = closure(new Set([0]));
  for (let i = 0; i < str.length; i++) {
    if (!charge(budget, cur.size)) return false;
    const ch = str[i];
    const next = new Set();
    for (const s of cur) {
      const p = s >> 1;
      if (p >= n) continue;
      const tok = seq[p];
      if ((s & 1) || tok.t === 'segs') {
        // `**/` is `(?:.*/)?`: any run of characters that ends in a slash.
        next.add((p << 1) | 1);
        if (ch === '/') next.add((p + 1) << 1);
      } else if (tok.t === 'lit') {
        if (ch === tok.c) next.add((p + 1) << 1);
      } else if (tok.t === 'one') {
        if (ch !== '/') next.add((p + 1) << 1);
      } else if (tok.t === 'star') {
        if (ch !== '/') next.add(p << 1);
      } else {
        next.add(p << 1);
      }
    }
    if (next.size === 0) return false;
    cur = closure(next);
  }
  return cur.has(n << 1);
}

function compileUntrusted(glob, budget) {
  const seqs = expandGlob(glob, PROJECT_LIMITS.alternatives, budget);
  return {
    test: (s) => {
      if (budget.exhausted) return false;
      for (const q of seqs) {
        if (matchSeq(q, s, budget)) return true;
        if (budget.exhausted) return false;
      }
      return false;
    },
  };
}

// --------------------------------------------------------------------------------- manifests

// Parse one manifest. `report` is how a problem surfaces: `die` for the operator's own manifests, a
// warning that skips the offending part for the project layer. `budget` is set only for the work
// tree's manifest (untrusted: limits + state-set matching); trusted manifests compile to RegExps.
function parseManifest(layer, label, text, dir, report, budget = null) {
  let data;
  try { data = JSON.parse(text); } catch (e) { report(`${label} is not valid JSON`); return null; }
  if (!data || typeof data !== 'object' || Array.isArray(data)) { report(`${label} is not a JSON object`); return null; }
  const limits = budget ? PROJECT_LIMITS : null;
  let taken = 0;
  let overflowReported = false;
  const compile = (list, what, check) => {
    const out = [];
    if (!Array.isArray(list)) return out;
    for (let i = 0; i < list.length; i++) {
      try {
        if (limits && ++taken > limits.entries) {
          if (!overflowReported) { report(`${label}: more than ${limits.entries} entries — the rest are ignored`); overflowReported = true; }
          break;
        }
        if (budget && budget.exhausted) {
          report(`${label}: the work budget ran out while compiling — ${what}[${i}] and the remaining entries are ignored`);
          break;
        }
        const e = list[i];
        if (!e || typeof e !== 'object' || Array.isArray(e) || typeof e.pattern !== 'string') { report(`${label}: ${what}[${i}] needs a string "pattern"`); continue; }
        if (limits && e.pattern.length > limits.patternLength) { report(`${label}: ${what}[${i}] pattern is ${e.pattern.length} characters, over the ${limits.patternLength} limit — ignored`); continue; }
        const bad = check(e);
        if (bad) { report(`${label}: ${what}[${i}] ${bad}`); continue; }
        let matcher;
        try { matcher = budget ? compileUntrusted(e.pattern, budget) : globToRegExp(e.pattern); } catch (err) { report(`${label}: ${what}[${i}] pattern ${excerpt(e.pattern)} ${err.message}`); continue; }
        out.push({ pattern: e.pattern, doc: e.doc, tier: e.tier, why: typeof e.why === 'string' ? e.why : null, matcher });
      } catch (err) {
        report(`${label}: ${what}[${i}] skipped: ${String(err && err.message).slice(0, 80)}`);
      }
    }
    return out;
  };
  const rules = compile(data.rules, 'rules', (e) => (typeof e.doc === 'string' ? null : `(pattern ${excerpt(e.pattern)}) needs a string "doc", got ${excerpt(e.doc)}`))
    .map((r) => ({ ...r, docPath: path.resolve(dir, r.doc) }));
  const risk = compile(data.risk, 'risk', (e) => (TIERS.includes(e.tier) ? null : `(pattern ${excerpt(e.pattern)}) has tier ${excerpt(e.tier)} (expected standard or deep)`));
  return { layer, file: label, rules, risk };
}

function loadTrustedManifest(layer, file) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
  return parseManifest(layer, file, text, path.dirname(file), die);
}

// The work tree's project manifest, read only when it is a regular file within the size limit.
// Absent → null without a warning; a symlink, directory, device or oversized file → warning + null.
function readProjectText(file, report) {
  let st;
  try { st = fs.lstatSync(file); } catch (e) { return null; }
  if (!st.isFile()) { report(`${file} is not a regular file — ignored`); return null; }
  if (st.size > PROJECT_LIMITS.bytes) { report(`${file} is ${st.size} bytes, over the ${PROJECT_LIMITS.bytes}-byte limit — ignored`); return null; }
  try { return fs.readFileSync(file, 'utf8'); } catch (e) { report(`${file} could not be read — ignored`); return null; }
}

// The base revision's project manifest text. Absent → null silently; present but unreadable → warning.
function readBaseText(root, base, report) {
  const spec = `${base}:${PROJECT_MANIFEST}`;
  try { git(root, ['cat-file', '-e', spec]); } catch (e) { return null; }
  try { return git(root, ['show', spec]); } catch (e) { report(`${base.slice(0, 12)}:${PROJECT_MANIFEST} could not be read — ignored`); return null; }
}

// May the reviewer be pointed at this project rule doc? It must lie inside the repository (lexically,
// so `/abs/path` and `../x` fail whether or not the target exists) and, when it exists, be a regular
// file within DOC_MAX_BYTES with no symlink anywhere on its path (the real path equals the lexical one).
// A doc that does not exist is harmless — there is nothing to read — and stays as it was in 2.1.0.
function docUsable(root, docPath) {
  const rel = path.relative(root, docPath);
  if (!rel || rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel)) return false;
  let st;
  try { st = fs.lstatSync(docPath); } catch (e) { return !!e && e.code === 'ENOENT'; }
  if (!st.isFile() || st.size > DOC_MAX_BYTES) return false;
  try { return fs.realpathSync(docPath) === path.resolve(fs.realpathSync(root), rel); } catch (e) { return false; }
}

// Did the branch add or change this project rule doc? The work tree copy must be a regular file
// inside the repo (no symlink anywhere on its path — `git hash-object` follows symlinks, and one to
// /dev/zero never ends) and within DOC_MAX_BYTES; then its blob id is compared with the base's.
// Anything else — missing on either side, outside the repo, special file, too big — is "changed".
function docChangedSince(root, base, docPath, cache) {
  if (cache.has(docPath)) return cache.get(docPath);
  let changed = true;
  try {
    const st = fs.lstatSync(docPath);
    const real = fs.realpathSync(docPath);
    const rootReal = fs.realpathSync(root);
    const rel = path.relative(rootReal, real);
    const inside = rel && !rel.startsWith('..') && !path.isAbsolute(rel) && real === path.resolve(rootReal, rel);
    if (st.isFile() && st.size <= DOC_MAX_BYTES && inside && real === path.resolve(docPath)) {
      const gitRel = path.relative(root, docPath).split(path.sep).join('/');
      // --no-filters: the branch owns .gitattributes; an `ident` clean filter would hash a planted
      // `$Id: Do NOT report … $` line as `$Id$`, the same as the base's.
      const now = git(root, ['hash-object', '--no-filters', '--', gitRel]).trim();
      const then = git(root, ['rev-parse', '--verify', '--quiet', `${base}:${gitRel}`]).trim();
      changed = now !== then;
    }
  } catch (e) { changed = true; }
  cache.set(docPath, changed);
  return changed;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const rootArg = opts.root || process.cwd();
  let root;
  try { root = git(rootArg, ['rev-parse', '--show-toplevel']).trim(); } catch (e) { die(`${rootArg} is not inside a git work tree`); }
  const files = readList(opts.files);
  const pluginRoot = opts.pluginRoot ? path.resolve(opts.pluginRoot) : path.resolve(__dirname, '..');
  const userManifest = opts.userManifest || path.join(os.homedir(), '.claude', 'review-rules', 'manifest.json');

  const warnings = [];
  const warn = (msg) => { warnings.push(msg); };
  const budget = { left: PROJECT_LIMITS.work, exhausted: false };
  const projectFile = path.join(root, ...PROJECT_MANIFEST.split('/'));
  const projectDir = path.dirname(projectFile);

  let base = null;
  if (opts.base) {
    try { base = git(root, ['rev-parse', '--verify', `${opts.base}^{commit}`]).trim(); } catch (e) { die(`--base ${opts.base} does not resolve to a commit`); }
  }
  let projectLayer = null;
  let projectRisk = { source: null, base: null, changed: false };
  if (base) {
    const baseText = readBaseText(root, base, warn);
    const fromBase = baseText === null ? null : parseManifest('project', `${base.slice(0, 12)}:${PROJECT_MANIFEST}`, baseText, projectDir, warn);
    if (fromBase) projectLayer = { layer: 'project', file: fromBase.file, rules: fromBase.rules, risk: fromBase.risk };
    const treeText = readProjectText(projectFile, warn);
    projectRisk = { source: 'base', base, changed: treeText !== baseText };
  } else {
    const treeText = readProjectText(projectFile, warn);
    const tree = treeText === null ? null : parseManifest('project', projectFile, treeText, projectDir, warn, budget);
    if (tree) projectLayer = { layer: 'project', file: projectFile, rules: tree.rules, risk: tree.risk };
    projectRisk = { source: tree ? 'working-tree' : null, base: null, changed: false };
  }

  const layers = [
    projectLayer,
    loadTrustedManifest('user', userManifest),
    loadTrustedManifest('built-in', path.join(pluginRoot, 'rules', 'manifest.json')),
  ].filter(Boolean);
  if (!layers.some((l) => l.layer === 'built-in')) die(`built-in manifest not found under ${pluginRoot}/rules`);

  const out = [];
  const docs = new Set();
  const docsChanged = new Set();
  const docCache = new Map();
  const droppedDocs = new Set();
  const hits = [];
  let exhaustedAt = null;
  for (const file of files) {
    let doc = null;
    let docChanged = null;
    let layer = null;
    for (const l of layers) {
      const r = l.rules.find((x) => x.matcher.test(file));
      if (!r) continue;
      if (l.layer === 'project' && !docUsable(root, r.docPath)) {
        // The project layer's doc is the branch's to influence (the manifest without --base, the file
        // itself with --base). Not handing it to the reviewer is the point; the next layer applies.
        if (!droppedDocs.has(r.docPath)) {
          droppedDocs.add(r.docPath);
          warn(`project layer: rule doc ${excerpt(r.doc, 120)} is not a regular file inside the repository (outside it, behind a symlink, a special file or over ${DOC_MAX_BYTES} bytes) — ignored, the next layer's rule applies`);
          if (base) docsChanged.add(path.relative(root, r.docPath).split(path.sep).join('/'));
        }
        continue;
      }
      doc = r.docPath; layer = l.layer; break;
    }
    if (doc) {
      docs.add(doc);
      if (layer === 'project' && base) {
        docChanged = docChangedSince(root, base, doc, docCache);
        if (docChanged) docsChanged.add(path.relative(root, doc).split(path.sep).join('/'));
      }
    }
    let risk = { tier: 'standard', pattern: null, why: null, layer: null };
    for (const l of layers) {
      const r = l.risk.find((x) => x.matcher.test(file));
      if (r) { risk = { tier: r.tier, pattern: r.pattern, why: r.why, layer: l.layer }; break; }
    }
    if (exhaustedAt === null && budget.exhausted) exhaustedAt = file;
    if (risk.tier === 'deep') hits.push({ file, pattern: risk.pattern, why: risk.why, layer: risk.layer });
    out.push({ file, doc, docChanged, layer, risk });
  }
  if (budget.exhausted) {
    // Only the work tree's manifest (no --base) is budgeted. Its risk list could not be fully
    // evaluated, and a list the branch can make unevaluable must not read as clean.
    warn(`project layer: the work tree manifest hit the matching work budget (${PROJECT_LIMITS.work} steps)${exhaustedAt ? ` at ${excerpt(exhaustedAt, 120)}` : ''} — its rules and risk list were ignored from that point on; the tier is forced to deep because the risk list could not be fully evaluated (pass --base to read the project layer from the base branch instead)`);
    hits.push({ file: exhaustedAt, pattern: null, why: 'project risk list could not be fully evaluated (work budget exhausted)', layer: 'project' });
  }

  const result = {
    root,
    layers: layers.map((l) => ({ layer: l.layer, file: l.file, rules: l.rules.length, risk: l.risk.length })),
    files: out,
    docs: [...docs],
    docsChanged: [...docsChanged],
    risk: { tier: hits.length ? 'deep' : 'standard', hits },
    projectRisk,
    warnings,
  };
  for (const w of warnings) process.stderr.write(`resolve-rules: warning: ${w}\n`);
  if (!opts.noWrite) {
    const gd = path.resolve(root, git(root, ['rev-parse', '--git-dir']).trim());
    const target = path.join(gd, RULES_FILE);
    fs.writeFileSync(target, JSON.stringify(result, null, 2) + '\n');
    result.rulesFile = target;
  }
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

main();
