#!/usr/bin/env node
'use strict';
// gate-check: does this change stop for the user at P1 (proposal + specs), P2 (design), Phase 3 → 4 or Step 6b?
//
//   node gate-check.cjs <p1|p2|p3|p6b> <change-dir>
//   exit 0  proceed  — announce the defaults and carry on
//   exit 10 stop     — run the independent review (p1/p2), then wait for the user
//   exit 1  error    — usage, or the change cannot be read; fix the call and re-run, a second failure is a stop
// p3 and p6b stop only under gates: supervised or unreadable settings; p3 first checks the tasks.md format
// (one checkbox per "### Task N") and exits 1 when it is broken.
// stdout: first line `stop` or `proceed`, then one `- <reason-id>: <detail>` line per reason.
//
// No network; the only write is the P1 record (see recordPath). Doubt resolves toward asking: an unreadable settings file or an unknown
// `gates` value means supervised (stop). That is the opposite of the hooks' fail-open on purpose: an error
// here would otherwise skip a human decision, where a hook error only lets one edit through.
// Structural facts (BREAKING, MODIFIED/REMOVED/RENAMED deltas) are what holds an agent that misjudges;
// [needs user] and the Decisions section are author-written reminders, not proof of a review.
// Design: docs/openspec-workflow-3-gates-design-2026-11-10.md §4. Tests: tests/gate-check.test.sh
const fs = require('fs');
const path = require('path');
const { findSpecFiles } = require('./validate-openspec-workflow.cjs');
const { parseTaskLines } = require('./task-line.cjs');
const { writeStateFile } = require('./safe-write.cjs');

const GATES = ['risk-based', 'supervised'];
// The marker counts anywhere in the document (any bullet style, any heading): a stricter reading than the
// docs promise would let a decision slip through silently.
const NEEDS_USER = /\[needs user\]/i;

