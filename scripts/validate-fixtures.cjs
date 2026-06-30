#!/usr/bin/env node
'use strict';

/**
 * validate-fixtures.cjs
 *
 * Zero-dependency repo-root fixture runner.
 * Runs all plugin validators against their test fixtures and reports results.
 *
 * Usage (from repo root):
 *   node scripts/validate-fixtures.cjs
 *
 * Exit codes:
 *   0 — all fixture checks passed
 *   1 — one or more checks failed
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;
let failed = 0;
const failures = [];

// ── helpers ───────────────────────────────────────────────────────────────────

/** Run a validator against a fixture; assert exit code matches expectation. */
function run(validator, fixture, expectValid) {
  const label = `${path.relative(ROOT, validator)} ← ${path.relative(ROOT, fixture)}`;
  if (!fs.existsSync(validator)) {
    console.error(`  ✗  ${label}: validator not found`);
    failed++;
    failures.push(label);
    return;
  }
  let exitCode = 0;
  try {
    execFileSync(process.execPath, [validator, fixture], { stdio: 'pipe' });
    exitCode = 0;
  } catch (e) {
    exitCode = typeof e.status === 'number' ? e.status : 1;
  }
  const ok = expectValid ? exitCode === 0 : exitCode !== 0;
  if (ok) {
    console.log(`  ✓  ${label}`);
    passed++;
  } else {
    const expected = expectValid ? 'exit 0 (VALID)' : 'exit non-zero (INVALID)';
    console.error(`  ✗  ${label}`);
    console.error(`     expected ${expected}, got exit ${exitCode}`);
    failed++;
    failures.push(label);
  }
}

/**
 * prior-debate.schema.json has no dedicated validator CLI.
 * We enforce the key contract directly here: schemaVersion is current,
 * reuseConstraint is present, suppressNew* are false, and an applicability
 * note documents why the prior run may inform this run.
 */
function checkPriorDebate(fixturePath, expectValid) {
  const label = `prior-debate shape check ← ${path.relative(ROOT, fixturePath)}`;
  let raw;
  try {
    raw = fs.readFileSync(fixturePath, 'utf8');
  } catch (e) {
    console.error(`  ✗  ${label}: cannot read file — ${e.message}`);
    failed++;
    failures.push(label);
    return;
  }
  let data;
  try {
    data = JSON.parse(raw);
  } catch (e) {
    if (!expectValid) {
      console.log(`  ✓  ${label} (invalid JSON as expected)`);
      passed++;
    } else {
      console.error(`  ✗  ${label}: invalid JSON — ${e.message}`);
      failed++;
      failures.push(label);
    }
    return;
  }

  const errors = [];
  const required = [
    'schemaVersion', 'topic', 'artifactRef', 'priorDecision',
    'rejectedAlternatives', 'unresolvedRisks', 'coverage',
    'validatorVerdict', 'reuseConstraint',
  ];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }
  if (data.schemaVersion !== '1.0') {
    errors.push('schemaVersion must be "1.0"');
  }
  if (!data.reuseConstraint || typeof data.reuseConstraint !== 'object' || Array.isArray(data.reuseConstraint)) {
    errors.push('reuseConstraint must be an object');
  } else {
    if (data.reuseConstraint.suppressNewFindings !== false) {
      errors.push('reuseConstraint.suppressNewFindings MUST be false');
    }
    if (data.reuseConstraint.suppressNewDecisions !== false) {
      errors.push('reuseConstraint.suppressNewDecisions MUST be false');
    }
    if (!data.reuseConstraint.applicabilityNote || typeof data.reuseConstraint.applicabilityNote !== 'string') {
      errors.push('reuseConstraint.applicabilityNote required');
    }
  }

  const isValid = errors.length === 0;
  const ok = expectValid ? isValid : !isValid;
  if (ok) {
    console.log(`  ✓  ${label}`);
    passed++;
  } else {
    console.error(`  ✗  ${label}`);
    if (expectValid) errors.forEach(e => console.error(`     - ${e}`));
    else console.error('     expected invalid but passed all shape checks');
    failed++;
    failures.push(label);
  }
}

// ── path helpers ──────────────────────────────────────────────────────────────

const P = (...parts) => path.join(ROOT, ...parts);

// ── fixture suite ─────────────────────────────────────────────────────────────

