#!/usr/bin/env node
'use strict';

/**
 * PostToolUse hook (Edit|Write|MultiEdit).
 *
 * When a plugin-code file that affects the test suite is edited — a validator
 * (a .cjs under a validators/ dir), a schema (a .json under a schema/ dir), a
 * fixture (anything under a tests/ dir), or the runner itself
 * (scripts/validate-fixtures.cjs) — run `node scripts/validate-fixtures.cjs`.
 * On failure, print the output and exit 2 so Claude Code feeds it back and must
 * fix before continuing.
 *
 * Purpose: the plugin's own test suite (fixtures + mutation harness + schema↔validator
 * consistency + self-test canaries) otherwise only runs when someone remembers to type
 * the command. This hook makes the harness enforce "plugin code changed → suite runs".
 *
 * Edits to any other file exit 0 silently (no-op).
 */

const cp = require('child_process');
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

  // Vendored security-audit keeps its validator/schema under skills/security-audit/
  // (not the conventional validators/ + schema/ dirs), so match those paths too.
  const relevant = /(\/validators\/.*\.cjs|\/schema\/.*\.json|\/tests\/|scripts\/validate-fixtures\.cjs|security-audit\/(validate-findings\.cjs|report-schema\.json))/.test(filePath);
  if (!relevant) process.exit(0);

  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const runner = path.join(root, 'scripts', 'validate-fixtures.cjs');
  const r = cp.spawnSync(process.execPath, [runner], { cwd: root, encoding: 'utf8' });

  if (r.status !== 0) {
    process.stderr.write(
      'Plugin test suite FAILED after a plugin-code edit — fix before continuing:\n' +
      (r.stdout || '') + (r.stderr || '')
    );
    process.exit(2); // PostToolUse exit 2 → output fed back to Claude
  }
  process.exit(0);
});
