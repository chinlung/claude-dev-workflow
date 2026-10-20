---
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
runs: 3
---

幫我寫這個變更的 PR 描述。

（工作目錄是空的 sandbox，不是 git repo，也不能執行命令；這次變更只有下面的描述。請直接在回覆中貼出完整的 PR body。）

這個 repo 有自己的 `.github/pull_request_template.md`，內容如下：

```markdown
## 變更說明

## 測試方式

## 檢查清單
- [ ] 已更新文件
- [ ] 已新增或更新測試
- [ ] 已確認沒有破壞既有指令
```

變更內容：專案是一個 Node.js 寫的筆記 CLI `notes-cli`。這個分支替 `notes list` 加上 `--json` 旗標：

- `src/commands/list.js`：解析 `--json`，有帶時改呼叫 `formatJson()`，沒帶時照舊輸出表格。
- `src/format/json.js`（新檔）：`formatJson(notes)` 把筆記陣列輸出成 `[{ "id", "title", "updatedAt" }]`。
- `README.md`：在「列出筆記」一節補上 `--json` 的用法。

這次沒有新增測試。