function main() {
  console.log('\n=== validate-fixtures: repo-root fixture runner ===\n');

  // ── Multi-Agent Debate ───────────────────────────────────────────────────────
  console.log('## Multi-Agent Debate — debate-output validator');
  const debateV = P('plugins/multi-agent-debate/validators/validate-debate-output.cjs');
  const debateF = P('plugins/multi-agent-debate/tests/fixtures/debate-output');
  run(debateV, path.join(debateF, 'valid-basic.json'), true);
  run(debateV, path.join(debateF, 'invalid-missing-consensus.json'), false);

  console.log('\n## Multi-Agent Debate — prior-debate schema (shape checks)');
  const priorF = P('plugins/multi-agent-debate/tests/fixtures/prior-debate');
  checkPriorDebate(path.join(priorF, 'valid-prior-debate.json'), true);
  checkPriorDebate(path.join(priorF, 'invalid-suppresses-new-findings.json'), false);
  checkPriorDebate(path.join(priorF, 'invalid-suppresses-new-decisions.json'), false);
  checkPriorDebate(path.join(priorF, 'invalid-missing-applicability-note.json'), false);

  // ── High-Precision Dev ────────────────────────────────────────────────────
  console.log('\n## High-Precision Dev — output validator');
  const hpV = P('plugins/high-precision-dev/validators/validate-high-precision-output.cjs');
  const hpF = P('plugins/high-precision-dev/tests/fixtures/high-precision-output');
  run(hpV, path.join(hpF, 'valid-basic.json'), true);
  run(hpV, path.join(hpF, 'valid-with-prior-run.json'), true);
  run(hpV, path.join(hpF, 'invalid-missing-coverage.json'), false);
  run(hpV, path.join(hpF, 'invalid-partial-empty-coverage.json'), false);
  run(hpV, path.join(hpF, 'invalid-prior-run-suppresses.json'), false);
  run(hpV, path.join(hpF, 'invalid-verified-empty-tested.json'), false);

  // ── OpenSpec + Superpowers ─────────────────────────────────────────────────
  console.log('\n## OpenSpec + Superpowers Workflow — change-folder validator');
  const openV = P('plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs');
  const openF = P('plugins/openspec-superpowers-workflow/tests/fixtures/openspec-workflow');
  run(openV, path.join(openF, 'valid-change'), true);
  run(openV, path.join(openF, 'invalid-missing-shall'), false);

  // ── Code Audit Rigor: finding ──────────────────────────────────────────────
  console.log('\n## Code Audit Rigor — finding validator');
  const carF = P('plugins/code-audit-rigor/tests/fixtures/code-audit-rigor');
  const findV = P('plugins/code-audit-rigor/validators/validate-finding.cjs');
  run(findV, path.join(carF, 'finding-valid.json'), true);
  run(findV, path.join(carF, 'finding-invalid-no-crossrefs.json'), false);

  // ── Code Audit Rigor: review-branch-results ────────────────────────────────
  console.log('\n## Code Audit Rigor — review-branch-results validator');
  const rbV = P('plugins/code-audit-rigor/validators/validate-review-branch-results.cjs');
  run(rbV, path.join(carF, 'review-branch-valid.json'), true);
  run(rbV, path.join(carF, 'review-branch-invalid-skip-no-reason.json'), false);

  // ── Code Audit Rigor: review-pr-comments ──────────────────────────────────
  console.log('\n## Code Audit Rigor — review-pr-comments validator');
  const prV = P('plugins/code-audit-rigor/validators/validate-review-pr-comments.cjs');
  run(prV, path.join(carF, 'review-pr-comments-valid.json'), true);
  run(prV, path.join(carF, 'review-pr-comments-valid-block.json'), true);
  run(prV, path.join(carF, 'review-pr-comments-invalid-block-no-rationale.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-fix-no-evidence.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-missing-endpoint.json'), false);

  // ── Code Audit Rigor: audit-review-fix-result ─────────────────────────────
  console.log('\n## Code Audit Rigor — audit-review-fix-result validator');
  const arfV = P('plugins/code-audit-rigor/validators/validate-audit-review-fix-result.cjs');
  run(arfV, path.join(carF, 'audit-review-fix-valid.json'), true);
  run(arfV, path.join(carF, 'audit-review-fix-valid-follow-up-with-fixes.json'), true);
  run(arfV, path.join(carF, 'audit-review-fix-valid-workflow-return.json'), true);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-follow-up-tests-failed.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-impossible-status.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-tests-fail.json'), false);

  // ── Code Audit Rigor: coverage-reconcile ──────────────────────────────────
  console.log('\n## Code Audit Rigor — coverage-reconcile validator');
  const covV = P('plugins/code-audit-rigor/validators/coverage-reconcile.cjs');
  run(covV, path.join(carF, 'coverage-reconcile-valid.json'), true);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-duplicate.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-missing-status.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-skip-no-reason.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-suggestion-no-file.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-unaccounted.json'), false);

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log(`\n=== Summary: ${passed} passed, ${failed} failed ===`);
  if (failed > 0) {
    console.error('\nFailed checks:');
    failures.forEach(f => console.error(`  - ${f}`));
    process.exit(1);
  }
  console.log('All fixture checks passed.');
  process.exit(0);
}

main();
