#!/usr/bin/env node
'use strict';
// gate-check: does this change stop for the user at P1 (proposal + specs) or P2 (design)?
//
//   node gate-check.cjs <p1|p2|p3|p6b> <change-dir>
//   exit 0  proceed  — announce the defaults and carry on
//   exit 10 stop     — run the independent review (p1/p2), then wait for the user
//   exit 1  error    — usage, or the change cannot be read; fix the call and re-run, a second failure is a stop
// p3 and p6b only read the settings: they stop under gates: supervised or unreadable settings, never on content.
// stdout: first line `stop` or `proceed`, then one `- <reason-id>: <detail>` line per reason.
//
// It reads files only (no network). Doubt resolves toward asking: an unreadable settings file or an unknown
// `gates` value means supervised (stop). That is the opposite of the hooks' fail-open on purpose: an error
// here would otherwise skip a human decision, where a hook error only lets one edit through.
// Structural facts (BREAKING, MODIFIED/REMOVED/RENAMED deltas) are what holds an agent that misjudges;
// [needs user] and the Decisions section are author-written reminders, not proof of a review.
// Design: docs/openspec-workflow-3-gates-design-2026-11-10.md §4. Tests: tests/gate-check.test.sh
const fs = require('fs');
const path = require('path');
const { findSpecFiles } = require('./validate-openspec-workflow.cjs');

const GATES = ['risk-based', 'supervised'];
const NEEDS_USER = /^\s*[-*]\s*\[needs user\]/im;

function read(file) {
  try { return fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n'); } catch { return null; }
}

// HTML comments and fenced code blocks hold templates and examples, not decisions.
function stripExamples(text) {
  return text.replace(/<!--[\s\S]*?-->/g, '').replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, '');
}

// The body of the first `## <title>` section (up to the next `## `), or null when there is none.
function section(text, title) {
  const m = text.match(new RegExp(`^##\\s+${title}\\b[^\\n]*\\n([\\s\\S]*?)(?=^##\\s|(?![\\s\\S]))`, 'm'));
  return m ? m[1] : null;
}

const unquote = (s) => s.replace(/^["']|["']$/g, '');

// Minimal front matter: `gates: <value>` and `high_risk_paths:` followed by `  - <glob>` lines.
function parseFrontMatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\s*(?:\n|$)/);
  if (!m) return { error: 'no closing --- for the front matter' };
  const out = {};
  let list = null;
  for (const line of m[1].split('\n')) {
    const item = line.match(/^\s+-\s+(.+?)\s*$/);
    if (item && list) { list.push(unquote(item[1])); continue; }
    const kv = line.match(/^([A-Za-z_]+):\s*(.*?)\s*$/);
    if (kv && kv[1] === 'gates') out.gates = unquote(kv[2]);
    list = kv && kv[1] === 'high_risk_paths' ? (out.highRiskPaths = []) : null;
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
    if (fm.highRiskPaths) settings.highRiskPaths = fm.highRiskPaths;
  }
  return settings;
}

function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') { re += '.*'; i++; }
    else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

// Path-like tokens of the Impact section: anything with a slash, without backticks or a leading ./
function impactPaths(proposal) {
  const body = section(proposal, 'Impact') || '';
  return body.split(/\s+/).map((t) => t.replace(/`/g, '').replace(/[,;:)]+$/, '').replace(/^\.\//, ''))
    .filter((t) => t.includes('/'));
}

function modeReasons(settings) {
  if (settings.error) return [{ id: 'settings-unreadable', detail: `${settings.error}; treated as supervised` }];
  if (settings.gates === 'supervised') return [{ id: 'supervised', detail: 'gates: supervised stops at every gate' }];
  return [];
}

function checkP1(changeDir, settings) {
  const reasons = modeReasons(settings);
  const proposal = stripExamples(read(path.join(changeDir, 'proposal.md')) || '');
  const decisions = section(proposal, 'Decisions');
  if (decisions === null) reasons.push({ id: 'no-decisions-section', detail: 'proposal.md has no ## Decisions section' });
  else if (NEEDS_USER.test(decisions)) reasons.push({ id: 'needs-user', detail: '## Decisions lists a [needs user] item' });
  if (/\bBREAKING\b/.test(proposal)) reasons.push({ id: 'breaking', detail: 'proposal.md marks a BREAKING change' });
  const kinds = new Set();
  for (const spec of findSpecFiles(changeDir)) {
    for (const m of stripExamples(read(spec) || '').matchAll(/^##\s+(MODIFIED|REMOVED|RENAMED)\s+Requirements/gm)) kinds.add(m[1]);
  }
  if (kinds.size) reasons.push({ id: 'delta-modified', detail: `spec deltas change existing requirements: ${[...kinds].sort().join(', ')}` });
  const hits = [];
  const paths = impactPaths(proposal);
  for (const glob of settings.highRiskPaths) {
    const re = globToRegExp(glob);
    for (const p of paths) if (re.test(p)) hits.push(`${p} (${glob})`);
  }
  if (hits.length) reasons.push({ id: 'high-risk-path', detail: `## Impact names high-risk paths: ${hits.join(', ')}` });
  return { stop: reasons.length > 0, reasons };
}

function checkP2(changeDir, settings) {
  const reasons = modeReasons(settings);
  const design = stripExamples(read(path.join(changeDir, 'design.md')) || '');
  const open = section(design, 'Open Questions');
  if (open !== null && NEEDS_USER.test(open)) reasons.push({ id: 'design-needs-user', detail: '## Open Questions lists a [needs user] item' });
  return { stop: reasons.length > 0, reasons };
}

// Phase 3 → 4 and Step 6b: no content rule, only the settings can stop them.
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
  const settings = readSettings(path.dirname(path.dirname(changes)));
  const result = check(changeDir, settings);
  console.log(result.stop ? 'stop' : 'proceed');
  for (const r of result.reasons) console.log(`- ${r.id}: ${r.detail}`);
  return result.stop ? 10 : 0;
}

module.exports = { readSettings, checkP1, checkP2 };
if (require.main === module) process.exitCode = main(process.argv.slice(2));
