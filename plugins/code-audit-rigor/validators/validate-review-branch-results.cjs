#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const FILE_STATUS_ENUM = ['reviewed', 'skipped'];
// Where the reviewed version of a scoped file came from (2.0.1). Required: a result file
// without it is indistinguishable from a committed-only run, and /review-branch is the
// only producer (no consumer re-validates older result files).
const SOURCE_ENUM = ['committed', 'working-tree', 'untracked'];
const SEVERITY_ENUM = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO'];
const VERDICT_ENUM = ['PASS', 'FAIL', 'SKIP'];
// 2.1.0: `since-last` means the scope was narrowed to what changed since the previous round.
const SCOPE_MODE_ENUM = ['full', 'since-last'];
const RISK_TIER_ENUM = ['standard', 'deep'];

const isNonEmptyString = (v) => typeof v === 'string' && v.length > 0;
const isPosInt = (v) => Number.isInteger(v) && v >= 1;

// A list of {file, quotedCode, round} anchors — `dismissed` and `carried` share the shape.
function checkAnchors(list, name, errors) {
  if (list === undefined) return;
  if (!Array.isArray(list)) { errors.push(`${name} must be an array`); return; }
  list.forEach((d, i) => {
    const p = `${name}[${i}]`;
    if (!d || typeof d !== 'object') { errors.push(`${p} must be an object`); return; }
    if (!isNonEmptyString(d.file)) errors.push(`${p}.file required`);
    if (!isNonEmptyString(d.quotedCode)) errors.push(`${p}.quotedCode required`);
    if (!isPosInt(d.round)) errors.push(`${p}.round must be integer >= 1`);
  });
}

function validate(data) {
  const errors = [];
  const required = ['branch', 'scopedFiles', 'suggestions', 'verifications'];
  for (const f of required) {
    if (data[f] === undefined || data[f] === null) errors.push(`Missing required field: ${f}`);
  }

  if (data.branch !== undefined && (!data.branch || typeof data.branch !== 'string')) {
    errors.push('branch must be a non-empty string');
  }
  if (data.round !== undefined && !isPosInt(data.round)) errors.push('round must be integer >= 1');
  if (data.scopeMode !== undefined && !SCOPE_MODE_ENUM.includes(data.scopeMode)) {
    errors.push(`scopeMode must be one of: ${SCOPE_MODE_ENUM.join(', ')}`);
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
        if (!SOURCE_ENUM.includes(f.source)) {
          errors.push(`${p}.source required, must be one of: ${SOURCE_ENUM.join(', ')}`);
        }
        if (f.blob !== undefined && !isNonEmptyString(f.blob)) errors.push(`${p}.blob must be a non-empty string when present`);
        if (f.unchangedSince !== undefined && !isPosInt(f.unchangedSince)) errors.push(`${p}.unchangedSince must be integer >= 1 when present`);
      });
    }
  }

  let suggestionCount = 0;
  if (data.suggestions !== undefined) {
    if (!Array.isArray(data.suggestions)) {
      errors.push('suggestions must be an array');
    } else {
      suggestionCount = data.suggestions.length;
      data.suggestions.forEach((s, i) => {
        const p = `suggestions[${i}]`;
        if (!s.file) errors.push(`${p}.file required`);
        if (typeof s.line !== 'number' || !Number.isInteger(s.line) || s.line < 1) errors.push(`${p}.line must be integer >= 1`);
        if (!s.quotedCode) errors.push(`${p}.quotedCode required`);
        if (!s.description) errors.push(`${p}.description required`);
        if (!SEVERITY_ENUM.includes(s.severity)) {
          errors.push(`${p}.severity must be one of: ${SEVERITY_ENUM.join(', ')}`);
        }
        // 2.1.0: required, like `source` — a file without it cannot be told from a run that never
        // computed it, and the tag is what keeps a pre-existing defect from reading as the author's.
        if (typeof s.introduced !== 'boolean') errors.push(`${p}.introduced required (boolean; review-branch-rounds.cjs annotate fills it)`);
        if (s.class !== undefined && !isNonEmptyString(s.class)) errors.push(`${p}.class must be a non-empty string when present`);
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
        if (v.suggestion !== undefined) {
          if (!Number.isInteger(v.suggestion) || v.suggestion < 0) errors.push(`${p}.suggestion must be an integer >= 0 (index into suggestions)`);
          else if (v.suggestion >= suggestionCount) errors.push(`${p}.suggestion ${v.suggestion} is out of range (${suggestionCount} suggestions)`);
        }
      });
    }
  }

  checkAnchors(data.dismissed, 'dismissed', errors);
  checkAnchors(data.carried, 'carried', errors);

  if (data.risk !== undefined) {
    if (!data.risk || typeof data.risk !== 'object' || Array.isArray(data.risk)) errors.push('risk must be an object');
    else {
      if (!RISK_TIER_ENUM.includes(data.risk.tier)) errors.push(`risk.tier must be one of: ${RISK_TIER_ENUM.join(', ')}`);
      if (!Array.isArray(data.risk.hits)) errors.push('risk.hits must be an array');
    }
  }

  // A suggestion whose anchor was dismissed in an EARLIER round is a re-post. Same-round entries are
  // this round's own FAIL verdicts (annotate records them), so only strictly earlier rounds count.
  if (Array.isArray(data.suggestions) && Array.isArray(data.dismissed)) {
    const current = isPosInt(data.round) ? data.round : 1;
    const earlier = new Map();
    for (const d of data.dismissed) {
      if (d && isNonEmptyString(d.file) && isNonEmptyString(d.quotedCode) && isPosInt(d.round) && d.round < current) {
        earlier.set(`${d.file}\u0000${d.quotedCode}`, d.round);
      }
    }
    data.suggestions.forEach((s, i) => {
      if (!s || !isNonEmptyString(s.file) || !isNonEmptyString(s.quotedCode)) return;
      const r = earlier.get(`${s.file}\u0000${s.quotedCode}`);
      if (r !== undefined) errors.push(`suggestions[${i}] re-posts an anchor dismissed in round ${r} (${s.file}) — drop it or re-open it with new evidence in the report`);
    });
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
