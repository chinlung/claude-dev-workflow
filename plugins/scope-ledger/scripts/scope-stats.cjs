#!/usr/bin/env node
'use strict';

/**
 * scope-stats — what happened to the findings each review tool produced, read back from the ledgers.
 *
 * A review tool's noise is measured by what the person (or agent) did with its findings, not by
 * what the tool says about itself. The ledger already records that per round:
 *
 *   - <date> <tool> r<N>: <n> findings → <f> fixed / <d> deferred / <w> wrong / <i> intentional / <m> moot
 *
 * (the 1.0.x form `<a> adopted / <d> deferred / <x> noise` is read too: adopted → fixed, noise → wrong).
 * This script walks the ledgers and follow-ups of one or more projects, sums those lines per tool,
 * and prints precision = (fixed + deferred) / findings — the number that decides whether a second
 * opinion earns its cost, or whether a pilot tool stays. Open items are counted per source as well,
 * so a tool whose findings keep landing in Deferred shows up.
 *
 *   node scope-stats.cjs [--project <dir>]... [--all] [--projects-root <dir>] [--json]
 *
 * --project <dir>    a project whose <dir>/.claude/scope-ledger.local.md and scope-followups.local.md
 *                    are read (repeatable; default: the current directory)
 * --all              also every project Claude Code has a directory for under <projects-root>
 *                    (~/.claude/projects by default): the directory name encodes the path
 *                    (-Users-x-repo), which is decoded by trying each split against the file system
 * --json             machine-readable output instead of the table
 *
 * Nothing here judges a finding; it counts what the ledger says was judged. Exit 2 on usage errors.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const LEDGER = path.join('.claude', 'scope-ledger.local.md');
const FOLLOWUPS = path.join('.claude', 'scope-followups.local.md');
const BUCKETS = ['fixed', 'deferred', 'wrong', 'intentional', 'moot'];
const ALIASES = { adopted: 'fixed', noise: 'wrong', moot: 'moot', 'didnt-matter': 'moot', irrelevant: 'moot' };

function die(msg) {
  process.stderr.write(`scope-stats: ${msg}\n`);
  process.exit(2);
}

function parseArgs(list) {
  const opts = { projects: [], all: false, json: false, projectsRoot: path.join(os.homedir(), '.claude', 'projects') };
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a === '--all') opts.all = true;
    else if (a === '--json') opts.json = true;
    else if (a === '--project' && list[i + 1] !== undefined) { opts.projects.push(list[++i]); }
    else if (a === '--projects-root' && list[i + 1] !== undefined) { opts.projectsRoot = list[++i]; }
    else if (a === '-h' || a === '--help') { process.stdout.write('usage: scope-stats.cjs [--project <dir>]... [--all] [--projects-root <dir>] [--json]\n'); process.exit(0); }
    else die(`unknown argument ${a}`);
  }
  if (opts.projects.length === 0 && !opts.all) opts.projects.push(process.cwd());
  return opts;
}

// `-Users-scl-web-my-repo` → `/Users/scl/web/my-repo`: every `-` is either a path separator or a
// literal hyphen. Descending with `/` is only allowed from a prefix that exists as a directory, but
// a prefix that does NOT exist is not dead — `/tmp/claude` is the start of `/tmp/claude-501` — so the
// hyphen branch is always tried too; the candidate must exist once every token is placed.
function decodeProjectDirName(name) {
  if (!name.startsWith('-')) return null;
  const tokens = name.slice(1).split('-');
  const seen = new Set();
  function walk(prefix, i) {
    if (i === tokens.length) return fs.existsSync(prefix) ? prefix : null;
    const key = `${prefix}\u0000${i}`;
    if (seen.has(key)) return null;
    seen.add(key);
    let r = null;
    if (prefix === '' || fs.existsSync(prefix)) r = walk(`${prefix}/${tokens[i]}`, i + 1);
    if (r === null && prefix !== '') r = walk(`${prefix}-${tokens[i]}`, i + 1);
    return r;
  }
  return walk('', 0);
}

function listProjectsFromRoot(root) {
  let names = [];
  try { names = fs.readdirSync(root); } catch (e) { return []; }
  const out = [];
  for (const n of names) {
    const p = decodeProjectDirName(n);
    if (p && fs.existsSync(path.join(p, '.claude'))) out.push(p);
  }
  return out;
}

const LOG_LINE = /^- (.*?)\s(\S+) r(\d+):\s*(\d+)\s*(?:findings?)?\s*→\s*(.*)$/u;

// Tail of a Log line → bucket counts. Accepts "3 fixed / 1 wrong" and "fixed 3 / wrong 1".
function parseTail(tail) {
  const counts = Object.fromEntries(BUCKETS.map((b) => [b, 0]));
  let recognised = false;
  for (const part of tail.split(/\s*\/\s*/)) {
    let m = /^(\d+)\s+([A-Za-z-]+)$/.exec(part.trim()) || /^([A-Za-z-]+)\s+(\d+)$/.exec(part.trim());
    if (!m) continue;
    const n = Number(/^\d+$/.test(m[1]) ? m[1] : m[2]);
    const wordRaw = (/^\d+$/.test(m[1]) ? m[2] : m[1]).toLowerCase();
    const word = ALIASES[wordRaw] || wordRaw;
    if (!BUCKETS.includes(word)) continue;
    counts[word] += n;
    recognised = true;
  }
  return recognised ? counts : null;
}

