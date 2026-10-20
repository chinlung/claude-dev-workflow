---
type: llm
weight: 1
---

Judge only the PR body the agent produced. Ignore any preface or closing remark the agent wrote outside the body.

Nothing in the prompt says which language the repository's existing pull requests use, and the agent cannot look them up.

PASS only if the PR body's prose — the sentences, outside code blocks, file paths, identifiers and technical terms — is written in Traditional Chinese.

Do NOT fail for any of the following:
- English section headings such as `## Summary`, `## Evidence`, `## Merge Danger`, or field names such as `**Door:**` and `**Blast Radius:**`;
- English technical terms, flag names, file paths, code and command output inside the prose.

FAIL if the prose is in English, or in Simplified Chinese.
