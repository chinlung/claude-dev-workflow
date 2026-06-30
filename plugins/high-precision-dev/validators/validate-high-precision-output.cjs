#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const COMPLETION_SIGNAL_ENUM = ['SPEC_COMPLETE', 'CONSENSUS_REACHED', 'PARTIAL', 'FAILED'];
const SOURCE_ENUM = ['critic', 'adversary', 'disproof'];
const SEVERITY_ENUM = ['critical', 'high', 'medium', 'low', 'info'];
const VERIFICATION_STATUS_ENUM = ['VERIFIED', 'PARTIAL', 'FAILED', 'SKIPPED'];

function validateFindings(findings, errors) {
  if (!Array.isArray(findings)) {
    errors.push('findings must be an array');
    return;
  }
  findings.forEach((f, i) => {
    const p = `findings[${i}]`;
    if (!SOURCE_ENUM.includes(f.source)) errors.push(`${p}.source must be one of: ${SOURCE_ENUM.join(', ')}`);
    if (!SEVERITY_ENUM.includes(f.severity)) errors.push(`${p}.severity must be one of: ${SEVERITY_ENUM.join(', ')}`);
    if (!f.description) errors.push(`${p}.description required`);
    if (!f.location) errors.push(`${p}.location required`);
    if (!f.evidence) errors.push(`${p}.evidence required`);
  });
}

function validateCoverage(coverage, errors) {
  if (!coverage || typeof coverage !== 'object') {
    errors.push('coverage is required and must be an object');
    return;
  }
  if (!Array.isArray(coverage.tested)) errors.push('coverage.tested must be an array');
  else coverage.tested.forEach((t, i) => {
    const p = `coverage.tested[${i}]`;
    if (!t.requirement) errors.push(`${p}.requirement required`);
    if (!t.testCase) errors.push(`${p}.testCase required`);
    if (typeof t.passed !== 'boolean') errors.push(`${p}.passed must be boolean`);
  });

  if (!Array.isArray(coverage.untested)) errors.push('coverage.untested must be an array');
  else coverage.untested.forEach((u, i) => {
    const p = `coverage.untested[${i}]`;
    if (!u.requirement) errors.push(`${p}.requirement required`);
    if (!u.reason) errors.push(`${p}.reason required`);
  });

  if (!Array.isArray(coverage.outOfScope)) errors.push('coverage.outOfScope must be an array');
  else coverage.outOfScope.forEach((o, i) => {
    const p = `coverage.outOfScope[${i}]`;
    if (!o.requirement) errors.push(`${p}.requirement required`);
    if (!o.reason) errors.push(`${p}.reason required`);
  });

  if (!VERIFICATION_STATUS_ENUM.includes(coverage.verificationStatus)) {
    errors.push(`coverage.verificationStatus must be one of: ${VERIFICATION_STATUS_ENUM.join(', ')}`);
  }

  if (coverage.verificationStatus === 'VERIFIED') {
    const hasTested = Array.isArray(coverage.tested) && coverage.tested.length > 0;
    if (!hasTested) {
      errors.push("coverage.verificationStatus is 'VERIFIED' but coverage.tested is empty — verified coverage requires at least one tested requirement with evidence");
    }
  }

  // PARTIAL or SKIPPED must have explicit entries in untested or outOfScope
  if ((coverage.verificationStatus === 'PARTIAL' || coverage.verificationStatus === 'SKIPPED')) {
    const hasUntested = Array.isArray(coverage.untested) && coverage.untested.length > 0;
    const hasOutOfScope = Array.isArray(coverage.outOfScope) && coverage.outOfScope.length > 0;
    if (!hasUntested && !hasOutOfScope) {
      errors.push(`coverage.verificationStatus is '${coverage.verificationStatus}' but both coverage.untested and coverage.outOfScope are empty — missing coverage entries are not explicitly documented`);
    }
  }

  // priorRunRef: if present, suppressesFindings must be false
  if (coverage.priorRunRef !== undefined) {
    const pr = coverage.priorRunRef;
    if (!pr || typeof pr !== 'object') {
      errors.push('coverage.priorRunRef must be an object');
    } else {
      if (!pr.artifactPath) errors.push('coverage.priorRunRef.artifactPath required');
      if (pr.suppressesFindings !== false) {
        errors.push('coverage.priorRunRef.suppressesFindings MUST be false — prior run data must not suppress critic/adversary findings');
      }
    }
  }

  // attackClassCoverage: if present, validate items
  if (coverage.attackClassCoverage !== undefined) {
    if (!Array.isArray(coverage.attackClassCoverage)) {
      errors.push('coverage.attackClassCoverage must be an array');
    } else {
      const ATTACK_OUTCOME_ENUM = ['succeeded', 'failed', 'inconclusive', 'not-applicable'];
      coverage.attackClassCoverage.forEach((a, i) => {
        const p = `coverage.attackClassCoverage[${i}]`;
        if (!a.attackClass) errors.push(`${p}.attackClass required`);
        if (typeof a.tried !== 'boolean') errors.push(`${p}.tried must be boolean`);
        if (!ATTACK_OUTCOME_ENUM.includes(a.outcome)) {
          errors.push(`${p}.outcome must be one of: ${ATTACK_OUTCOME_ENUM.join(', ')}`);
        }
      });
    }
  }
}

function validate(data) {
  const errors = [];
  const required = ['implementerId', 'timestamp', 'specRef', 'completionSignal', 'findings', 'coverage'];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }
  if (errors.find(e => e.includes('Missing required field'))) {
    // Still try to validate present fields
  }

  if (data.implementerId !== undefined && (!data.implementerId || typeof data.implementerId !== 'string')) {
    errors.push('implementerId must be a non-empty string');
  }
  if (data.completionSignal !== undefined && !COMPLETION_SIGNAL_ENUM.includes(data.completionSignal)) {
    errors.push(`completionSignal must be one of: ${COMPLETION_SIGNAL_ENUM.join(', ')}`);
  }
  if (data.findings !== undefined) validateFindings(data.findings, errors);
  if (data.coverage !== undefined) validateCoverage(data.coverage, errors);

  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-high-precision-output.cjs <path-to-json>');
    process.exit(2);
  }
  const absPath = path.resolve(filePath);
  let raw;
  try {
    raw = fs.readFileSync(absPath, 'utf8');
  } catch (e) {
    console.error(`Cannot read file: ${absPath}`);
    process.exit(2);
  }
  let data;
  try {
    data = JSON.parse(raw);
  } catch (e) {
    console.error(`Invalid JSON: ${e.message}`);
    process.exit(1);
  }

  const result = validate(data);
  if (result.valid) {
    console.log('VALID: high-precision output passes all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: high-precision output failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
