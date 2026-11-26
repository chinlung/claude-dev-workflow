## ADDED Requirements

### Requirement: 防護 hook 失效時擋下
防護 hook 無法做出判定時——逾時、以非 0 且非 2 的 exit code 結束、輸出無法解析——Claude Code MUST 擋下該工具呼叫，而不是放行；`hooks.json` 中防護 hook 的每個 handler MUST 設定 `"onFailure": "block"`。防護 hook 在 `/bin/bash` 3.2 與 UTF-8 locale 下 MUST 與 bash 5 做出相同判定，不得因 shell 版本而在該擋下時結束。沒有 PR 正在監看時，防護 hook MUST 以 exit 0 結束、不輸出判定。

#### Scenario: bash 3.2 下照樣擋下
- **WHEN** 有 PR 正在監看，hook 由 `/bin/bash` 3.2 在 `LC_ALL=en_US.UTF-8` 下執行，模型執行 `gh pr comment 7 -b done`
- **THEN** 防護 hook 輸出 deny 並以 exit 0 結束，理由寫出狀態檔的路徑

#### Scenario: 逾時不放行
- **WHEN** 有 PR 正在監看，防護 hook 執行超過 `hooks.json` 設定的逾時
- **THEN** 該工具呼叫被擋下

#### Scenario: 沒有監看時不擋
- **WHEN** 專案沒有 `active` 為 true 的監看狀態檔，hook 由 `/bin/bash` 3.2 在 UTF-8 locale 下執行，且環境沒有 `CLAUDE_PROJECT_DIR`
- **THEN** 防護 hook 以 exit 0 結束，不輸出判定
