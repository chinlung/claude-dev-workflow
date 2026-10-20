---
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
runs: 3
---

Write the pull request description for this change.

(The working directory is an empty sandbox: not a git repository, and no commands can be run. The change exists only in the description below. Paste the complete PR body in your reply.)

The project is `notes-cli`, a note-taking CLI written in Node.js. This branch adds a `--json` flag to `notes list`:

- `src/commands/list.js`: parses `--json`; when present it calls `formatJson()`, otherwise it prints the table as before.
- `src/format/json.js` (new): `formatJson(notes)` prints the notes as `[{ "id", "title", "updatedAt" }]`, with `updatedAt` in ISO 8601.
- `README.md`: documents `--json` in the "Listing notes" section.

No other command and no config format changed.