// In scope / Deferred lines carry `← 來源: x`; follow-ups lines carry `｜ 來源: x` after `← from:`.
const SOURCE_RE = /(?:←|[｜|])\s*(?:來源|source):\s*([^｜|]+?)\s*(?:[｜|].*)?$/u;
// One tool, one row. The triage hook tags a source with the name the review was invoked by — the
// qualified form when the model called the Skill (`code-audit-rigor:review-branch@r1`), the short form
// when the user typed the slash command (`review-branch@r1`) — and a Log line is usually written short.
// Only the aliases below are merged; "take the part after the last colon" would merge different tools
// (`pr-review-toolkit:review-pr` vs `code-audit-rigor:review-pr`, `engineering:code-review` vs the
// built-in `code-review`) and split one (`claude-security:scan` vs `claude-security`). An unknown
// qualified name stays as written.
const TOOL_ALIASES = {
  'code-audit-rigor:review-branch': 'review-branch',
  'code-audit-rigor:review-pr': 'review-pr',
  'security-audit:security-audit': 'security-audit',
  'multi-agent-debate:debate': 'debate',
  'high-precision-dev:start': 'high-precision-dev',
  'claude-security:scan': 'claude-security',
  'claude-security:claude-security': 'claude-security',
  'codex:review': 'codex',
  'codex:adversarial-review': 'codex',
  'codex-review-bg': 'codex',
  'codex-review': 'codex',
  'codex_review': 'codex',
};
function toolKey(name) {
  const t = String(name).trim();
  return Object.prototype.hasOwnProperty.call(TOOL_ALIASES, t) ? TOOL_ALIASES[t] : t;
}
function sourceTool(line) {
  const m = SOURCE_RE.exec(line.replace(/\s*<!-- scope:[A-Za-z0-9_]+ .*-->\s*$/u, ''));
  if (!m) return null;
  const src = m[1].trim();
  const at = src.lastIndexOf('@r');
  return toolKey(at > 0 ? src.slice(0, at) : src);
}

