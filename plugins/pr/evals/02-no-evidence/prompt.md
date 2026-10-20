---
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
runs: 3
---

幫我寫這個變更的 PR 描述。

（工作目錄是空的 sandbox，不是 git repo，也不能執行命令；這次變更只有下面的描述。請直接在回覆中貼出完整的 PR body。）

專案是一個 Node.js 寫的筆記 CLI `notes-cli`。這個分支替 `notes list` 加上 `--json` 旗標：

- `src/commands/list.js`：解析 `--json`，有帶時改呼叫 `formatJson()`，沒帶時照舊輸出表格。
- `src/format/json.js`（新檔）：`formatJson(notes)` 把筆記陣列輸出成 `[{ "id", "title", "updatedAt" }]`，`updatedAt` 用 ISO 8601。
- `test/list.test.js`（新檔）：兩個測試，分別檢查有帶與沒帶 `--json` 的輸出。
- `README.md`：在「列出筆記」一節補上 `--json` 的用法。

沒有改到其他指令，也沒有改設定檔格式。
