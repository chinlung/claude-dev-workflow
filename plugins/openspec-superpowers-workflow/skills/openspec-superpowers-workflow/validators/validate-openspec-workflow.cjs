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

// OpenSpec lets a pure refactor or tooling change opt out of specs with `skip_specs: true` in .openspec.yaml.
// The one reading of that flag: gate-check (P1), reconcile-check (R1) and validate() below all call this.
// OpenSpec 2.1.0 (readSkipSpecsMarker, dist/utils/change-metadata.js) honors the flag only when the file is valid
// change metadata, so `schema` is required. Without a YAML parser this matches the common forms: a top-level
// `skip_specs` key (quotes allowed) whose value on the same line is boolean true, optionally followed by a
// comment, and a top-level `schema` with a value. It is a text match, not a parse, so it honors some files OpenSpec
// refuses. Known ones (not a complete list): a schema that does not exist or is not a non-empty string (`''`, `~`,
// `123`), a duplicate key, more than one YAML document or a `...` end marker, flow or multi-line forms.
// `openspec validate` decides those; do not grow the patterns to chase them.
const NO_SPECS = 'no specs/**/spec.md, and .openspec.yaml does not declare skip_specs: true (the flag counts only next to a top-level schema: line)';
const SKIP_SPECS_TRUE = /^(['"]?)skip_specs\1[ \t]*:[ \t]*(?:true|True|TRUE)(?:[ \t]+#.*)?[ \t]*$/m;
const SCHEMA_SET = /^(['"]?)schema\1[ \t]*:[ \t]*[^\s#]/m;
function skipsSpecs(changeDir) {
  let yaml;
  try { yaml = fs.readFileSync(path.join(changeDir, '.openspec.yaml'), 'utf8').replace(/\r\n/g, '\n'); } catch { return false; }
  return SKIP_SPECS_TRUE.test(yaml) && SCHEMA_SET.test(yaml);
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

  // Check specs/**/spec.md exists, unless the change opts out with skip_specs: true
  const specFiles = findSpecFiles(absFolder);
  if (specFiles.length === 0 && !skipsSpecs(absFolder)) {
    errors.push(NO_SPECS);
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

// CLI when run directly; reconcile-check.cjs requires these functions instead of copying them.
if (require.main === module) main();
module.exports = { REQUIRED_FILES, NO_SPECS, findSpecFiles, skipsSpecs, checkRequirementBlocks };
