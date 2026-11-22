#!/usr/bin/env node
'use strict';

/**
 * PostToolUse hook (Edit|Write|MultiEdit).
 *
 * When a plugin-code file that affects the test suite is edited — a validator
 * (a .cjs under a validators/ dir), a schema (a .json under a schema/ dir), a
 * fixture (anything under a tests/ dir), a hook script (anything under a hooks/
 * dir), the runner itself (scripts/validate-fixtures.cjs), code or data sitting directly
 * in a skill dir (plugins/<p>/skills/<s>/*.{cjs,js,mjs,json}, root-relative — e.g.
 * vendored security-audit's validators, their upstream tests, report-schema.json), or a file the runner's
 * repo-structure gates read (plugins/<p>/commands/*.md, plugins/<p>/skills/<s>/SKILL.md,
 * plugins/<p>/.claude-plugin/plugin.json, plugins/<p>/CHANGELOG.md, the root marketplace.json,
 * a root CHANGELOG, and .claude/settings.json — the denyWrite gate reads it, and editing
 * denyWrite or this hook's own command is exactly when that gate most needs to run) — run
 * `node scripts/validate-fixtures.cjs` PLUS every bash suite named *.test.sh
 * under each plugin's tests/ dir (the node runner never executes those, and
 * hook-script logic is exactly what they guard). On any failure, print the
 * output and exit 2 so Claude Code feeds it back and must fix before continuing.
 *
 * How it runs: the runner and all suites go side by side (CONCURRENCY at a time), the suites with
 * NO_MUTANTS=1 (they skip re-running against mutated copies of their own code; CI runs them whole). That
 * is to fit the 120 s `timeout` in .claude/settings.json: a hook the harness kills at its timeout reports
 * nothing, and run one after another with mutants on, the suites took 658 s, so a failure in a suite near
 * the end of the list never reached Claude. With this, 21 suites and the runner took 68 s on an 18-core
 * machine; the slowest is tokenizer-differential.test.sh, which runs its own jobs in parallel. On a
 * machine slow enough to pass 120 s the harness still drops the hook without a word; CI runs everything.
 *
 * Purpose: the plugin's own test suite (fixtures + mutation harness + schema↔validator
 * consistency + self-test canaries) otherwise only runs when someone remembers to type
 * the command. This hook makes the harness enforce "plugin code changed → suite runs".
 *
 * Edits to any other file exit 0 silently (no-op).
 */

const cp = require('child_process');
const fs = require('fs');
const path = require('path');

const CONCURRENCY = 8;
// What one job may put into the report, kept while reading, not after: everything a failing suite
// prints goes into Claude's context, and holding a runaway suite's whole output would grow without
// bound (the spawnSync this replaced stopped at 1 MB). The head and the tail are kept: the first
// failure and the summary line are usually there.
const KEEP = 12000;
// A job whose output passes this is stopped and counted as failed, as spawnSync's maxBuffer did (1 MiB,
// ENOBUFS). Otherwise a job stuck printing would keep the hook waiting until the harness killed it at its
// timeout, and every other failure would go unreported with it.
const MAX_OUTPUT = 1024 * 1024;
function outputSink() {
  let head = '';
  let tail = '';
  let dropped = 0;
  return {
    get total() { return head.length + tail.length + dropped; },
    push(d) {
      if (head.length < KEEP) { const take = d.slice(0, KEEP - head.length); head += take; d = d.slice(take.length); }
      if (!d) return;
      tail += d;
      if (tail.length > KEEP) { dropped += tail.length - KEEP; tail = tail.slice(-KEEP); }
    },
    text: () => (dropped ? `${head}\n… [${dropped} characters truncated] …\n${tail}` : head + tail),
  };
}

