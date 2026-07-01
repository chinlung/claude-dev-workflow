#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const REQUIRED_FILES = ['proposal.md', 'design.md', 'tasks.md', 'review-notes.md'];

function findSpecFiles(dir) {
  const results = [];
  function walk(current) {
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch (_) {
      return;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile() && entry.name === 'spec.md') {
        results.push(full);
      }
    }
  }
  const specsDir = path.join(dir, 'specs');
  if (fs.existsSync(specsDir)) walk(specsDir);
  return results;
}

/**
 * Check all `### Requirement:` blocks in a markdown file.
 * Each such block's first paragraph must contain SHALL or MUST (case-insensitive).
 * Returns array of error strings.
 */
function checkRequirementBlocks(filePath, content) {
  const errors = [];
  // Split content into lines for processing
  const lines = content.split('\n');
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    // Match lines that start a Requirement heading (### Requirement: ...)
    if (/^###\s+Requirement:/i.test(line)) {
      const headingLine = i + 1; // 1-based for display
      // Collect the first paragraph after the heading
      // Skip blank lines immediately after heading
      let j = i + 1;
      while (j < lines.length && lines[j].trim() === '') j++;
      // Collect non-blank lines forming the first paragraph
      const paragraphLines = [];
      while (j < lines.length && lines[j].trim() !== '') {
        // Stop if we hit another heading
        if (/^#+\s/.test(lines[j])) break;
        paragraphLines.push(lines[j]);
        j++;
      }
      const paragraph = paragraphLines.join(' ');
      if (!/\bSHALL\b|\bMUST\b/i.test(paragraph)) {
        errors.push(
          `${filePath}:${headingLine}: Requirement block "${line.trim()}" — first paragraph lacks SHALL or MUST.\n  First paragraph: "${paragraph.trim() || '(empty)'}"`
        );
      }
      i = j;
    } else {
      i++;
    }
  }
  return errors;
}

function validate(folderPath) {
  const errors = [];
  const absFolder = path.resolve(folderPath);

  // Check folder exists
  if (!fs.existsSync(absFolder)) {
    return { valid: false, errors: [`Folder does not exist: ${absFolder}`] };
  }

  // Check required files
  for (const file of REQUIRED_FILES) {
    const filePath = path.join(absFolder, file);
    if (!fs.existsSync(filePath)) {
      errors.push(`Missing required file: ${file}`);
    }
  }

  // Check specs/**/spec.md exists
  const specFiles = findSpecFiles(absFolder);
  if (specFiles.length === 0) {
    errors.push('No specs/**/spec.md found in change folder');
  }

  // Check SHALL/MUST in all spec.md requirement blocks
  for (const specFile of specFiles) {
    let content;
    try {
      content = fs.readFileSync(specFile, 'utf8');
    } catch (e) {
      errors.push(`Cannot read ${specFile}: ${e.message}`);
      continue;
    }
    const specErrors = checkRequirementBlocks(specFile, content);
    errors.push(...specErrors);
  }

  return { valid: errors.length === 0, errors };
}

function main() {
  const folderPath = process.argv[2];
  if (!folderPath) {
    console.error('Usage: validate-openspec-workflow.cjs <change-folder-path>');
    process.exit(2);
  }

  const result = validate(folderPath);
  if (result.valid) {
    console.log('VALID: openspec change folder passes all checks.');
    process.exit(0);
  } else {
    console.error('INVALID: openspec change folder failed validation:');
    result.errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }
}

main();
