#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const SEVERITY_ENUM = ['critical', 'high', 'medium', 'low'];
const VERDICT_ENUM = ['verified', 'corrected', 'rejected', 'needs_user_decision'];

function err(msg) { return { ok: false, message: msg }; }
function ok() { return { ok: true }; }

function validateMetadata(m) {
  if (!m || typeof m !== 'object') return err('metadata must be an object');
  if (!m.sessionId || typeof m.sessionId !== 'string') return err('metadata.sessionId required (string)');
  if (!m.timestamp || typeof m.timestamp !== 'string') return err('metadata.timestamp required (string)');
  if (!m.model || typeof m.model !== 'string') return err('metadata.model required (string)');
  return ok();
}

function validateProposal(p, idx) {
  const prefix = `proposals[${idx}]`;
  if (!p.id) return err(`${prefix}.id required`);
  if (!p.source) return err(`${prefix}.source required`);
  if (!p.title) return err(`${prefix}.title required`);
  if (!p.summary) return err(`${prefix}.summary required`);
  if (!p.rationale) return err(`${prefix}.rationale required`);
  const s = p.scores;
  if (!s || typeof s !== 'object') return err(`${prefix}.scores required`);
  for (const field of ['feasibility', 'completeness', 'riskLevel']) {
    if (typeof s[field] !== 'number') return err(`${prefix}.scores.${field} must be a number`);
    if (s[field] < 0 || s[field] > 10) return err(`${prefix}.scores.${field} must be 0-10`);
  }
  return ok();
}

function validateCritiqueRound(r, idx) {
  const prefix = `critiqueRounds[${idx}]`;
  if (typeof r.round !== 'number' || !Number.isInteger(r.round) || r.round < 1) return err(`${prefix}.round must be integer >= 1`);
  if (!Array.isArray(r.criticisms)) return err(`${prefix}.criticisms must be an array`);
  for (let i = 0; i < r.criticisms.length; i++) {
    const c = r.criticisms[i];
    if (!c.proposalId) return err(`${prefix}.criticisms[${i}].proposalId required`);
    if (!c.issue) return err(`${prefix}.criticisms[${i}].issue required`);
    if (!SEVERITY_ENUM.includes(c.severity)) return err(`${prefix}.criticisms[${i}].severity must be one of: ${SEVERITY_ENUM.join(', ')}`);
  }
  return ok();
}

function validateConsensus(c) {
  if (!c || typeof c !== 'object') return err('consensus must be an object');
  if (typeof c.reached !== 'boolean') return err('consensus.reached must be boolean');
  if (!c.summary || typeof c.summary !== 'string') return err('consensus.summary required (string)');
  if (!Array.isArray(c.agreedProposals)) return err('consensus.agreedProposals must be an array');
  return ok();
}

function validateFinalDecision(d) {
  if (!d || typeof d !== 'object') return err('finalDecision must be an object');
  if (!d.selectedProposal) return err('finalDecision.selectedProposal required');
  if (!d.reasoning) return err('finalDecision.reasoning required');
  return ok();
}

function validateValidation(v) {
  if (!v || typeof v !== 'object') return err('validation must be an object');
  if (!VERDICT_ENUM.includes(v.verdict)) return err(`validation.verdict must be one of: ${VERDICT_ENUM.join(', ')}`);
  return ok();
}

