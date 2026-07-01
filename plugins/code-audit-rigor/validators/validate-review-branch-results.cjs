#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const FILE_STATUS_ENUM = ['reviewed', 'skipped'];
const SEVERITY_ENUM = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO'];
const VERDICT_ENUM = ['PASS', 'FAIL', 'SKIP'];

function validate(data) {
  const errors = [];
  const required = ['branch', 'scopedFiles', 'suggestions', 'verifications'];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }

  if (data.branch !== undefined && (!data.branch || typeof data.branch !== 'string')) {
    errors.push('branch must be a non-empty string');
  }

  if (data.scopedFiles !== undefined) {
    if (!Array.isArray(data.scopedFiles) || data.scopedFiles.length < 1) {
      errors.push('scopedFiles must be a non-empty array');
    } else {
      data.scopedFiles.forEach((f, i) => {
        const p = `scopedFiles[${i}]`;
        if (!f.file) errors.push(`${p}.file required`);
        if (!FILE_STATUS_ENUM.includes(f.status)) {
          errors.push(`${p}.status must be one of: ${FILE_STATUS_ENUM.join(', ')}`);
        }
        if (f.status === 'skipped' && (!f.skipReason || typeof f.skipReason !== 'string')) {
          errors.push(`${p}.skipReason required when status is 'skipped'`);
        }
      });
    }
  }

  if (data.suggestions !== undefined) {
    if (!Array.isArray(data.suggestions)) {
      errors.push('suggestions must be an array');
    } else {
      data.suggestions.forEach((s, i) => {
        const p = `suggestions[${i}]`;
        if (!s.file) errors.push(`${p}.file required`);
        if (typeof s.line !== 'number' || !Number.isInteger(s.line) || s.line < 1) errors.push(`${p}.line must be integer >= 1`);
        if (!s.quotedCode) errors.push(`${p}.quotedCode required`);
        if (!s.description) errors.push(`${p}.description required`);
        if (!SEVERITY_ENUM.includes(s.severity)) {
          errors.push(`${p}.severity must be one of: ${SEVERITY_ENUM.join(', ')}`);
        }
      });
    }
  }

  if (data.verifications !== undefined) {
    if (!Array.isArray(data.verifications)) {
      errors.push('verifications must be an array');
    } else {
      data.verifications.forEach((v, i) => {
        const p = `verifications[${i}]`;
        if (!v.id) errors.push(`${p}.id required`);
        if (!VERDICT_ENUM.includes(v.verdict)) {
          errors.push(`${p}.verdict must be one of: ${VERDICT_ENUM.join(', ')}`);
        }
      });
    }
  }

  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-review-branch-results.cjs <path-to-json>');
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
    console.log('VALID: review-branch results pass all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: review-branch results failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