function read(file) {
  try { return fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n'); } catch { return null; }
}

// HTML comments and fenced code blocks hold templates and examples, not decisions.
// Fenced code blocks and HTML comments hold templates and examples, not decisions. One pass over the lines with
// block state, so neither can pair across the other (a ``` line inside a comment, ``` inside a ~~~ fence):
// - a fence opens on a line starting (after up to 3 spaces) with 3+ backticks or tildes; a backtick fence's
//   opening line has no other backtick (CommonMark), so ```x``` is a code span; it closes on a line of the same
//   character, at least as long, and nothing else;
// - outside fences, `<!--` opens a comment unless it sits inside an inline code span, and `-->` closes it.
function stripExamples(text) {
  const out = [];
  let fence = null;
  let inComment = false;
  for (const line of text.split('\n')) {
    if (fence) {
      const close = line.match(/^ {0,3}(`{3,}|~{3,})[ \t]*$/);
      if (close && close[1][0] === fence[0] && close[1].length >= fence.length) fence = null;
      continue;
    }
    if (!inComment) {
      const open = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
      if (open && !(open[1][0] === '`' && open[2].includes('`'))) { fence = open[1]; continue; }
    }
    const masked = line.replace(/`[^`\n]*`/g, (m) => ' '.repeat(m.length));
    let kept = '';
    let i = 0;
    while (i <= line.length) {
      if (inComment) {
        const j = line.indexOf('-->', i);
        if (j < 0) { i = line.length + 1; break; }
        inComment = false;
        i = j + 3;
      } else {
        const j = masked.indexOf('<!--', i);
        if (j < 0) { kept += line.slice(i); break; }
        kept += line.slice(i, j);
        inComment = true;
        i = j + 4;
      }
    }
    out.push(kept);
  }
  return out.join('\n');
}

// The body of the first `## <title>` section (up to the next `## `), or null when there is none.
function section(text, title) {
  const m = text.match(new RegExp(`^##\\s+${title}\\b[^\\n]*\\n([\\s\\S]*?)(?=^##\\s|(?![\\s\\S]))`, 'm'));
  return m ? m[1] : null;
}

const unquote = (s) => s.replace(/^["']|["']$/g, '');

// A YAML comment starts at `#` at the line start or after whitespace, outside quotes.
function stripComment(line) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote) { if (c === quote) quote = null; }
    else if (c === '"' || c === "'") quote = c;
    else if (c === '#' && (i === 0 || /\s/.test(line[i - 1]))) return line.slice(0, i);
  }
  return line;
}

// Minimal front matter: `gates: <value>` and `high_risk_paths:` followed by `- <glob>` lines (indented or not;
// blank and comment lines in between are fine). Any other shape is an error rather than a silently empty list:
// an empty high_risk_paths would let a high-risk change proceed.
function parseFrontMatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\s*(?:\n|$)/);
  if (!m) return { error: 'no closing --- for the front matter' };
  const out = {};
  let list = null;
  for (const raw of m[1].split('\n')) {
    const line = stripComment(raw).trimEnd();
    if (!line.trim()) continue;
    const item = line.match(/^\s*-\s+(.+)$/);
    if (item) {
      if (!list) return { error: `list item "${item[1]}" does not belong to a key` };
      list.push(unquote(item[1]));
      continue;
    }
    const kv = line.match(/^([A-Za-z_]+):\s*(.*)$/);
    if (!kv) return { error: `cannot read "${line.trim()}"` };
    if (kv[1] === 'gates') {
      if (out.gates !== undefined) return { error: 'gates is set twice' };
      out.gates = unquote(kv[2]); list = null;
    }
    else if (kv[1] === 'high_risk_paths') {
      if (kv[2] !== '') return { error: 'high_risk_paths must be followed by "- <glob>" lines, not an inline value' };
      list = out.highRiskPaths = [];
    } else return { error: `unknown key "${kv[1]}" (expected gates or high_risk_paths)` };
  }
  return out;
}

// .claude/openspec-workflow.md (committed) then .claude/openspec-workflow.local.md: a key the local file sets wins.
function readSettings(projectRoot) {
  const settings = { gates: 'risk-based', highRiskPaths: [], error: null };
  for (const name of ['openspec-workflow.md', 'openspec-workflow.local.md']) {
    const file = path.join(projectRoot, '.claude', name);
    if (!fs.existsSync(file)) continue;
    const text = read(file);
    const fm = text === null ? { error: 'cannot read the file' } : parseFrontMatter(text);
    if (fm.error) { settings.error = `.claude/${name}: ${fm.error}`; continue; }
    if (fm.gates !== undefined) {
      if (GATES.includes(fm.gates)) settings.gates = fm.gates;
      else settings.error = `.claude/${name}: gates is "${fm.gates}", expected ${GATES.join(' or ')}`;
    }
    // Union: a personal file can add high-risk paths but never drop the project's.
    if (fm.highRiskPaths) settings.highRiskPaths = [...new Set([...settings.highRiskPaths, ...fm.highRiskPaths])];
  }
  return settings;
}

function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      if (glob[i + 2] === '/') { re += '(?:.*/)?'; i += 2; }   // `**/` also matches zero directories
      else { re += '.*'; i++; }
    }
    else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

