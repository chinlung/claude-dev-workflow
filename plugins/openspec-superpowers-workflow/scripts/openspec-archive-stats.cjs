#!/usr/bin/env node
'use strict';
// How many archived OpenSpec changes left tasks unchecked? Scans <project>/openspec/changes/archive/*/tasks.md.
//   node openspec-archive-stats.cjs --root <dir> [--root <dir> …] [--since YYYY-MM-DD] [--names]
// A --root is either a project (it has openspec/changes/archive) or a directory of projects.
// Project names are replaced by the first six hex chars of the sha256 of the directory name (an unsalted
// hash: it hides the name from a reader, not from someone who guesses and checks); --names shows the real names.
// Exit codes: 0 done (also when nothing was found), 2 usage error or a --root that is not a directory.
// Design: docs/openspec-workflow-2-part2-design-2026-11-09.md §4.2. Tests: tests/archive-stats.test.sh

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const USAGE = 'Usage: openspec-archive-stats.cjs --root <dir> [--root <dir> …] [--since YYYY-MM-DD] [--names]';
// The task definition and the skip rule are shared with reconcile-check R6 (one module, same pattern as the OpenSpec CLI).
const { parseTaskLines } = require('../skills/openspec-superpowers-workflow/validators/task-line.cjs');
const DEFINITION =
  'task = a line OpenSpec 1.16 counts as a task (bullet -, *, +, 1. or 1), then a [ ]-style box, at any indentation; ' +
  'done only when the box holds x or X); ' +
  'incomplete = at least one unfinished task; incompletePct = incomplete / archived; ' +
  'incompleteNoReason = at least one unfinished task without "skip:" and a reason (a letter or digit); ' +
  'withSkipReason = at least one unfinished task with such a reason (a change can count in both); ' +
  'noTasks = no tasks.md, or no task line in it';

function fail(message) {
  console.error(message);
  return 2;
}

function parseArgs(argv) {
  const opts = { roots: [], since: null, names: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--root' && argv[i + 1] !== undefined) opts.roots.push(argv[++i]);
    else if (a === '--since' && /^\d{4}-\d{2}-\d{2}$/.test(argv[i + 1] || '')) opts.since = argv[++i];
    else if (a === '--names') opts.names = true;
    else return null;
  }
  return opts.roots.length ? opts : null;
}

const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
const archiveDir = (project) => path.join(project, 'openspec', 'changes', 'archive');

function findProjects(roots) {
  const found = new Set();
  for (const root of roots) {
    const abs = path.resolve(root);
    const candidates = isDir(archiveDir(abs))
      ? [abs]
      : (() => { try { return fs.readdirSync(abs).map((n) => path.join(abs, n)); } catch { return []; } })();
    for (const c of candidates) if (isDir(archiveDir(c))) found.add(c);
  }
  return [...found];
}

function readTasks(changeDir) {
  try { return fs.readFileSync(path.join(changeDir, 'tasks.md'), 'utf8'); } catch { return null; }
}

function main(argv) {
  const opts = parseArgs(argv);
  if (!opts) return fail(USAGE);
  const missing = opts.roots.find((r) => !isDir(path.resolve(r)));
  if (missing) return fail(`--root is not a directory: ${missing}`);

  const totals = { archived: 0, noTasks: 0, withTasks: 0, incomplete: 0, incompletePct: 0, zeroChecked: 0, incompleteNoReason: 0, withSkipReason: 0 };
  const byMonth = {};
  const projects = [];

  for (const project of findProjects(opts.roots)) {
    const base = path.basename(project);
    const entry = { label: opts.names ? base : crypto.createHash('sha256').update(base).digest('hex').slice(0, 6), archived: 0, incomplete: 0 };
    let names = [];
    try { names = fs.readdirSync(archiveDir(project)); } catch { /* unreadable: counted as empty */ }
    for (const name of names) {
      const dir = path.join(archiveDir(project), name);
      if (!isDir(dir)) continue;
      const m = name.match(/^(\d{4}-\d{2}-\d{2})-/);
      if (opts.since && (!m || m[1] < opts.since)) continue;
      const month = m ? m[1].slice(0, 7) : 'unknown';
      byMonth[month] = byMonth[month] || { archived: 0, incomplete: 0 };

      totals.archived++; entry.archived++; byMonth[month].archived++;
      const tasks = parseTaskLines(readTasks(dir));
      if (tasks.length === 0) { totals.noTasks++; continue; }

      totals.withTasks++;
      const open = tasks.filter((t) => !t.done);
      if (open.length === 0) continue;
      totals.incomplete++; entry.incomplete++; byMonth[month].incomplete++;
      if (open.length === tasks.length) totals.zeroChecked++;
      const excused = open.filter((t) => t.skipped).length;
      if (excused < open.length) totals.incompleteNoReason++;
      if (excused > 0) totals.withSkipReason++;
    }
    projects.push(entry);
  }

  totals.incompletePct = totals.archived ? Math.round((totals.incomplete / totals.archived) * 1000) / 10 : 0;
  projects.sort((a, b) => a.label.localeCompare(b.label));
  console.log(JSON.stringify({ definition: DEFINITION, asOf: new Date().toISOString().slice(0, 10), roots: opts.roots.length, since: opts.since, totals, byMonth, projects }, null, 2));
  return 0;
}

process.exitCode = main(process.argv.slice(2));
