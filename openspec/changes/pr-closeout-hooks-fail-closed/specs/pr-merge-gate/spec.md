## Purpose

pr-closeout 的 merge gate 是一個 PreToolUse hook：`gh pr merge`、`gh api …/pulls/<n>/merge` 與 GitHub MCP 的 merge 工具執行前，先跑 `pr-closeout ready`，exit 0 才放行。本 spec 規定它無法做出判定時的行為。

## ADDED Requirements

### Requirement: 合併閘門失效時擋下
合併閘門無法做出判定時——逾時、以非 0 且非 2 的 exit code 結束、輸出無法解析——Claude Code MUST 擋下該合併，而不是放行；`hooks.json` 中合併閘門的每個 handler MUST 設定 `"onFailure": "block"`。合併閘門在 `/bin/bash` 3.2 與 UTF-8 locale 下 MUST 與 bash 5 做出相同判定：`pr-closeout ready` 不是 exit 0 時擋下，理由寫出 ready 的 exit code 與命中的條件；`--match-head-commit` 不是字面的 40 碼 sha 時擋下。

#### Scenario: bash 3.2 下 ready 不就緒照樣擋下
- **WHEN** hook 由 `/bin/bash` 3.2 在 `LC_ALL=en_US.UTF-8` 下執行，模型執行 `gh pr merge 7 --repo o/r --squash`，`pr-closeout ready` 以 exit 3（有未解決的 thread）結束
- **THEN** 合併閘門輸出 deny，理由含 `exit 3`

#### Scenario: bash 3.2 下非字面 sha 照樣擋下
- **WHEN** hook 由 `/bin/bash` 3.2 在 UTF-8 locale 下執行，模型執行 `gh pr merge 7 --repo o/r --squash --match-head-commit "$SHA"`
- **THEN** 合併閘門輸出 deny，理由說明 sha 必須是字面的 40 碼

#### Scenario: 逾時不放行
- **WHEN** 合併閘門執行超過 `hooks.json` 設定的逾時
- **THEN** 該合併被擋下