// Every word of the Impact section is a candidate path (a root-level `Dockerfile` has no slash). Brackets,
// quotes, bold and table bars only wrap a path, so they split words (`[x](src/a.ts)` gives `x` and `src/a.ts`);
// trailing punctuation and a leading ./ or / go; a directory is tried with and without its trailing slash.
function impactPaths(proposal) {
  const body = section(proposal, 'Impact') || '';
  const out = [];
  for (const w of body.split(/[\s()[\]<>"'`*|]+/)) {
    const t = w.replace(/[,;:.]+$/, '').replace(/^\.?\//, '').replace(/\/+$/, '');
    if (t) out.push(t, `${t}/`);
  }
  return out;
}

function modeReasons(settings) {
  if (settings.error) return [{ id: 'settings-unreadable', detail: `${settings.error}; treated as supervised` }];
  if (settings.gates === 'supervised') return [{ id: 'supervised', detail: 'gates: supervised stops at every gate' }];
  return [];
}

// The structural facts of a change: what holds an agent that misjudges, and what P2 compares against P1.
function structure(changeDir, settings) {
  const proposal = stripExamples(read(path.join(changeDir, 'proposal.md')) || '');
  const breaking = /\bBREAKING\b/.test(proposal);
  const kindSet = new Set();
  const unreadable = [];
  const specs = findSpecFiles(changeDir);
  for (const spec of specs) {
    const text = read(spec);
    if (text === null) { unreadable.push(path.relative(changeDir, spec)); continue; }
    for (const m of stripExamples(text).matchAll(/^##\s+(MODIFIED|REMOVED|RENAMED)\s+Requirements/gim)) kindSet.add(m[1].toUpperCase());
  }
  const kinds = [...kindSet].sort();
  const hitSet = new Set();
  const paths = impactPaths(proposal);
  for (const glob of settings.highRiskPaths) {
    const re = globToRegExp(glob);
    for (const p of paths) if (re.test(p)) hitSet.add(`${p.replace(/\/$/, '')} (${glob})`);
  }
  const hits = [...hitSet];
  const facts = [...(breaking ? ['BREAKING'] : []), ...kinds.map((k) => `${k} delta`), ...hits.map((h) => `high-risk ${h}`)];
  return { proposal, breaking, kinds, hits, facts, specCount: specs.length, unreadable };
}

function checkP1(changeDir, settings) {
  const reasons = modeReasons(settings);
  const s = structure(changeDir, settings);
  if (section(s.proposal, 'Decisions') === null) reasons.push({ id: 'no-decisions-section', detail: 'proposal.md has no ## Decisions section' });
  if (NEEDS_USER.test(s.proposal)) reasons.push({ id: 'needs-user', detail: 'proposal.md has a [needs user] item' });
  if (s.breaking) reasons.push({ id: 'breaking', detail: 'proposal.md marks a BREAKING change' });
  // OpenSpec lets a pure refactor or tooling change opt out of specs with `skip_specs: true` in .openspec.yaml.
  const skipSpecs = /^skip_specs:\s*true\s*$/m.test(read(path.join(changeDir, '.openspec.yaml')) || '');
  if (s.specCount === 0 && !skipSpecs) reasons.push({ id: 'no-specs', detail: 'no specs/**/spec.md and .openspec.yaml does not set skip_specs: true' });
  if (s.unreadable.length) reasons.push({ id: 'spec-unreadable', detail: `cannot read ${s.unreadable.join(', ')}` });
  if (s.kinds.length) reasons.push({ id: 'delta-modified', detail: `spec deltas change existing requirements: ${s.kinds.join(', ')}` });
  if (s.hits.length) reasons.push({ id: 'high-risk-path', detail: `## Impact names high-risk paths: ${s.hits.join(', ')}` });
  return { stop: reasons.length > 0, reasons, facts: s.facts };
}

// What P1 saw, so P2 can tell a structural fact added after P1 (a new delta, a BREAKING marker) from one the
// user was already shown. Written by every `p1` run; kept beside reconcile-check's state.
// <root>/openspec/changes/<name> → <root>
const projectRoot = (changeDir) => path.dirname(path.dirname(path.dirname(changeDir)));
function recordPath(changeDir) {
  return path.join(projectRoot(changeDir), '.claude', `openspec-gate.${path.basename(changeDir)}.local.json`);
}

function checkP2(changeDir, settings) {
  const reasons = modeReasons(settings);
  const raw = read(path.join(changeDir, 'design.md'));
  if (raw === null) {
    reasons.push({ id: 'design-unreadable', detail: 'design.md is missing or cannot be read' });
    return { stop: true, reasons };
  }
  if (NEEDS_USER.test(stripExamples(raw))) reasons.push({ id: 'design-needs-user', detail: 'design.md has a [needs user] item' });
  let seen = null;
  try { seen = JSON.parse(fs.readFileSync(recordPath(changeDir), 'utf8')).facts; } catch { /* no record */ }
  if (!Array.isArray(seen)) {
    reasons.push({ id: 'no-p1-record', detail: 'no readable record of the P1 check; run gate-check p1 first' });
  } else {
    const added = structure(changeDir, settings).facts.filter((f) => !seen.includes(f));
    if (added.length) reasons.push({ id: 'structure-changed-since-p1', detail: `new since P1: ${added.join(', ')}` });
  }
  return { stop: reasons.length > 0, reasons };
}

// P3 format rule: every "### Task N" section holds exactly one checkbox (the task line OpenSpec counts), and no
// checkbox sits outside them. A broken tasks.md is the agent's to fix, so it is an error (exit 1), not a stop.
function tasksFormatErrors(changeDir) {
  const text = read(path.join(changeDir, 'tasks.md'));
  if (text === null) return ['tasks.md is missing or cannot be read'];
  const parts = stripExamples(text).split(/^(?=###\s+Task\b)/m);
  const head = /^###\s+Task\b/.test(parts[0]) ? null : parts.shift();
  const errors = [];
  if (!parts.length) errors.push('tasks.md has no "### Task N" heading');
  if (head && parseTaskLines(head).length) errors.push('a checkbox sits outside every "### Task N" section');
  for (const part of parts) {
    const name = part.match(/^###\s+(Task\b[^:\n]*)/)[1].trim();
    const n = parseTaskLines(part).length;
    if (n !== 1) errors.push(`${name} has ${n} checkboxes, expected exactly 1`);
  }
  return errors;
}

// Phase 3 → 4 and Step 6b: beyond the format rule above, only the settings can stop them.
function checkSettingsOnly(_changeDir, settings) {
  const reasons = modeReasons(settings);
  return { stop: reasons.length > 0, reasons };
}

const CHECKS = { p1: checkP1, p2: checkP2, p3: checkSettingsOnly, p6b: checkSettingsOnly };

function main(argv) {
  const [gate, dir] = argv;
  const check = Object.hasOwn(CHECKS, gate) ? CHECKS[gate] : null;
  if (!check || !dir) {
    console.error(`usage: gate-check.cjs <${Object.keys(CHECKS).join('|')}> <openspec/changes/<name>>`);
    return 1;
  }
  const changeDir = path.resolve(dir);
  const changes = path.dirname(changeDir);
  if (path.basename(changes) !== 'changes' || path.basename(path.dirname(changes)) !== 'openspec') {
    console.error(`gate-check: ${dir} is not under openspec/changes`);
    return 1;
  }
  if (!fs.existsSync(path.join(changeDir, 'proposal.md'))) {
    console.error(`gate-check: ${dir} has no proposal.md`);
    return 1;
  }
  if (gate === 'p3') {
    const errors = tasksFormatErrors(changeDir);
    if (errors.length) {
      for (const e of errors) console.error(`gate-check: ${e}`);
      return 1;
    }
  }
  const settings = readSettings(projectRoot(changeDir));
  const result = check(changeDir, settings);
  if (gate === 'p1') {
    try {
      writeStateFile(recordPath(changeDir), `${JSON.stringify({ facts: result.facts }, null, 2)}\n`);
    } catch (e) {
      // A stale record that stays readable would let P2 wave through a fact this run no longer saw.
      console.error(`gate-check: cannot write the P1 record (${e.message}); fix it and run p1 again`);
      return 1;
    }
  }
  console.log(result.stop ? 'stop' : 'proceed');
  for (const r of result.reasons) console.log(`- ${r.id}: ${r.detail}`);
  return result.stop ? 10 : 0;
}

module.exports = { readSettings, checkP1, checkP2 };
if (require.main === module) process.exitCode = main(process.argv.slice(2));
