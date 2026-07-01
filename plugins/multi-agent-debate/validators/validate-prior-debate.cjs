#!/usr/bin/env node
'use strict';

/**
 * validate-prior-debate.cjs
 *
 * Zero-dependency validator for a prior-debate reuse artifact
 * (schema: schema/prior-debate.schema.json). Enforces the schema contract:
 * required fields (incl. nested objects/arrays), non-empty top-level strings,
 * enum vocabularies, and the reuse-constraint MUST-be-false guards that prevent
 * a prior run from suppressing new findings.
 *
 * Exits 0 (VALID), 1 (INVALID or bad JSON), or 2 (usage/unreadable file).
 *
 * Usage: node validate-prior-debate.cjs <path-to-prior-debate.json>
 */

const fs = require('fs');
const path = require('path');

const CONFIDENCE_ENUM = ['HIGH', 'MEDIUM', 'LOW'];
const SEVERITY_ENUM = ['critical', 'high', 'medium', 'low'];
const VERDICT_ENUM = ['verified', 'corrected', 'rejected', 'needs_user_decision', 'NOT_VALIDATED'];

function isNonEmptyString(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

function validate(data) {
  const errors = [];

  const required = [
    'schemaVersion', 'topic', 'artifactRef', 'priorDecision',
    'rejectedAlternatives', 'unresolvedRisks', 'coverage',
    'validatorVerdict', 'reuseConstraint',
  ];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }

  // topic / artifactRef carry minLength:1 in the schema — enforce non-empty, matching
  // the nested string fields (otherwise "" would pass while violating the schema).
  for (const f of ['topic', 'artifactRef']) {
    if (data[f] !== undefined && data[f] !== null && !isNonEmptyString(data[f])) {
      errors.push(`${f} must be a non-empty string`);
    }
  }

  if (data.schemaVersion !== undefined && data.schemaVersion !== '1.0') {
    errors.push('schemaVersion must be "1.0"');
  }

  // priorDecision: selectedProposal, reasoning, confidenceLevel (enum)
  if (data.priorDecision !== undefined) {
    const d = data.priorDecision;
    if (!d || typeof d !== 'object' || Array.isArray(d)) {
      errors.push('priorDecision must be an object');
    } else {
      if (!d.selectedProposal) errors.push('priorDecision.selectedProposal required');
      if (!d.reasoning) errors.push('priorDecision.reasoning required');
      if (!CONFIDENCE_ENUM.includes(d.confidenceLevel)) {
        errors.push(`priorDecision.confidenceLevel must be one of: ${CONFIDENCE_ENUM.join(', ')}`);
      }
    }
  }

  // rejectedAlternatives[]: proposal, rejectionReason
  if (data.rejectedAlternatives !== undefined) {
    if (!Array.isArray(data.rejectedAlternatives)) {
      errors.push('rejectedAlternatives must be an array');
    } else {
      data.rejectedAlternatives.forEach((a, i) => {
        const p = `rejectedAlternatives[${i}]`;
        if (!a || typeof a !== 'object' || Array.isArray(a)) { errors.push(`${p} must be an object`); return; }
        if (!a.proposal) errors.push(`${p}.proposal required`);
        if (!a.rejectionReason) errors.push(`${p}.rejectionReason required`);
      });
    }
  }

  // unresolvedRisks[]: description, severity (enum)
  if (data.unresolvedRisks !== undefined) {
    if (!Array.isArray(data.unresolvedRisks)) {
      errors.push('unresolvedRisks must be an array');
    } else {
      data.unresolvedRisks.forEach((r, i) => {
        const p = `unresolvedRisks[${i}]`;
        if (!r || typeof r !== 'object' || Array.isArray(r)) { errors.push(`${p} must be an object`); return; }
        if (!r.description) errors.push(`${p}.description required`);
        if (!SEVERITY_ENUM.includes(r.severity)) {
          errors.push(`${p}.severity must be one of: ${SEVERITY_ENUM.join(', ')}`);
        }
      });
    }
  }

  // coverage: covered[]{aspect,summary}, notCovered[]{aspect,reason}
  if (data.coverage !== undefined) {
    const c = data.coverage;
    if (!c || typeof c !== 'object' || Array.isArray(c)) {
      errors.push('coverage must be an object');
    } else {
      if (!Array.isArray(c.covered)) {
        errors.push('coverage.covered must be an array');
      } else {
        c.covered.forEach((x, i) => {
          const p = `coverage.covered[${i}]`;
          if (!x || typeof x !== 'object' || Array.isArray(x)) { errors.push(`${p} must be an object`); return; }
          if (!x.aspect) errors.push(`${p}.aspect required`);
          if (!x.summary) errors.push(`${p}.summary required`);
        });
      }
      if (!Array.isArray(c.notCovered)) {
        errors.push('coverage.notCovered must be an array');
      } else {
        c.notCovered.forEach((x, i) => {
          const p = `coverage.notCovered[${i}]`;
          if (!x || typeof x !== 'object' || Array.isArray(x)) { errors.push(`${p} must be an object`); return; }
          if (!x.aspect) errors.push(`${p}.aspect required`);
          if (!x.reason) errors.push(`${p}.reason required`);
        });
      }
    }
  }

  // validatorVerdict enum
  if (data.validatorVerdict !== undefined && !VERDICT_ENUM.includes(data.validatorVerdict)) {
    errors.push(`validatorVerdict must be one of: ${VERDICT_ENUM.join(', ')}`);
  }

  // reuseConstraint: suppressNew* MUST be false, applicabilityNote required
  if (data.reuseConstraint !== undefined) {
    const rc = data.reuseConstraint;
    if (!rc || typeof rc !== 'object' || Array.isArray(rc)) {
      errors.push('reuseConstraint must be an object');
    } else {
      if (rc.suppressNewFindings !== false) {
        errors.push('reuseConstraint.suppressNewFindings MUST be false');
      }
      if (rc.suppressNewDecisions !== false) {
        errors.push('reuseConstraint.suppressNewDecisions MUST be false');
      }
      if (!isNonEmptyString(rc.applicabilityNote)) {
        errors.push('reuseConstraint.applicabilityNote required (non-empty string)');
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-prior-debate.cjs <path-to-prior-debate.json>');
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
    console.log('VALID: prior-debate artifact passes all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: prior-debate artifact failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
