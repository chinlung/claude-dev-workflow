---
type: llm
weight: 1
---

Judge only the PR body the agent produced. Ignore any preface or closing remark the agent wrote outside the body — a Chinese sentence such as "以下是 PR 描述：" before the body must NOT cause a failure.

The prompt says the repository's existing pull requests are all written in English.

PASS only if the PR body's prose — the sentences, outside code blocks, file paths and identifiers — is written in English.

FAIL if the body's prose is in Chinese (Traditional or Simplified), or mixes Chinese sentences into the body.
