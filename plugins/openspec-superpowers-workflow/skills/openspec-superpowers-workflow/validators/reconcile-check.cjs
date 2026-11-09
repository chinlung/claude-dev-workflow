#!/usr/bin/env node
'use strict';
// Phase 6 mechanical checks before an OpenSpec change is archived.
//   snapshot <change-dir>        record the hash of tasks.md (run when Phase 6 starts; refused, exit 1, while R6 fails)
//   check    <change-dir> [--json]  run R1–R9; with no fail, record a pass verdict pinned to the
//                                    hashes of proposal, design, tasks, review-notes and specs
//   verify   <change-dir>        exit 0 when that verdict exists, was recorded under the current RULES, and none of those files changed
// State: <project>/.claude/openspec-reconcile.<change>.local.json. The archive gate hook calls
// `verify`; the checks that need judgment (C1, C2, C5) are printed as `manual`, not decided here.
// Exit codes: 0 pass / fresh, 1 check failed, 2 usage or a path outside openspec/changes/,
// 3 verify found no verdict or a stale one — a code node never produces by itself, so the archive
// gate can tell "the change is not ready" from "the checker crashed" (exit 1) by exit code alone.
// Design: docs/openspec-workflow-2-design-2026-11-09.md §4.1. Tests: tests/reconcile-check.test.sh

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const { REQUIRED_FILES, findSpecFiles, checkRequirementBlocks } = require('./validate-openspec-workflow.cjs');
const { parseTaskLines } = require('./task-line.cjs');

const ARTIFACTS = { proposal: 'proposal.md', design: 'design.md', tasks: 'tasks.md', reviewNotes: 'review-notes.md' };
// Bump when a check gets stricter: a pass verdict is pinned to the rules that produced it, so verify rejects one
// recorded under older rules even when no artifact changed (2 = R6 fails on an unfinished task without a skip reason).
const RULES = 2;
const USAGE = 'Usage: reconcile-check.cjs snapshot|check|verify <openspec/changes/<name>> [--json]';