let input = '';
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => {
  let filePath = '';
  try {
    filePath = (JSON.parse(input).tool_input || {}).file_path || '';
  } catch (e) {
    process.exit(0); // no parseable payload → nothing to check
  }

  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  // The runner's repo-structure gates (command/skill name collision, version bookkeeping,
  // plugin changelog bookkeeping, plugin dir completeness, agent models and judgment dispatches)
  // read exactly these — without them here a shadowing command or a version drift only
  // surfaces in CI. Matched ROOT-RELATIVE and fully anchored, not by substring: the gates
  // read fixed paths, so anything else is a pure mis-trigger costing a full suite run (see the header) —
  // ~/.claude/commands/*.md, a project's own .claude/commands/, and the marketplace cache
  // clone (~/.claude/plugins/marketplaces/<m>/plugins/<p>/commands/x.md, which a
  // "/plugins/<p>/commands/" substring would still match). A plugin's own CHANGELOG.md IS
  // gated (its top heading must equal that plugin's plugin.json version); a marketplace.json
  // inside a plugin is not. Trade-off: if CLAUDE_PROJECT_DIR and
  // file_path differ in realpath form (/tmp vs /private/tmp) this goes quiet — a missed
  // local trigger, not a false one, and CI still runs the gates.
  const rel = path.relative(root, filePath).split(path.sep).join('/');
  const structural = /^(plugins\/[^/]+\/(commands\/[^/]+\.md|agents\/(?:[^/]+\/)*[^/]+\.md|skills\/[^/]+\/SKILL\.md|\.claude-plugin\/plugin\.json|CHANGELOG\.md)|\.claude-plugin\/marketplace\.json|CHANGELOG(\.zh-TW)?\.md|\.claude\/settings\.json)$/.test(rel);
  // Code and data that sit directly in a skill dir instead of the conventional validators/ +
  // schema/ dirs — e.g. vendored security-audit's validators, their upstream test suites, and
  // report-schema.json, which the runner and tests/*.test.sh run or load. Root-relative like
  // `structural`, so a cache clone of the same skill does not trigger.
  const skillCode = /^plugins\/[^/]+\/skills\/[^/]+\/[^/]+\.(c?js|mjs|json)$/.test(rel);
  const relevant = structural || skillCode || /(\/validators\/.*\.cjs|\/schema\/.*\.json|\/tests\/|\/hooks\/|scripts\/validate-fixtures\.cjs)/.test(filePath);
  if (!relevant) process.exit(0);

  const runner = path.join(root, 'scripts', 'validate-fixtures.cjs');
  // The node runner and every suite run side by side (at most CONCURRENCY at once), and each suite gets
  // NO_MUTANTS=1: they skip re-running themselves against mutated copies of the code they test, which
  // is where almost all of their time goes (measured one after another with mutants on: 658 s; with
  // mutants off the longest single suite is about 60 s). CI runs every suite whole, mutants included.
  // The runner keeps the caller's environment. Why this matters: settings.json gives the hook 120 s, and
  // a hook the harness kills at its timeout reports nothing, so a failure in a suite not reached yet
  // never came back to Claude.
  const jobs = [{ label: 'scripts/validate-fixtures.cjs', cmd: process.execPath, args: [runner], env: process.env }];
  try {
    for (const name of fs.readdirSync(path.join(root, 'plugins'))) {
      const testsDir = path.join(root, 'plugins', name, 'tests');
      let entries = [];
      try { entries = fs.readdirSync(testsDir); } catch { continue; }
      for (const f of entries.filter((e) => e.endsWith('.test.sh')).sort()) {
        const suite = path.join(testsDir, f);
        jobs.push({ label: path.relative(root, suite), cmd: 'bash', args: [suite], env: { ...process.env, NO_MUTANTS: '1' } });
      }
    }
  } catch { /* no plugins dir → nothing extra to run */ }

  // Not detached: the jobs stay in the hook's process group, as they were under spawnSync, so whatever
  // stops the hook stops them too. (A version with its own deadline that killed the jobs was tried and
  // dropped: each fix to its process handling turned up another case, five rounds in a row.)
  const runJob = (i) => new Promise((resolve) => {
    const out = outputSink();
    const child = cp.spawn(jobs[i].cmd, jobs[i].args, { cwd: root, env: jobs[i].env, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    let stopped = false;
    const take = (d) => {
      if (stopped) return;
      out.push(d);
      if (out.total <= MAX_OUTPUT) return;
      stopped = true;
      child.kill('SIGKILL');
      // like spawnSync: stop the job and move on; something it started may still hold the pipes
      child.stdout.destroy();
      child.stderr.destroy();
      resolve({ status: 1, why: `stopped: its output passed ${MAX_OUTPUT} characters`, output: out.text() });
    };
    child.stdout.on('data', take);
    child.stderr.on('data', take);
    child.on('error', (e) => { out.push(String(e)); resolve({ status: 1, output: out.text() }); });
    child.on('close', (status) => resolve({ status, output: out.text() }));
  });

  const results = new Array(jobs.length);
  let next = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const i = next++;
      results[i] = await runJob(i);
    }
  };

  Promise.all(Array.from({ length: Math.min(CONCURRENCY, jobs.length) }, worker)).then(() => {
    // Reported in job order, not completion order, so the same failure reads the same every time.
    const failures = [];
    jobs.forEach((job, i) => {
      const res = results[i];
      if (res.status !== 0) failures.push(`--- ${job.label} (${res.why || `exit ${res.status}`}) ---\n${res.output}`);
    });
    if (failures.length > 0) {
      // exit 2 → Claude Code feeds stderr back and Claude must deal with it before going on
      process.stderr.write('Plugin test suite FAILED after a plugin-code edit — fix before continuing:\n' + failures.join('\n'));
      process.exitCode = 2;
      return;
    }
    process.exitCode = 0;
  });
});
