---
max_turns: 6
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep, Skill]
runs: 3
---

幫我替這個變更寫一則 git commit message：一行標題，加兩三行內文就好。

（工作目錄是空的 sandbox，不是 git repo，也不能執行命令；這次變更只有下面的描述。請直接在回覆中貼出 commit message。）

專案是一個 Node.js 寫的筆記 CLI `notes-cli`。這次替 `notes list` 加上 `--json` 旗標：`src/commands/list.js` 解析旗標，新檔 `src/format/json.js` 負責輸出 JSON，`README.md` 補上用法。
