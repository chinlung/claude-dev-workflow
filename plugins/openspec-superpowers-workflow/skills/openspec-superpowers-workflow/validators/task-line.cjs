'use strict';
// What counts as a task in tasks.md: the same line pattern OpenSpec 1.16.1 uses (dist/utils/task-progress.js,
// TASK_LINE_PATTERN), so reconcile-check R6 and openspec-archive-stats agree with `openspec instructions apply`.
// Bullets `-`, `*`, `+`, `1.`, `1)` all count, at any indentation; the box is done only when it holds x or X,
// so `[~]`, `[]` and `[1]` are unfinished; a bracket followed by `(` or `[` is a Markdown link, not a task,
// except a whitespace-only box which still counts. Unanchored at the end so CRLF lines match.
// tests/cli-claims.test.sh checks this module against the real CLI on every bullet and marker form.
const TASK_LINE = /^\s*(?:[-*+]|\d{1,9}[.)])\s*\[(?:\s*([^\]\s]?)\s*\](?![([])|\s+\])\s*(.*)/;

// A skip reason is the suffix the workflow teaches, ` — skip: <reason>`: whitespace, a dash (—, –, - or --),
// whitespace, "skip:" (half- or full-width colon), then at least one letter or digit somewhere after it. So
// `— skip: （範圍外）`, `— skip: "not required"` and `- skip: \`docs/x.md\`` all count; "skip:" alone or followed only
// by punctuation does not, and neither does a "skip:" the task text merely mentions (`add a skip: flag`,
// `noskip:`, `the --skip: option`): without the dash and the spaces around it, it is not the suffix.
const SKIP_REASON = /\s(?:—|–|-{1,2})\s+skip[:：].*[\p{L}\p{N}]/u;

// → [{ line, no (1-based), done, skipped }] for every task line of the text, in order; `skipped` is an
// unfinished task excused with a skip reason, so "open work" is `!done && !skipped` for every consumer.
function parseTaskLines(text) {
  const out = [];
  (text || '').split('\n').forEach((line, i) => {
    const m = line.match(TASK_LINE);
    if (m) {
      const done = (m[1] ?? '').toLowerCase() === 'x';
      out.push({ line, no: i + 1, done, skipped: !done && SKIP_REASON.test(line) });
    }
  });
  return out;
}

module.exports = { parseTaskLines };
