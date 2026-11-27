# Proposal: pr-closeout-hooks-fail-closed

## Why

pr-closeout 有兩個負責擋動作的 PreToolUse hook：`pr-merge-gate`（`pr-closeout ready` exit 0 才放行 merge）與 `pr-watch-guard`（PR 監看中擋下對 GitHub 的寫入）。兩個 hook 失效時都會放行：

- Claude Code 在 command hook 逾時、或 exit code 不是 0 也不是 2 時，照樣執行工具呼叫（https://code.claude.com/docs/en/hooks：「a timed-out `command` … hook doesn't block the tool call」；「Exit code 1 without valid JSON output is a non-blocking error」）。
- `hooks.json` 以 `bash "<路徑>"` 執行兩個 hook，用的是 PATH 上第一個 `bash`，一般 macOS 就是 `/bin/bash` 3.2。3.2 在 UTF-8 locale 下會把緊接在變數名後的全形字元（`$active）`、`$sha」`、`$rc）`）讀成變數名的一部分，`set -u` 便在 hook 正要擋下的那一刻以 exit 1 結束。2026-11-27 量測：以 `/bin/bash` 3.2、`LC_ALL=en_US.UTF-8` 跑，guard 套件 126 條只過 34 條、merge gate 套件 243 條只過 230 條；所有沒擋成的案例都是 exit 1 放行。`ready` 說 PR 有未解決的 thread 或 head 不符時，merge gate 照樣放行合併。
- `gh api … -f body=<200 KB>` 讓 guard 超過 10 秒逾時（PR #76 的 follow-up），一樣放行。

CI 跑在 ubuntu 的 bash 5 上，以上都看不到。

## What Changes

- 兩個 hook 在 bash 3.2、UTF-8 locale 下行為正確：兩份套件在 `/bin/bash` 3.2 下揭露的崩潰全部修掉（`${var}` 那一型，以及其餘 allow 路徑上的失敗）。
- `plugins/pr-closeout/hooks/hooks.json` 裡這兩個 hook 的每個 handler 都加 `"onFailure": "block"`：逾時、崩潰或輸出讀不懂時擋下，不再放行。
- CI 加一個 job：從 GNU 原始碼編 bash 3.2.57，通過金絲雀（確認 PATH 上是 3.2）後用它跑 guard 與 merge gate 兩份套件；`$name` 後接全形字元那一型只在 macOS 重現，由兩份套件各加的 lint 在每個平台擋。
- pr-closeout 1.2.1 → 1.3.0、marketplace 1.23.1 → 1.24.0；README 與 CHANGELOG 寫明 hook 失效時現在的行為與脫困方式。

## Capabilities

### New Capabilities
- `pr-merge-gate`：merge gate 無法做出判定時（崩潰、逾時、舊版 shell）的行為。

### Modified Capabilities
- `pr-watch`：新增「防護 hook 失效時擋下」一條需求，既有需求不變。

## Impact

- `plugins/pr-closeout/hooks/pr-merge-gate.sh`、`plugins/pr-closeout/hooks/pr-watch-guard.sh`、`plugins/pr-closeout/hooks/hooks.json`
- `plugins/pr-closeout/tests/pr-merge-gate.test.sh`、`plugins/pr-closeout/tests/pr-watch-guard.test.sh`
- `.github/workflows/validate.yml`
- `plugins/pr-closeout/.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、`plugins/pr-closeout/CHANGELOG.md`、`CHANGELOG.md`、`CHANGELOG.zh-TW.md`、`plugins/pr-closeout/README.md`、`plugins/pr-closeout/README.zh-TW.md`

## Decisions

- 兩個 hook 都加 `onFailure: "block"`，不只 merge gate——使用者 2026-11-27 裁定（方案 B）：放行一次不該合的 merge，代價遠大於多擋一次 Bash。
- CI 從 GNU 原始碼編 bash 3.2.57，不只靠靜態檢查——使用者 2026-11-27 裁定；金絲雀驗 PATH 上真的是 3.2（空陣列在 `set -u` 下報錯、`$'…'` 不在雙引號 `${…}` 內展開），`$name` 後接全形字元那一型 glibc 不重現，由兩份套件的 lint 擋。編好的 bash 以快取保存，key 帶手動遞增的 recipe 標記。
- 200 KB 逾時不另設長度上限：有 `onFailure: "block"` 後逾時就是擋下，方向正確。
- 早於 v2.1.295 的 Claude Code 會忽略 `onFailure`，仍舊放行；README 寫明最低版本，hook 不自行偵測。
- hook 壞掉、擋住所有 Bash 時的脫困方式：停用 plugin（`/plugin disable pr-closeout`）再回報；README 寫明。`PR_CLOSEOUT_OK=1` 只在 hook 能正常執行時有效。
- 版本走 minor（1.3.0）：hook 失效時由放行改為擋下，是使用者會察覺的行為變更。
