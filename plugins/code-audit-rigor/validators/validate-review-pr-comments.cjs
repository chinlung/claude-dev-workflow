#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const CLASSIFICATION_ENUM = ['bug', 'security', 'style', 'test', 'question', 'other'];
const DECISION_ENUM = ['fix', 'skip', 'block'];

function validateComment(c, i) {
  const errors = [];
  const p = `comments[${i}]`;
  const required = ['endpoint', 'id', 'author', 'body', 'classification', 'decision'];
  for (const f of required) {
    if (c[f] === undefined || c[f] === null || c[f] === '') {
      errors.push(`${p}.${f} required`);
    }
  }
  if (c.classification !== undefined && !CLASSIFICATION_ENUM.includes(c.classification)) {
    errors.push(`${p}.classification must be one of: ${CLASSIFICATION_ENUM.join(', ')}`);
  }
  if (c.decision !== undefined && !DECISION_ENUM.includes(c.decision)) {
    errors.push(`${p}.decision must be one of: ${DECISION_ENUM.join(', ')}`);
  }
  if (c.decision === 'fix') {
    if (!c.fix || !c.fix.evidence) {
      errors.push(`${p}.fix.evidence required when decision is 'fix'`);
    }
  }
  if (c.decision === 'skip') {
    if (!c.skip || !c.skip.rationale) {
      errors.push(`${p}.skip.rationale required when decision is 'skip'`);
    }
  }
  if (c.decision === 'block') {
    if (!c.block || !c.block.rationale) {
      errors.push(`${p}.block.rationale required when decision is 'block'`);
    }
  }
  return errors;
}

function validate(data) {
  const errors = [];
  if (!data.prNumber || typeof data.prNumber !== 'number' || !Number.isInteger(data.prNumber)) {
    errors.push('prNumber required (integer)');
  }
  if (!Array.isArray(data.comments)) {
    errors.push('comments must be an array');
  } else {
    data.comments.forEach((c, i) => {
      errors.push(...validateComment(c, i));
    });
  }
  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-review-pr-comments.cjs <path-to-json>');
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
    console.log('VALID: review PR comments pass all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: review PR comments failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
