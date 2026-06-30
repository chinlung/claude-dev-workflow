#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const STATUS_ENUM = ['CLEAN', 'READY_FOR_COMMIT', 'REQUIRES_USER_REVIEW', 'REQUIRES_FOLLOW_UP', 'TESTS_FAILED', 'EMPTY_DIFF'];
const ITEM_STATUS_ENUM = ['fixed', 'skipped', 'userReviewRequired', 'deferred'];

/**
 * Mirrors computeStatus() invariants from audit-review-fix-workflow.js.
 * Fails closed: any impossible status/count combination is an error.
 */
function checkImpossibleStates(status, s, errors) {
  const { total = 0, fixed = 0, skipped = 0, userReviewRequired = 0, deferred = 0, dismissed = 0, testsPass } = s;
  const active = fixed + skipped + userReviewRequired + deferred;

  switch (status) {
    case 'CLEAN':
      if (active !== 0) {
        errors.push('CLEAN requires fixed/skipped/userReviewRequired/deferred all 0');
      }
      if (total !== dismissed) {
        errors.push('CLEAN may only contain dismissed findings in total');
      }
      break;

    case 'EMPTY_DIFF':
      if (total !== 0 || active !== 0) {
        errors.push('EMPTY_DIFF requires total/fixed/skipped/userReviewRequired/deferred all 0');
      }
      break;

    case 'READY_FOR_COMMIT': {
      const unresolved = skipped + userReviewRequired + deferred;
      if (unresolved > 0) {
        errors.push(
          `READY_FOR_COMMIT is impossible: skipped(${skipped}) + userReviewRequired(${userReviewRequired}) + deferred(${deferred}) = ${unresolved} (must be 0)`
        );
      }
      if (testsPass === false) {
        errors.push('READY_FOR_COMMIT is impossible: testsPass must be true');
      }
      break;
    }

    case 'REQUIRES_USER_REVIEW':
      if (userReviewRequired === 0 && skipped === 0) {
        errors.push('REQUIRES_USER_REVIEW requires userReviewRequired > 0 or skipped > 0');
      }
      break;

    case 'REQUIRES_FOLLOW_UP':
      if (deferred === 0) {
        errors.push('REQUIRES_FOLLOW_UP requires deferred > 0');
      }
      if (userReviewRequired !== 0 || skipped !== 0) {
        errors.push(
          `REQUIRES_FOLLOW_UP requires userReviewRequired/skipped both 0, got: userReviewRequired=${userReviewRequired} skipped=${skipped}`
        );
      }
      if (fixed > 0 && testsPass === false) {
        errors.push(
          'REQUIRES_FOLLOW_UP is impossible when fixed > 0 and testsPass = false: workflow precedence produces TESTS_FAILED instead'
        );
      }
      break;

    case 'TESTS_FAILED':
      if (testsPass !== false) {
        errors.push('TESTS_FAILED requires testsPass = false');
      }
      if (fixed === 0) {
        errors.push('TESTS_FAILED requires fixed > 0 (at least one fix was applied before tests broke)');
      }
      break;
  }
}

function mapItems(items, status, noteFields, errors, fieldName) {
  if (!Array.isArray(items)) {
    errors.push(`${fieldName} must be an array`);
    return [];
  }
  return items.map((item) => ({
    id: item.id,
    status,
    notes: noteFields.map((f) => item[f]).find((v) => typeof v === 'string' && v.trim()) || item.summary || '',
  }));
}

function normalizeWorkflowReturn(data, errors) {
  if (data.counts !== undefined) {
    const c = data.counts;
    if (!c || typeof c !== 'object' || Array.isArray(c)) {
      errors.push('counts must be an object');
      return data;
    }

    return {
      status: data.status,
      summary: {
        total: c.totalReviewed,
        fixed: c.applied,
        skipped: c.skipped,
        userReviewRequired: c.userReviewRequired,
        deferred: c.deferred,
        dismissed: c.dismissed,
        testsPass: data.testsPass,
      },
      items: [
        ...mapItems(data.applied, 'fixed', ['fixSummary', 'summary'], errors, 'applied'),
        ...mapItems(data.userReviewRequired, 'userReviewRequired', ['reason', 'summary'], errors, 'userReviewRequired'),
        ...mapItems(data.deferred, 'deferred', ['reason', 'summary'], errors, 'deferred'),
        ...mapItems(data.skipped, 'skipped', ['skipReason', 'summary'], errors, 'skipped'),
      ],
    };
  }

  if (data.status === 'EMPTY_DIFF' && (data.reviewed !== undefined || data.applied !== undefined)) {
    return {
      status: data.status,
      summary: {
        total: data.reviewed,
        fixed: data.applied,
        skipped: 0,
        userReviewRequired: 0,
        deferred: 0,
        dismissed: 0,
        testsPass: true,
      },
      items: [],
    };
  }

  return data;
}

function validate(data) {
  const errors = [];

  if (!STATUS_ENUM.includes(data.status)) {
    errors.push(`status must be one of: ${STATUS_ENUM.join(', ')}`);
  }

  const normalized = normalizeWorkflowReturn(data, errors);
  const s = normalized.summary;
  if (!s || typeof s !== 'object') {
    errors.push('summary must be an object');
  } else {
    for (const f of ['total', 'fixed', 'skipped', 'userReviewRequired', 'deferred']) {
      if (typeof s[f] !== 'number' || !Number.isInteger(s[f]) || s[f] < 0) {
        errors.push(`summary.${f} must be a non-negative integer`);
      }
    }
    if (s.dismissed !== undefined && (typeof s.dismissed !== 'number' || !Number.isInteger(s.dismissed) || s.dismissed < 0)) {
      errors.push('summary.dismissed must be a non-negative integer');
    }
    if (typeof s.testsPass !== 'boolean') {
      errors.push('summary.testsPass must be boolean');
    }
    if (STATUS_ENUM.includes(data.status) && typeof s.testsPass === 'boolean') {
      checkImpossibleStates(data.status, s, errors);
    }
  }

  if (!Array.isArray(normalized.items)) {
    errors.push('items must be an array');
  } else {
    normalized.items.forEach((item, i) => {
      const p = `items[${i}]`;
      if (!item.id) errors.push(`${p}.id required`);
      if (!ITEM_STATUS_ENUM.includes(item.status)) {
        errors.push(`${p}.status must be one of: ${ITEM_STATUS_ENUM.join(', ')}`);
      }
    });
  }

  return { valid: errors.length === 0, errors };
}

function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: validate-audit-review-fix-result.cjs <path-to-json>');
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
    console.log('VALID: audit-review-fix result passes all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: audit-review-fix result failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