function readLedger(project) {
  const file = path.join(project, LEDGER);
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
  const out = { project, file, goal: null, mode: null, review_rounds: null, log: [], unparsedLog: [], open: {}, deferred: {} };
  let section = null;
  let fm = false;
  text.split(/\r?\n/).forEach((raw, idx) => {
    if (idx === 0 && raw === '---') { fm = true; return; }
    if (fm) {
      if (raw === '---') { fm = false; return; }
      const m = /^([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$/.exec(raw);
      if (m && (m[1] === 'goal' || m[1] === 'mode' || m[1] === 'review_rounds')) out[m[1]] = m[1] === 'review_rounds' ? Number(m[2]) : m[2];
      return;
    }
    if (raw.startsWith('## ')) { section = raw.slice(3); return; }
    if (section === 'Log' && raw.startsWith('- ')) {
      const m = LOG_LINE.exec(raw);
      const counts = m ? parseTail(m[5]) : null;
      if (m && counts) out.log.push({ tool: toolKey(m[2]), round: Number(m[3]), findings: Number(m[4]), ...counts });
      else if (/→/.test(raw)) out.unparsedLog.push(idx + 1);
      return;
    }
    if (section === 'In scope' && /^- \[ \] /.test(raw)) {
      const t = sourceTool(raw) || 'unknown';
      out.open[t] = (out.open[t] || 0) + 1;
    }
    if (section === 'Deferred' && raw.startsWith('- ')) {
      const t = sourceTool(raw) || 'unknown';
      out.deferred[t] = (out.deferred[t] || 0) + 1;
    }
  });
  return out;
}

function readFollowups(project) {
  const file = path.join(project, FOLLOWUPS);
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
  const open = {};
  for (const raw of text.split(/\r?\n/)) {
    if (!/^- \[ \] /.test(raw)) continue;
    const t = sourceTool(raw) || 'unknown';
    open[t] = (open[t] || 0) + 1;
  }
  return { project, file, open };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const projects = new Set(opts.projects.map((p) => path.resolve(p)));
  if (opts.all) for (const p of listProjectsFromRoot(opts.projectsRoot)) projects.add(p);

  const ledgers = [];
  const followups = [];
  for (const p of projects) {
    const l = readLedger(p);
    if (l) ledgers.push(l);
    const f = readFollowups(p);
    if (f) followups.push(f);
  }

  const perTool = {};
  const tool = (t) => (perTool[t] = perTool[t] || { rounds: 0, findings: 0, ...Object.fromEntries(BUCKETS.map((b) => [b, 0])), open: 0, deferredOpen: 0, followupsOpen: 0 });
  for (const l of ledgers) {
    for (const e of l.log) {
      const t = tool(e.tool);
      t.rounds += 1;
      t.findings += e.findings;
      for (const b of BUCKETS) t[b] += e[b];
    }
    for (const [k, v] of Object.entries(l.open)) tool(k).open += v;
    for (const [k, v] of Object.entries(l.deferred)) tool(k).deferredOpen += v;
  }
  for (const f of followups) for (const [k, v] of Object.entries(f.open)) tool(k).followupsOpen += v;
  for (const t of Object.values(perTool)) {
    const judged = t.fixed + t.deferred + t.wrong + t.intentional + t.moot;
    t.judged = judged;
    t.precision = judged > 0 ? Math.round(((t.fixed + t.deferred) / judged) * 1000) / 10 : null;
  }

  const result = {
    projects: [...projects],
    ledgers: ledgers.map((l) => ({ project: l.project, goal: l.goal, mode: l.mode, review_rounds: l.review_rounds, logLines: l.log.length, unparsedLog: l.unparsedLog })),
    tools: perTool,
  };
  if (opts.json) {
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    return;
  }
  const names = Object.keys(perTool).sort();
  process.stdout.write(`projects scanned: ${projects.size}, ledgers: ${ledgers.length}, follow-ups files: ${followups.length}\n`);
  if (names.length === 0) { process.stdout.write('no review rounds recorded yet\n'); return; }
  const head = ['tool', 'rounds', 'findings', 'fixed', 'deferred', 'wrong', 'intentional', 'moot', 'precision%', 'open', 'deferred-open', 'followups-open'];
  const rows = names.map((n) => { const t = perTool[n]; return [n, t.rounds, t.findings, t.fixed, t.deferred, t.wrong, t.intentional, t.moot, t.precision === null ? '-' : t.precision, t.open, t.deferredOpen, t.followupsOpen].map(String); });
  const widths = head.map((h, i) => Math.max(h.length, ...rows.map((r) => r[i].length)));
  const line = (cells) => cells.map((c, i) => c.padEnd(widths[i])).join('  ') + '\n';
  process.stdout.write(line(head));
  process.stdout.write(line(widths.map((w) => '-'.repeat(w))));
  for (const r of rows) process.stdout.write(line(r));
  const unparsed = ledgers.filter((l) => l.unparsedLog.length);
  for (const l of unparsed) process.stdout.write(`note: ${l.file} has Log lines with → that did not parse (lines ${l.unparsedLog.join(', ')})\n`);
  process.stdout.write('precision = (fixed + deferred) / judged; wrong = the reviewer was mistaken, intentional = the behaviour was by design, moot = true but did not matter\n');
}

main();
