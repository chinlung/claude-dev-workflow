#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const SEVERITY_ENUM = ['critical', 'high', 'medium', 'low'];
const VERDICT_ENUM = ['APPROVED', 'REJECTED', 'NEEDS_REVISION'];

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
  if (typeof r.round !== 'number' || r.round < 1) return err(`${prefix}.round must be integer >= 1`);
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

function validate(data) {
  const errors = [];
  const required = ['metadata', 'requirement', 'proposals', 'critiqueRounds', 'consensus', 'finalDecision', 'validation'];
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
