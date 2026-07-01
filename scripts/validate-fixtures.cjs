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
const os = require('os');
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
  // Fail fast on a missing fixture regardless of expectValid. Without this, an
  // expected-invalid case would pass spuriously: the validator exits non-zero
  // simply because it cannot read the fixture, masking the missing test case.
  if (!fs.existsSync(fixture)) {
    console.error(`  ✗  ${label}: fixture not found`);
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

let tmpCounter = 0;
/**
 * Generator-based coverage for the required-field / type / enum long tail.
 * Loads a KNOWN-VALID base fixture, applies exactly one mutation, and asserts the
 * validator rejects it. Isolation is guaranteed by construction: a valid base plus
 * a single-field change means a non-zero exit can only come from that field's rule.
 * Keeps the repo free of dozens of near-duplicate static fixtures.
 */
function runMutations(validator, baseFixture, group, mutations) {
  const rel = path.relative(ROOT, baseFixture);
  let base;
  try {
    base = JSON.parse(fs.readFileSync(baseFixture, 'utf8'));
  } catch (e) {
    console.error(`  ✗  ${group}: cannot load valid base ${rel} — ${e.message}`);
    failed++;
    failures.push(group);
    return;
  }
  for (const m of mutations) {
    const obj = JSON.parse(JSON.stringify(base));
    m.mutate(obj);
    const tmp = path.join(os.tmpdir(), `validate-fixtures-mut-${process.pid}-${tmpCounter++}.json`);
    let exitCode = 0;
    try {
      fs.writeFileSync(tmp, JSON.stringify(obj));
      execFileSync(process.execPath, [validator, tmp], { stdio: 'pipe' });
      exitCode = 0;
    } catch (e) {
      exitCode = typeof e.status === 'number' ? e.status : 1;
    } finally {
      try { fs.unlinkSync(tmp); } catch (e) { /* ignore cleanup errors */ }
    }
    const label = `${group} ← mutate: ${m.label}`;
    if (exitCode !== 0) {
      console.log(`  ✓  ${label}`);
      passed++;
    } else {
      console.error(`  ✗  ${label}: expected rejection (exit non-zero), got exit 0`);
      failed++;
      failures.push(label);
    }
  }
}

/** Recursively collect string enum values and regex patterns declared in a schema. */
function collectSchemaEnums(node, acc) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node.enum)) {
    for (const v of node.enum) if (typeof v === 'string') acc.enumValues.add(v);
  }
  if (typeof node.pattern === 'string') acc.patterns.add(node.pattern);
  for (const k of Object.keys(node)) {
    if (node[k] && typeof node[k] === 'object') collectSchemaEnums(node[k], acc);
  }
}

/**
 * Schema ↔ validator consistency gate. Nothing executes the JSON schemas at
 * runtime (no ajv), so schema/validator drift is otherwise invisible. This
 * makes the schema a live layer: bidirectional value-level diff —
 *   1. every string enum value / pattern declared in the schema(s) must appear
 *      in the validator source (schema promises → validator enforces), and
 *   2. every value in the validator's `*_ENUM` arrays must appear in the
 *      schema text (validator enforces → schema documents).
 * A mismatch (e.g. renaming an enum on one side only) fails the suite.
 */
