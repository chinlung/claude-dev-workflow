---
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
runs: 3
---

幫我寫這個修正的 PR 描述。

（工作目錄是空的 sandbox，不是 git repo，也不能執行命令；這次變更只有下面的描述。請直接在回覆中貼出完整的 PR body。）

專案是一個 Node.js 寫的筆記 CLI `notes-cli`。`notes export` 在沒有任何筆記時會丟出 `TypeError: Cannot read properties of undefined (reading 'map')`。這個分支在 `src/commands/export.js` 開頭加上空陣列判斷，沒有筆記時輸出 `[]` 並以 exit code 0 結束；另外在 `test/export.test.js` 加了一個測試 `exports empty list`。

我本機跑過了，修好之後測試都過了。
