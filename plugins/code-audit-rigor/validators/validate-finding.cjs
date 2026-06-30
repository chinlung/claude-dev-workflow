#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const SEVERITY_ENUM = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO'];
const DECISION_ENUM = ['FIX', 'SKIP', 'DEFER', 'USER_REVIEW'];
const STRIDE_ENUM = ['S', 'T', 'R', 'I', 'D', 'E'];
const CWE_PATTERN = /^CWE-[0-9]+$/;

function validate(data) {
  const errors = [];
  const required = ['id', 'title', 'severity', 'confidence', 'ev', 'decision', 'description', 'crossReferences'];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }

  if (data.severity !== undefined && !SEVERITY_ENUM.includes(data.severity)) {
    errors.push(`severity must be one of: ${SEVERITY_ENUM.join(', ')}`);
  }
  if (data.confidence !== undefined) {
    if (typeof data.confidence !== 'number' || data.confidence < 0 || data.confidence > 100) {
      errors.push('confidence must be a number 0-100');
    }
  }
  if (data.ev !== undefined && typeof data.ev !== 'number') {
    errors.push('ev must be a number');
  }
  if (data.decision !== undefined && !DECISION_ENUM.includes(data.decision)) {
    errors.push(`decision must be one of: ${DECISION_ENUM.join(', ')}`);
  }

  if (data.crossReferences !== undefined) {
    if (!Array.isArray(data.crossReferences) || data.crossReferences.length < 1) {
      errors.push('crossReferences must be a non-empty array');
    } else {
      data.crossReferences.forEach((ref, i) => {
        const p = `crossReferences[${i}]`;
        if (!ref.file) errors.push(`${p}.file required`);
        if (!ref.lines) errors.push(`${p}.lines required`);
        if (!ref.quotedCode) errors.push(`${p}.quotedCode required`);
        if (!ref.note) errors.push(`${p}.note required`);
      });
    }
  }

  if (data.security !== undefined) {
    if (!data.security || typeof data.security !== 'object') {
      errors.push('security must be an object when present');
    } else {
      if (!STRIDE_ENUM.includes(data.security.stride)) {
        errors.push(`security.stride must be one of: ${STRIDE_ENUM.join(', ')}`);
      }
      if (!data.security.cwe || !CWE_PATTERN.test(data.security.cwe)) {
        errors.push('security.cwe must match pattern CWE-<number>');
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-finding.cjs <path-to-json>');
    process.exit(2);
  }
  const absPath = path.resolve(filePath);
  let raw;
  try { raw = fs.readFileSync(absPath, 'utf8'); } catch (e) {
    console.error(`Cannot read file: ${absPath}`);
    process.exit(2);
  }
  let data;
  try { data = JSON.parse(raw); } catch (e) {
    console.error(`Invalid JSON: ${e.message}`);
    process.exit(1);
  }

  const result = validate(data);
  if (result.valid) {
    console.log('VALID: finding passes all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: finding failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
