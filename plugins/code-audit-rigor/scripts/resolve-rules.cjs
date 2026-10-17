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
 * Globs: `**` matches any number of path segments (so `** /x` also matches a top-level `x`), `*` any
 * run of characters within one segment, `?` one character, `{a,b}` alternatives. Patterns are matched
 * against the whole repo-relative path with forward slashes.
 *
 *   node resolve-rules.cjs --root <repo> --files <list|-> [--plugin-root <dir>] [--user-manifest <path>] [--no-write]
 *
 * Output (stdout): {root, files: [{file, doc, layer, risk}], docs: [...], risk: {tier, hits}}; also
 * written to <gitdir>/review-branch-rules.json (review-branch-rounds.cjs annotate embeds `risk` from
 * it) unless --no-write. Exit 2 on usage / IO errors. Zero dependencies.
 */

const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const RULES_FILE = 'review-branch-rules.json';
const TIERS = ['standard', 'deep'];

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
      process.stdout.write('usage: resolve-rules.cjs --root <repo> --files <list|-> [--plugin-root <dir>] [--user-manifest <path>] [--no-write]\n');
      process.exit(0);
    }
    if (!a.startsWith('--') || list[i + 1] === undefined) die(`unexpected argument ${a}`);
    opts[a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = list[i + 1];
    i++;
  }
  return opts;
}

function git(root, args) {
  const r = cp.spawnSync('git', ['-C', root, '-c', 'core.fsmonitor=false', ...args], { encoding: 'utf8' });
  if (r.error || r.status !== 0) throw new Error((r.stderr || '').trim() || `git ${args.join(' ')} failed`);
  return r.stdout;
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
    const f = raw.trim().replace(/^\.\//, '').split(path.sep).join('/');
    if (f && !seen.has(f)) { seen.add(f); out.push(f); }
  }
  return out;
}

// Glob → anchored RegExp. Brace groups are expanded to alternations first so that `*` and `**`
// inside them are translated like everywhere else.
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
        // `**/` → zero or more whole segments; a trailing or infix `**` → anything.
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
  return new RegExp(`^${re}$`);
}

function loadManifest(layer, file) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
  let data;
  try { data = JSON.parse(text); } catch (e) { die(`${file} is not valid JSON: ${e.message}`); }
  const dir = path.dirname(file);
  const compile = (list, what) => (Array.isArray(list) ? list : []).map((e, i) => {
    if (!e || typeof e.pattern !== 'string') die(`${file}: ${what}[${i}] needs a string "pattern"`);
    return { ...e, re: globToRegExp(e.pattern) };
  });
  const rules = compile(data.rules, 'rules').map((r) => {
    if (typeof r.doc !== 'string') die(`${file}: rules entry "${r.pattern}" needs a "doc"`);
    return { ...r, docPath: path.resolve(dir, r.doc) };
  });
  const risk = compile(data.risk, 'risk').map((r) => {
    if (!TIERS.includes(r.tier)) die(`${file}: risk entry "${r.pattern}" has tier ${JSON.stringify(r.tier)} (expected standard or deep)`);
    return r;
  });
  return { layer, file, rules, risk };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const rootArg = opts.root || process.cwd();
  let root;
  try { root = git(rootArg, ['rev-parse', '--show-toplevel']).trim(); } catch (e) { die(`${rootArg} is not inside a git work tree`); }
  const files = readList(opts.files);
  const pluginRoot = opts.pluginRoot ? path.resolve(opts.pluginRoot) : path.resolve(__dirname, '..');
  const userManifest = opts.userManifest || path.join(os.homedir(), '.claude', 'review-rules', 'manifest.json');
  const layers = [
    loadManifest('project', path.join(root, '.reviewrules', 'manifest.json')),
    loadManifest('user', userManifest),
    loadManifest('built-in', path.join(pluginRoot, 'rules', 'manifest.json')),
  ].filter(Boolean);
  if (!layers.some((l) => l.layer === 'built-in')) die(`built-in manifest not found under ${pluginRoot}/rules`);

  const out = [];
  const docs = new Set();
  const hits = [];
  for (const file of files) {
    let doc = null;
    let layer = null;
    for (const l of layers) {
      const r = l.rules.find((x) => x.re.test(file));
      if (r) { doc = r.docPath; layer = l.layer; break; }
    }
    if (doc) docs.add(doc);
    let risk = { tier: 'standard', pattern: null, why: null, layer: null };
    for (const l of layers) {
      const r = l.risk.find((x) => x.re.test(file));
      if (r) { risk = { tier: r.tier, pattern: r.pattern, why: r.why || null, layer: l.layer }; break; }
    }
    if (risk.tier === 'deep') hits.push({ file, pattern: risk.pattern, why: risk.why, layer: risk.layer });
    out.push({ file, doc, layer, risk });
  }
  const result = {
    root,
    layers: layers.map((l) => ({ layer: l.layer, file: l.file, rules: l.rules.length, risk: l.risk.length })),
    files: out,
    docs: [...docs],
    risk: { tier: hits.length ? 'deep' : 'standard', hits },
  };
  if (!opts.noWrite) {
    const gd = path.resolve(root, git(root, ['rev-parse', '--git-dir']).trim());
    const target = path.join(gd, RULES_FILE);
    fs.writeFileSync(target, JSON.stringify(result, null, 2) + '\n');
    result.rulesFile = target;
  }
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

main();
