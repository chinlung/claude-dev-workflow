---
type: llm
weight: 1
---

PASS only if the reply gives a git commit message: a single subject line of at most 72 characters, followed by a short body of a few lines describing the `--json` change.

FAIL if the reply instead produces a pull-request description — for example sections headed Summary, Evidence or Merge Danger, a "Door"/"Blast Radius" assessment, or a before/after evidence block.