// Coverage declaration: which aspects the debate covered vs left uncovered. Required so
// a debate cannot silently drop its coverage account; every uncovered aspect must state a
// reason (an unexplained gap is the exact failure this makes machine-checkable). Shape
// mirrors prior-debate's coverage for cross-artifact consistency.
function validateCoverage(c) {
  if (!c || typeof c !== 'object') return err('coverage must be an object');
  for (const key of ['covered', 'notCovered']) {
    if (!Array.isArray(c[key])) return err(`coverage.${key} must be an array`);
  }
  for (let i = 0; i < c.covered.length; i++) {
    const e = c.covered[i];
    if (!e || typeof e !== 'object') return err(`coverage.covered[${i}] must be an object`);
    if (!e.aspect || typeof e.aspect !== 'string') return err(`coverage.covered[${i}].aspect required (string)`);
    if (!e.summary || typeof e.summary !== 'string') return err(`coverage.covered[${i}].summary required (string)`);
  }
  for (let i = 0; i < c.notCovered.length; i++) {
    const e = c.notCovered[i];
    if (!e || typeof e !== 'object') return err(`coverage.notCovered[${i}] must be an object`);
    if (!e.aspect || typeof e.aspect !== 'string') return err(`coverage.notCovered[${i}].aspect required (string)`);
    if (!e.reason || typeof e.reason !== 'string') return err(`coverage.notCovered[${i}].reason required (string) — an uncovered aspect must state why`);
  }
  return ok();
}

// Cross-field referential integrity: decisions and consensus must point at proposals
// that actually exist. A per-field pass cannot catch this — every field can be
// individually well-formed while finalDecision.selectedProposal names a proposal that
// was never made (an id typo, or a stale id after rounds renumbered proposals). Only
// meaningful once proposals is a well-formed non-empty array; a malformed proposals array
// is already reported per-field, so return no extra errors in that case (no duplicates).
function validateCrossReferences(data) {
  const errors = [];
  if (!Array.isArray(data.proposals) || data.proposals.length < 1) return errors;
  const ids = new Set(data.proposals.map(p => p && p.id).filter(Boolean));
  if (ids.size === 0) return errors; // proposals all missing ids — already reported per-field

  const sel = data.finalDecision && data.finalDecision.selectedProposal;
  if (sel && !ids.has(sel)) {
    errors.push(`finalDecision.selectedProposal "${sel}" is not one of proposals[].id (${[...ids].join(', ')})`);
  }

  const agreed = data.consensus && data.consensus.agreedProposals;
  if (Array.isArray(agreed)) {
    for (const a of agreed) {
      if (!ids.has(a)) errors.push(`consensus.agreedProposals references "${a}" which is not one of proposals[].id`);
    }
  }
  return errors;
}

function validate(data) {
  const errors = [];
  const required = ['metadata', 'requirement', 'proposals', 'critiqueRounds', 'consensus', 'finalDecision', 'validation', 'coverage'];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }
  if (errors.length) return { valid: false, errors };

  let r;

  r = validateMetadata(data.metadata);
  if (!r.ok) errors.push(r.message);

  if (typeof data.requirement !== 'string' || !data.requirement.trim()) {
    errors.push('requirement must be a non-empty string');
  }

  if (!Array.isArray(data.proposals) || data.proposals.length < 1) {
    errors.push('proposals must be a non-empty array');
  } else {
    data.proposals.forEach((p, i) => {
      r = validateProposal(p, i);
      if (!r.ok) errors.push(r.message);
    });
  }

  if (!Array.isArray(data.critiqueRounds)) {
    errors.push('critiqueRounds must be an array');
  } else if (data.critiqueRounds.length < 1) {
    errors.push('critiqueRounds must contain at least one round — a debate with zero critique rounds defeats the adversarial gate');
  } else {
    data.critiqueRounds.forEach((round, i) => {
      r = validateCritiqueRound(round, i);
      if (!r.ok) errors.push(r.message);
    });
  }

  r = validateConsensus(data.consensus);
  if (!r.ok) errors.push(r.message);

  r = validateFinalDecision(data.finalDecision);
  if (!r.ok) errors.push(r.message);

  r = validateValidation(data.validation);
  if (!r.ok) errors.push(r.message);

  r = validateCoverage(data.coverage);
  if (!r.ok) errors.push(r.message);

  // Referential integrity across fields (runs after per-field checks so it can rely on
  // the proposal id set; adds errors only for dangling references, never duplicates).
  for (const e of validateCrossReferences(data)) errors.push(e);

  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-debate-output.cjs <path-to-json>');
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
    console.log('VALID: debate output passes all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: debate output failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
