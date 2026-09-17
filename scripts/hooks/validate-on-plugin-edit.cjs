#!/usr/bin/env node
'use strict';

/**
 * PostToolUse hook (Edit|Write|MultiEdit).
 *
 * When a plugin-code file that affects the test suite is edited — a validator
 * (a .cjs under a validators/ dir), a schema (a .json under a schema/ dir), a
 * fixture (anything under a tests/ dir), a hook script (anything under a hooks/
 * dir), the runner itself (scripts/validate-fixtures.cjs), or a file the runner's
 * repo-structure gates read (plugins/<p>/commands/*.md, plugins/<p>/skills/<s>/SKILL.md,
 * plugins/<p>/.claude-plugin/plugin.json, the root marketplace.json, a root CHANGELOG, and
 * .claude/settings.json — the denyWrite gate reads it, and editing denyWrite or this hook's
 * own command is exactly when that gate most needs to run) — run
 * `node scripts/validate-fixtures.cjs` PLUS every bash suite named *.test.sh
 * under each plugin's tests/ dir (the node runner never executes those, and
 * hook-script logic is exactly what they guard). On any failure, print the
 * output and exit 2 so Claude Code feeds it back and must fix before continuing.
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
  // The runner's repo-structure gates (command/skill name collision, version bookkeeping)
  // read exactly these — without them here a shadowing command or a version drift only
  // surfaces in CI. Matched ROOT-RELATIVE and fully anchored, not by substring: the gates
  // read fixed paths, so anything else is a pure mis-trigger costing a full ~5s suite run —
  // ~/.claude/commands/*.md, a project's own .claude/commands/, and the marketplace cache
  // clone (~/.claude/plugins/marketplaces/<m>/plugins/<p>/commands/x.md, which a
  // "/plugins/<p>/commands/" substring would still match). Plugin-level CHANGELOG.md and a
  // marketplace.json inside a plugin are not gated. Trade-off: if CLAUDE_PROJECT_DIR and
  // file_path differ in realpath form (/tmp vs /private/tmp) this goes quiet — a missed
  // local trigger, not a false one, and CI still runs the gates.
  const rel = path.relative(root, filePath).split(path.sep).join('/');
  const structural = /^(plugins\/[^/]+\/(commands\/[^/]+\.md|skills\/[^/]+\/SKILL\.md|\.claude-plugin\/plugin\.json)|\.claude-plugin\/marketplace\.json|CHANGELOG(\.zh-TW)?\.md|\.claude\/settings\.json)$/.test(rel);
  // Vendored security-audit keeps its validator/schema under skills/security-audit/
  // (not the conventional validators/ + schema/ dirs), so match those paths too.
  const relevant = structural || /(\/validators\/.*\.cjs|\/schema\/.*\.json|\/tests\/|\/hooks\/|scripts\/validate-fixtures\.cjs|security-audit\/(validate-findings\.cjs|report-schema\.json))/.test(filePath);
  if (!relevant) process.exit(0);

  const failures = [];

  const runner = path.join(root, 'scripts', 'validate-fixtures.cjs');
  const r = cp.spawnSync(process.execPath, [runner], { cwd: root, encoding: 'utf8' });
  if (r.status !== 0) failures.push(r);

  const suites = [];
  try {
    for (const name of fs.readdirSync(path.join(root, 'plugins'))) {
      const testsDir = path.join(root, 'plugins', name, 'tests');
      let entries = [];
      try { entries = fs.readdirSync(testsDir); } catch { continue; }
      for (const f of entries.filter((e) => e.endsWith('.test.sh')).sort()) {
        suites.push(path.join(testsDir, f));
      }
    }
  } catch { /* no plugins dir → nothing extra to run */ }
  for (const s of suites) {
    const b = cp.spawnSync('bash', [s], { cwd: root, encoding: 'utf8' });
    if (b.status !== 0) failures.push(b);
  }

  if (failures.length > 0) {
    process.stderr.write(
      'Plugin test suite FAILED after a plugin-code edit — fix before continuing:\n' +
      failures.map((f) => (f.stdout || '') + (f.stderr || '')).join('\n')
    );
    process.exit(2); // PostToolUse exit 2 → output fed back to Claude
  }
  process.exit(0);
});
