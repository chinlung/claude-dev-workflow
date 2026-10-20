---
type: llm
weight: 1
---

Judge only the PR body the agent produced, not the prompt.

PASS only if all of the following hold:
1. The body shows both the failing run before the fix and the passing run after it, using the test output from the prompt (quoted or excerpted, not paraphrased into different numbers).
2. The body states whether merging is a one-way door (hard to reverse) or a two-way door (cheap to roll back), and says how far the change's effects reach (its blast radius).

Do NOT fail for wording, language, or section names, as long as both points are clearly present.
