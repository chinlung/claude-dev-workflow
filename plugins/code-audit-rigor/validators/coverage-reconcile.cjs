#!/usr/bin/env node
'use strict';

/**
 * coverage-reconcile.cjs
 *
 * Zero-dependency Node CLI. Validates coverage completeness of a
 * review-branch-results.json artifact:
 *
 *   1. scopedFiles must be a non-empty array.
 *   2. No duplicate file entries in scopedFiles.
 *   3. Every 'skipped' entry must have a non-empty skipReason.
 *   4. Every file appearing in suggestions must also appear in scopedFiles
 *      (unaccounted suggestion file = coverage gap).
 *   5. Every file in scopedFiles must have a status of 'reviewed' or 'skipped'.
 *      Files present in scopedFiles but with no valid status are flagged.
 *   6. Every suggestion must include a file so it can be reconciled to scope.
 *
 * Exits 0 (PASS), 1 (coverage issues found), or 2 (usage/IO error).
 *
 * Usage: node coverage-reconcile.cjs <path-to-review-branch-results.json>
 */

const fs = require('fs');
const path = require('path');

const VALID_STATUS = ['reviewed', 'skipped'];

function reconcile(data) {
  const errors = [];
  const warnings = [];

  // 1. scopedFiles must be present and non-empty
  if (!Array.isArray(data.scopedFiles)) {
    errors.push('scopedFiles is missing or not an array — no coverage information present');
    return { passed: false, errors, warnings };
  }
  if (data.scopedFiles.length === 0) {
    errors.push('scopedFiles is empty — at least one file must be in scope for a review to be complete');
    return { passed: false, errors, warnings };
  }

  // 2. Duplicate detection
  const seen = new Map(); // file -> first index
  for (let i = 0; i < data.scopedFiles.length; i++) {
    const entry = data.scopedFiles[i];
    const file = entry.file;
    if (!file) continue; // let schema validator handle missing .file
    if (seen.has(file)) {
      errors.push(`Duplicate file in scopedFiles: "${file}" appears at index ${seen.get(file)} and ${i}`);
    } else {
      seen.set(file, i);
    }
  }

  // 3. Skipped entries must have skipReason
  for (let i = 0; i < data.scopedFiles.length; i++) {
    const entry = data.scopedFiles[i];
    if (entry.status === 'skipped') {
      if (!entry.skipReason || typeof entry.skipReason !== 'string' || !entry.skipReason.trim()) {
        errors.push(`scopedFiles[${i}] ("${entry.file || '?'}"): status is 'skipped' but skipReason is missing or empty`);
      }
    }
  }

  // 4. Status must be one of VALID_STATUS
  for (let i = 0; i < data.scopedFiles.length; i++) {
    const entry = data.scopedFiles[i];
    if (entry.status === undefined) {
      errors.push(`scopedFiles[${i}] ("${entry.file || '?'}"): status is missing — must be reviewed or skipped`);
    } else if (!VALID_STATUS.includes(entry.status)) {
      errors.push(`scopedFiles[${i}] ("${entry.file || '?'}"): unknown status "${entry.status}" — must be reviewed or skipped`);
    }
  }

  // 5. Every file in suggestions must appear in scopedFiles
  if (Array.isArray(data.suggestions)) {
    const scopedSet = new Set(data.scopedFiles.map(e => e.file).filter(Boolean));
    const unaccountedFiles = new Set();
    for (let i = 0; i < data.suggestions.length; i++) {
      const s = data.suggestions[i];
      if (!s.file || typeof s.file !== 'string' || !s.file.trim()) {
        errors.push(`suggestions[${i}].file is missing or empty — cannot reconcile suggestion to scopedFiles`);
      } else if (!scopedSet.has(s.file)) {
        unaccountedFiles.add(s.file);
      }
    }
    for (const f of unaccountedFiles) {
      errors.push(`Unaccounted suggestion file: "${f}" appears in suggestions but is not listed in scopedFiles — add it with status 'reviewed' or 'skipped' (with reason)`);
    }
  }

  // Summary stats (for reporting)
  const reviewed = data.scopedFiles.filter(e => e.status === 'reviewed').length;
  const skipped = data.scopedFiles.filter(e => e.status === 'skipped').length;
  const total = data.scopedFiles.length;

  return { passed: errors.length === 0, errors, warnings, stats: { total, reviewed, skipped } };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: coverage-reconcile.cjs <path-to-review-branch-results.json>');
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
    process.exit(2);
  }

  const result = reconcile(data);

  if (result.stats) {
    console.log(`Coverage: ${result.stats.reviewed} reviewed, ${result.stats.skipped} skipped (with reason), ${result.stats.total} total scoped files`);
  }

  if (result.passed) {
    console.log('PASS: coverage reconciliation complete — all scoped files accounted for.');
    process.exit(0);
  } else {
    console.error('FAIL: coverage reconciliation found issues:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