function resolveChange(arg) {
  if (!arg) return null;
  const changeDir = path.resolve(arg);
  const parent = path.dirname(changeDir);
  if (path.basename(parent) !== 'changes' || path.basename(path.dirname(parent)) !== 'openspec') return null;
  const projRoot = path.resolve(changeDir, '../../..');
  const name = path.basename(changeDir);
  const read = (rel) => {
    try { return fs.readFileSync(path.join(changeDir, rel), 'utf8').replace(/\r\n/g, '\n'); } catch { return null; }
  };
  let parsedRounds;
  const reviewRounds = () => (parsedRounds ??= rounds(read(ARTIFACTS.reviewNotes)));
  return { changeDir, projRoot, name, read, reviewRounds, statePath: path.join(projRoot, '.claude', `openspec-reconcile.${name}.local.json`) };
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
function fileHash(ctx, rel) {
  try { return sha256(fs.readFileSync(path.join(ctx.changeDir, rel))); } catch { return 'missing'; }
}
function specRelPaths(ctx) {
  return findSpecFiles(ctx.changeDir).map((f) => path.relative(ctx.changeDir, f)).sort();
}
function specsHash(ctx) {
  const h = crypto.createHash('sha256');
  for (const rel of specRelPaths(ctx)) {
    h.update(rel + '\0');
    h.update(fs.readFileSync(path.join(ctx.changeDir, rel)));
    h.update('\0');
  }
  return h.digest('hex');
}
function hashes(ctx) {
  const out = {};
  for (const [key, rel] of Object.entries(ARTIFACTS)) out[key] = fileHash(ctx, rel);
  out.specs = specsHash(ctx);
  return out;
}

function readState(ctx) {
  try { return JSON.parse(fs.readFileSync(ctx.statePath, 'utf8')); } catch { return {}; }
}
function writeState(ctx, state) {
  fs.mkdirSync(path.dirname(ctx.statePath), { recursive: true });
  fs.writeFileSync(ctx.statePath, JSON.stringify(state, null, 2) + '\n');
}

// review-notes.md → [{ heading, entries }]; an entry is a `- [` bullet under a `## Round` heading.
function rounds(notes) {
  const out = [];
  let cur = null;
  for (const line of (notes || '').split('\n')) {
    if (/^##\s+Round\b/i.test(line)) { cur = { heading: line.trim(), entries: [] }; out.push(cur); continue; }
    if (/^##\s/.test(line)) { cur = null; continue; }
    if (cur && /^\s*-\s*\[/.test(line)) cur.entries.push(line.trim());
  }
  return out;
}
const ENTRY = /^-\s*\[(REQUIREMENT|DESIGN|CODE|CONSTITUTION)\]\s*([YN])\b/;
function badEntry(entry) {
  const m = entry.match(ENTRY);
  return !m || (m[1] === 'CODE' && m[2] === 'Y');
}

const result = (status, detail = []) => ({ status, detail });

function checkR1(ctx) {
  const detail = REQUIRED_FILES.filter((f) => !fs.existsSync(path.join(ctx.changeDir, f))).map((f) => `missing ${f}`);
  if (findSpecFiles(ctx.changeDir).length === 0) detail.push('no specs/**/spec.md');
  return result(detail.length ? 'fail' : 'pass', detail);
}

function checkR2(ctx) {
  const detail = [];
  for (const rel of specRelPaths(ctx)) detail.push(...checkRequirementBlocks(rel, ctx.read(rel) || ''));
  return result(detail.length ? 'fail' : 'pass', detail);
}

function checkR3(ctx) {
  const rs = ctx.reviewRounds();
  const detail = [];
  let lastRoundBad = false;
  rs.forEach((r, i) => {
    for (const e of r.entries) {
      if (!badEntry(e)) continue;
      detail.push(`${r.heading}: ${e}`);
      if (i === rs.length - 1) lastRoundBad = true;
    }
  });
  return result(lastRoundBad ? 'fail' : detail.length ? 'warn' : 'pass', detail);
}

function checkR4(ctx) {
  const rs = ctx.reviewRounds();
  if (rs.length === 0) return result('warn', ['review-notes.md has no ## Round section']);
  const last = rs[rs.length - 1].heading;
  if (/final/i.test(last)) return result('pass');
  return result('fail', [`last round is not marked final: "${last}" — add "final" to it only after the user says review has converged`]);
}

function checkR5(ctx) {
  const snap = readState(ctx).snapshot;
  if (snap && snap.tasks) {
    return snap.tasks === fileHash(ctx, ARTIFACTS.tasks) ? result('pass') : result('fail', ['tasks.md changed since the snapshot']);
  }
  const rel = path.relative(ctx.projRoot, path.join(ctx.changeDir, ARTIFACTS.tasks));
  try {
    execFileSync('git', ['-C', ctx.projRoot, 'ls-files', '--error-unmatch', '--', rel], { stdio: 'ignore' });
  } catch {
    return result('warn', ['no snapshot, and tasks.md is not tracked by git: run `snapshot` when Phase 6 starts']);
  }
  try {
    execFileSync('git', ['-C', ctx.projRoot, 'diff', '--quiet', 'HEAD', '--', rel], { stdio: 'ignore' });
    return result('pass', ['no snapshot; tasks.md matches HEAD']);
  } catch {
    return result('fail', ['no snapshot, and tasks.md differs from HEAD']);
  }
}

// A task is whatever OpenSpec counts as one (task-line.cjs, same pattern as the CLI). An unfinished one needs
// "skip:" and a reason with at least one letter or digit; "skip:" alone or followed by punctuation is not one.
function checkR6(ctx) {
  const boxes = parseTaskLines(ctx.read(ARTIFACTS.tasks));
  if (boxes.length === 0) return result('warn', ['tasks.md has no checkbox task']);
  const open = boxes.filter((t) => !t.done && !t.skipped);
  if (open.length === 0) return result('pass');
  return result('fail', [`${open.length} unchecked task(s) without "skip: <reason>" (the reason needs a letter or digit)`, ...open.map(({ line, no }) => `line ${no}: ${line.trim()}`)]);
}

const PATCH_LANGUAGE = [/修訂[：:]/, /原本(是|為)/, /\bRound \d+\b/i, /review-notes/, /\bpreviously\b/i];
function checkR7(ctx) {
  const detail = [];
  for (const rel of [ARTIFACTS.proposal, ARTIFACTS.design, ...specRelPaths(ctx)]) {
    const text = ctx.read(rel);
    if (text == null) continue;
    text.split('\n').forEach((line, i) => {
      if (PATCH_LANGUAGE.some((re) => re.test(line))) detail.push(`${rel}:${i + 1}: ${line.trim().slice(0, 120)}`);
    });
  }
  return result(detail.length ? 'warn' : 'pass', detail);
}

function checkR8(ctx) {
  const entries = [];
  for (const r of ctx.reviewRounds()) {
    for (const e of r.entries) {
      const m = e.match(ENTRY);
      if (m && m[1] === 'CONSTITUTION' && m[2] === 'Y') entries.push(e);
    }
  }
  if (entries.length === 0) return result('pass');
  return result('manual', ["confirm each rule below is in openspec/config.yaml (context: or rules:) and not in this change's spec files", ...entries]);
}

function checkR9() {
  return result('manual', [
    'C1: every Y entry in review-notes.md landed in its artifact — [REQUIREMENT] in proposal.md or specs, [DESIGN] in design.md, [CONSTITUTION] in the project constitution — and in no artifact its tag forbids',
    'C5: the rewritten proposal, specs and design read as if written with everything known from the start: no amendment notes, no comparison with an earlier version, no contradictions',
  ]);
}

const CHECKS = [checkR1, checkR2, checkR3, checkR4, checkR5, checkR6, checkR7, checkR8, checkR9];

function main(argv) {
  const [cmd, arg, ...rest] = argv;
  const ctx = resolveChange(arg);
  if (!['snapshot', 'check', 'verify'].includes(cmd) || !ctx || !fs.existsSync(ctx.changeDir)) {
    console.error(USAGE);
    return 2;
  }
  if (cmd === 'snapshot') {
    // tasks.md is frozen from here on, so every unchecked task must already be ticked or carry a skip reason.
    const r6 = checkR6(ctx);
    if (r6.status === 'fail') {
      console.log('snapshot refused: tick each unchecked task or add " — skip: <reason>" to it, then run snapshot again');
      for (const d of r6.detail) console.log(`  ${d}`);
      return 1;
    }
    const state = readState(ctx);
    state.change = ctx.name;
    state.snapshot = { tasks: fileHash(ctx, ARTIFACTS.tasks), at: new Date().toISOString() };
    writeState(ctx, state);
    console.log(ctx.statePath);
    return 0;
  }
  if (cmd === 'verify') {
    const verdict = readState(ctx).verdict;
    if (!verdict || verdict.result !== 'pass' || !verdict.hashes) { console.log('no-verdict'); return 3; }
    if (verdict.rules !== RULES) { console.log('stale:rules'); return 3; }
    const now = hashes(ctx);
    for (const key of Object.keys(now)) {
      if (verdict.hashes[key] !== now[key]) { console.log(`stale:${key}`); return 3; }
    }
    console.log('fresh');
    return 0;
  }
  const checks = CHECKS.map((fn, i) => ({ id: `R${i + 1}`, ...fn(ctx) }));
  const outcome = checks.some((c) => c.status === 'fail') ? 'fail' : 'pass';
  const state = readState(ctx);
  state.change = ctx.name;
  // A failed check withdraws any earlier verdict: the gate must not pass on a result that no longer holds.
  if (outcome === 'pass') state.verdict = { result: 'pass', rules: RULES, at: new Date().toISOString(), hashes: hashes(ctx) };
  else delete state.verdict;
  writeState(ctx, state);
  if (rest.includes('--json')) {
    console.log(JSON.stringify({ change: ctx.name, result: outcome, checks }, null, 2));
  } else {
    console.log(`reconcile-check ${ctx.name}: ${outcome}`);
    for (const c of checks) {
      console.log(`${c.id} ${c.status}`);
      for (const d of c.detail) console.log(`  ${d}`);
    }
  }
  return outcome === 'pass' ? 0 : 1;
}

process.exitCode = main(process.argv.slice(2));
