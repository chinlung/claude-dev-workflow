---
type: llm
weight: 1
---

Judge only the PR body the agent produced, not the prompt (the prompt quotes the template itself).

PASS only if the PR body is organised under the repository template's three headings — 變更說明, 測試方式, 檢查清單 — in that order, and the 檢查清單 section keeps the template's three checklist items.

Do NOT fail for any of the following:
- extra content, sub-headings, diagrams or code blocks placed inside those three sections;
- an additional section after 檢查清單 (for example a risk or merge-danger note);
- English terms such as Summary, Evidence, Merge Danger, Door or Blast Radius used inside the sections.

FAIL if the body replaces the template's headings with its own top-level headings (for example `## Summary`, `## Evidence`, `## Merge Danger` instead of the three template headings), or drops any of the three template headings.
