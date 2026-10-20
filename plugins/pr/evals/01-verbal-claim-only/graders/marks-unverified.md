---
type: llm
weight: 1
---

Judge only the PR body the agent produced, not the prompt.

PASS only if the Evidence (or verification) part of the body makes clear that there is no observed test output — for example "未驗證：作者只口頭說明測試通過，沒有提供輸出" or "Not verified: no test output was provided" — rather than presenting "tests pass" as established evidence.

FAIL if the body presents the passing tests as verified evidence (for example a checked "tests pass" item, or an After line stating the tests passed without saying it is unverified).

Do NOT fail because of the wording, language, or which section the statement is placed in.