function checkSchemaConsistency(schemaPaths, validatorPath, group) {
  let src;
  try {
    src = fs.readFileSync(validatorPath, 'utf8');
  } catch (e) {
    console.error(`  ✗  ${group}: cannot read validator — ${e.message}`);
    failed++;
    failures.push(group);
    return;
  }
  const acc = { enumValues: new Set(), patterns: new Set() };
  const schemaTexts = [];
  for (const sp of schemaPaths) {
    let schema;
    try {
      const rawSchema = fs.readFileSync(sp, 'utf8');
      schema = JSON.parse(rawSchema);
      schemaTexts.push(rawSchema);
    } catch (e) {
      console.error(`  ✗  ${group}: cannot read schema ${path.relative(ROOT, sp)} — ${e.message}`);
      failed++;
      failures.push(group);
      return;
    }
    collectSchemaEnums(schema, acc);
  }
  const schemaText = schemaTexts.join('\n');

  const drift = [];
  for (const v of acc.enumValues) {
    if (!src.includes(v)) drift.push(`schema enum value "${v}" is not enforced in the validator`);
  }
  for (const p of acc.patterns) {
    if (!src.includes(p)) drift.push(`schema pattern "${p}" is not present in the validator`);
  }
  const enumArrayRe = /_ENUM\s*=\s*\[([^\]]*)\]/g;
  let m;
  while ((m = enumArrayRe.exec(src)) !== null) {
    const quoted = m[1].match(/'([^']*)'|"([^"]*)"/g) || [];
    for (const raw of quoted) {
      const val = raw.slice(1, -1);
      if (!schemaText.includes(val)) drift.push(`validator enum value "${val}" is not declared in the schema`);
    }
  }

  const label = `${group} (schema ↔ validator)`;
  if (drift.length === 0) {
    console.log(`  ✓  ${label}`);
    passed++;
  } else {
    console.error(`  ✗  ${label}`);
    drift.forEach(d => console.error(`     - ${d}`));
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
  run(debateV, path.join(debateF, 'invalid-bad-verdict.json'), false);
  run(debateV, path.join(debateF, 'invalid-score-out-of-range.json'), false);
  run(debateV, path.join(debateF, 'invalid-bad-severity.json'), false);
  run(debateV, path.join(debateF, 'invalid-noninteger-round.json'), false);
  run(debateV, path.join(debateF, 'invalid-consensus-not-boolean.json'), false);
  run(debateV, path.join(debateF, 'invalid-empty-critique-rounds.json'), false);

  console.log('\n## Multi-Agent Debate — prior-debate validator');
  const priorV = P('plugins/multi-agent-debate/validators/validate-prior-debate.cjs');
  const priorF = P('plugins/multi-agent-debate/tests/fixtures/prior-debate');
  run(priorV, path.join(priorF, 'valid-prior-debate.json'), true);
  run(priorV, path.join(priorF, 'invalid-suppresses-new-findings.json'), false);
  run(priorV, path.join(priorF, 'invalid-suppresses-new-decisions.json'), false);
  run(priorV, path.join(priorF, 'invalid-missing-applicability-note.json'), false);
  run(priorV, path.join(priorF, 'invalid-missing-required.json'), false);
  run(priorV, path.join(priorF, 'invalid-bad-schemaversion.json'), false);
  run(priorV, path.join(priorF, 'invalid-reuseconstraint-not-object.json'), false);

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
  run(hpV, path.join(hpF, 'invalid-verified-passed-false.json'), false);
  run(hpV, path.join(hpF, 'invalid-priorref-no-artifact.json'), false);
  run(hpV, path.join(hpF, 'invalid-attackclass-outcome.json'), false);

  // ── OpenSpec + Superpowers ─────────────────────────────────────────────────
  console.log('\n## OpenSpec + Superpowers Workflow — change-folder validator');
  const openV = P('plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs');
  const openF = P('plugins/openspec-superpowers-workflow/tests/fixtures/openspec-workflow');
  run(openV, path.join(openF, 'valid-change'), true);
  run(openV, path.join(openF, 'invalid-missing-shall'), false);
  run(openV, path.join(openF, 'invalid-missing-file'), false);
  run(openV, path.join(openF, 'invalid-no-spec'), false);

  // ── Code Audit Rigor: finding ──────────────────────────────────────────────
  console.log('\n## Code Audit Rigor — finding validator');
  const carF = P('plugins/code-audit-rigor/tests/fixtures/code-audit-rigor');
  const findV = P('plugins/code-audit-rigor/validators/validate-finding.cjs');
  run(findV, path.join(carF, 'finding-valid.json'), true);
  run(findV, path.join(carF, 'finding-invalid-no-crossrefs.json'), false);
  run(findV, path.join(carF, 'finding-invalid-crossref-incomplete.json'), false);
  run(findV, path.join(carF, 'finding-invalid-bad-security.json'), false);
  run(findV, path.join(carF, 'finding-invalid-empty-crossrefs.json'), false);
  run(findV, path.join(carF, 'finding-invalid-bad-decision.json'), false);
  run(findV, path.join(carF, 'finding-invalid-bad-confidence.json'), false);

  // ── Code Audit Rigor: review-branch-results ────────────────────────────────
  console.log('\n## Code Audit Rigor — review-branch-results validator');
  const rbV = P('plugins/code-audit-rigor/validators/validate-review-branch-results.cjs');
  run(rbV, path.join(carF, 'review-branch-valid.json'), true);
  run(rbV, path.join(carF, 'review-branch-invalid-skip-no-reason.json'), false);
  run(rbV, path.join(carF, 'review-branch-invalid-noninteger-line.json'), false);

  // ── Code Audit Rigor: review-pr-comments ──────────────────────────────────
  console.log('\n## Code Audit Rigor — review-pr-comments validator');
  const prV = P('plugins/code-audit-rigor/validators/validate-review-pr-comments.cjs');
  run(prV, path.join(carF, 'review-pr-comments-valid.json'), true);
  run(prV, path.join(carF, 'review-pr-comments-valid-block.json'), true);
  run(prV, path.join(carF, 'review-pr-comments-invalid-block-no-rationale.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-fix-no-evidence.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-missing-endpoint.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-negative-prnumber.json'), false);
  run(prV, path.join(carF, 'review-pr-comments-invalid-skip-no-rationale.json'), false);

  // ── Code Audit Rigor: audit-review-fix-result ─────────────────────────────
  console.log('\n## Code Audit Rigor — audit-review-fix-result validator');
  const arfV = P('plugins/code-audit-rigor/validators/validate-audit-review-fix-result.cjs');
  run(arfV, path.join(carF, 'audit-review-fix-valid.json'), true);
  run(arfV, path.join(carF, 'audit-review-fix-valid-follow-up-with-fixes.json'), true);
  run(arfV, path.join(carF, 'audit-review-fix-valid-workflow-return.json'), true);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-follow-up-tests-failed.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-impossible-status.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-tests-fail.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-user-review-tests-failed.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-ready-no-fixes.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-clean-active.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-tests-failed-no-fix.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-follow-up-no-deferred.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-empty-diff-nonzero.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-workflow-return-impossible.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-follow-up-userreview.json'), false);
  run(arfV, path.join(carF, 'audit-review-fix-invalid-tests-failed-passing.json'), false);

  // ── Code Audit Rigor: coverage-reconcile ──────────────────────────────────
  console.log('\n## Code Audit Rigor — coverage-reconcile validator');
  const covV = P('plugins/code-audit-rigor/validators/coverage-reconcile.cjs');
  run(covV, path.join(carF, 'coverage-reconcile-valid.json'), true);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-duplicate.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-missing-status.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-skip-no-reason.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-suggestion-no-file.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-scoped-no-file.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-empty-scoped.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-not-array.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-unknown-status.json'), false);
  run(covV, path.join(carF, 'coverage-reconcile-invalid-unaccounted.json'), false);

  // ── Long-tail required-field / type / enum coverage (generated mutations) ────
  console.log('\n## Required-field / type / enum coverage (single-field mutations off valid bases)');

  runMutations(debateV, path.join(debateF, 'valid-basic.json'), 'debate-output', [
    { label: 'delete metadata', mutate: o => { delete o.metadata; } },
    { label: 'metadata.sessionId empty', mutate: o => { o.metadata.sessionId = ''; } },
    { label: 'requirement empty', mutate: o => { o.requirement = ''; } },
    { label: 'proposals empty', mutate: o => { o.proposals = []; } },
    { label: 'proposal missing id', mutate: o => { delete o.proposals[0].id; } },
    { label: 'proposal missing source', mutate: o => { delete o.proposals[0].source; } },
    { label: 'proposal missing title', mutate: o => { delete o.proposals[0].title; } },
    { label: 'proposal missing summary', mutate: o => { delete o.proposals[0].summary; } },
    { label: 'proposal missing rationale', mutate: o => { delete o.proposals[0].rationale; } },
    { label: 'proposal missing scores', mutate: o => { delete o.proposals[0].scores; } },
    { label: 'criticism missing proposalId', mutate: o => { delete o.critiqueRounds[0].criticisms[0].proposalId; } },
    { label: 'criticism missing issue', mutate: o => { delete o.critiqueRounds[0].criticisms[0].issue; } },
    { label: 'consensus.summary empty', mutate: o => { o.consensus.summary = ''; } },
    { label: 'consensus.agreedProposals not array', mutate: o => { o.consensus.agreedProposals = 'x'; } },
    { label: 'finalDecision missing selectedProposal', mutate: o => { delete o.finalDecision.selectedProposal; } },
    { label: 'finalDecision missing reasoning', mutate: o => { delete o.finalDecision.reasoning; } },
    { label: 'delete validation', mutate: o => { delete o.validation; } },
  ]);

  runMutations(findV, path.join(carF, 'finding-valid.json'), 'finding', [
    { label: 'severity bad enum', mutate: o => { o.severity = 'SEV'; } },
    { label: 'confidence out of range', mutate: o => { o.confidence = 150; } },
    { label: 'ev not number', mutate: o => { o.ev = 'high'; } },
    { label: 'decision bad enum', mutate: o => { o.decision = 'MAYBE'; } },
    { label: 'crossRef missing file', mutate: o => { delete o.crossReferences[0].file; } },
    { label: 'crossRef missing lines', mutate: o => { delete o.crossReferences[0].lines; } },
  ]);

  runMutations(rbV, path.join(carF, 'review-branch-valid.json'), 'review-branch-results', [
    { label: 'branch empty', mutate: o => { o.branch = ''; } },
    { label: 'scopedFiles empty', mutate: o => { o.scopedFiles = []; } },
    { label: 'scopedFile missing file', mutate: o => { delete o.scopedFiles[0].file; } },
    { label: 'scopedFile bad status', mutate: o => { o.scopedFiles[0].status = 'wip'; } },
    { label: 'suggestion missing quotedCode', mutate: o => { delete o.suggestions[0].quotedCode; } },
    { label: 'suggestion missing description', mutate: o => { delete o.suggestions[0].description; } },
    { label: 'suggestion bad severity', mutate: o => { o.suggestions[0].severity = 'SEV'; } },
    { label: 'verification missing id', mutate: o => { delete o.verifications[0].id; } },
    { label: 'verification bad verdict', mutate: o => { o.verifications[0].verdict = 'MAYBE'; } },
  ]);

  runMutations(prV, path.join(carF, 'review-pr-comments-valid.json'), 'review-pr-comments', [
    { label: 'comments not array', mutate: o => { o.comments = 'x'; } },
    { label: 'comment missing id', mutate: o => { delete o.comments[0].id; } },
    { label: 'comment missing author', mutate: o => { delete o.comments[0].author; } },
    { label: 'comment missing body', mutate: o => { delete o.comments[0].body; } },
    { label: 'comment bad classification', mutate: o => { o.comments[0].classification = 'weird'; } },
    { label: 'comment bad decision', mutate: o => { o.comments[0].decision = 'maybe'; } },
  ]);

  runMutations(hpV, path.join(hpF, 'valid-basic.json'), 'high-precision-output', [
    { label: 'implementerId empty', mutate: o => { o.implementerId = ''; } },
    { label: 'completionSignal bad enum', mutate: o => { o.completionSignal = 'DONE'; } },
    { label: 'finding missing source', mutate: o => { delete o.findings[0].source; } },
    { label: 'finding bad severity', mutate: o => { o.findings[0].severity = 'sev'; } },
    { label: 'finding missing description', mutate: o => { delete o.findings[0].description; } },
    { label: 'finding missing location', mutate: o => { delete o.findings[0].location; } },
    { label: 'finding missing evidence', mutate: o => { delete o.findings[0].evidence; } },
    { label: 'tested missing requirement', mutate: o => { delete o.coverage.tested[0].requirement; } },
    { label: 'tested missing testCase', mutate: o => { delete o.coverage.tested[0].testCase; } },
    { label: 'tested passed not boolean', mutate: o => { o.coverage.tested[0].passed = 'yes'; } },
    { label: 'verificationStatus bad enum', mutate: o => { o.coverage.verificationStatus = 'DONE'; } },
  ]);

  runMutations(priorV, path.join(priorF, 'valid-prior-debate.json'), 'prior-debate', [
    { label: 'validatorVerdict bad enum', mutate: o => { o.validatorVerdict = 'APPROVED'; } },
    { label: 'priorDecision.confidenceLevel bad enum', mutate: o => { o.priorDecision.confidenceLevel = 'VERY_HIGH'; } },
    { label: 'priorDecision missing selectedProposal', mutate: o => { delete o.priorDecision.selectedProposal; } },
    { label: 'unresolvedRisks bad severity', mutate: o => { o.unresolvedRisks[0].severity = 'blocker'; } },
    { label: 'rejectedAlternatives missing proposal', mutate: o => { delete o.rejectedAlternatives[0].proposal; } },
    { label: 'coverage.covered missing aspect', mutate: o => { delete o.coverage.covered[0].aspect; } },
    { label: 'coverage.notCovered missing reason', mutate: o => { delete o.coverage.notCovered[0].reason; } },
  ]);

  // ── Schema ↔ validator consistency (makes the schema a live, checked layer) ──
  console.log('\n## Schema ↔ validator consistency (enum/pattern drift detection)');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/finding.schema.json')], findV, 'finding');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/review-branch-results.schema.json')], rbV, 'review-branch-results');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/review-pr-comments.schema.json')], prV, 'review-pr-comments');
  checkSchemaConsistency([P('plugins/code-audit-rigor/schema/audit-review-fix-result.schema.json')], arfV, 'audit-review-fix-result');
  checkSchemaConsistency([
    P('plugins/high-precision-dev/schema/findings.schema.json'),
    P('plugins/high-precision-dev/schema/coverage.schema.json'),
  ], hpV, 'high-precision-output');
  checkSchemaConsistency([P('plugins/multi-agent-debate/schema/debate-output.schema.json')], debateV, 'debate-output');
  checkSchemaConsistency([P('plugins/multi-agent-debate/schema/prior-debate.schema.json')], priorV, 'prior-debate');

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
