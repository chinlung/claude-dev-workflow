# Contributing — 新增一個 plugin 到本 marketplace

本 repo 是一個 Claude Code plugin marketplace（`scl-claude-plugins`）。以下是新增一個 plugin 的可重複 checklist，依實際發佈流程整理。

> 通用的「怎麼寫 skill / plugin」請用官方 `plugin-dev:*`、`superpowers:writing-skills` skills。本檔只記**本 repo 特有的慣例**（目錄結構、marketplace 註冊、版本與雙語文件同步）。

## 1. 建 plugin 目錄（對齊既有 plugin 結構）

以 `plugins/code-audit-rigor/` 為範本。最小結構：

```
plugins/<name>/
  .claude-plugin/plugin.json     # 必須
  skills/<name>/SKILL.md         # skill-based plugin
  skills/<name>/reference.md     # 選用：progressive disclosure（重內容下放）
  README.md                      # plugin 自己的說明
  CHANGELOG.md                   # plugin 自己的變更日誌
  .mcp.json                      # 選用：夾帶 MCP server（見第 5 節）
```

`plugin.json` 欄位（照既有 plugin）：`name`、`version`、`description`、`author`、`license`、`repository`、`homepage`、`keywords`。

> **SKILL.md frontmatter description ≤ 1536 字元**：Claude Code 送進 skill 清單的 per-skill description 有字元上限（預設 1536，超過**靜默截斷尾端**）——auto-trigger 條款寫在 description 裡的 plugin（如 openspec-superpowers-workflow）超標會讓尾端條款直接消失。編修後用 `python3 -c "import re;print(len(re.search(r'^description: (.*)$',open('<SKILL.md>').read(),re.M).group(1)))"` 量一次。

## 2. 註冊進 marketplace

編輯 `.claude-plugin/marketplace.json`：
- `plugins` 陣列尾端加一筆：`name` / `source`（`./plugins/<name>`）/ `description`（中文）/ `version` / `keywords`
- bump `metadata.version`（見第 4 節）

## 3. 雙語文件同步（**最容易漏**）

本 repo 所有頂層文件都有 `.md`（英）+ `.zh-TW.md`（繁中）兩份，**兩邊都要改**：
- `README.md` + `README.zh-TW.md`：
  - 頂部 Available Plugins 表格加一列
  - 檔尾加一個 `# <Name> Plugin` 明細段（對齊既有段落格式）
- `CHANGELOG.md` + `CHANGELOG.zh-TW.md`：在 preamble 之後、最新版本之前插入新版段落

## 4. 版本規則（語意化版本）

- **plugin 自己的版本**（`plugin.json` + `marketplace.json` 該 entry + plugin `CHANGELOG.md`）：新 plugin 從 `1.0.0`；既有 plugin 內容變更走 patch / minor。
- **marketplace `metadata.version`**：
  - 新增一個 plugin → **minor** bump（例：1.6.1 → 1.7.0）
  - 既有 plugin patch → **patch** bump（例：1.6.0 → 1.6.1）
- 全域紀律：動到版本號時，**檢查所有含版本字串的檔案**（plugin.json、marketplace.json entry、兩份 CHANGELOG），不要只改一處。

## 5.（選用）夾帶 MCP server

若 plugin 要提供 MCP 工具（讓使用者裝一次處處可用，不必逐專案 `mcp` 設定）：

- 在 plugin 根建 `.mcp.json`（`mcpServers`-wrapped，與專案 `.mcp.json` 同格式）：
  ```json
  { "mcpServers": { "<server>": { "type": "stdio", "command": "<cmd>", "args": ["..."] } } }
  ```
  - 命令在 PATH 上的全域 CLI → 直接寫命令名；打包進 plugin 的 server → 用 `${CLAUDE_PLUGIN_ROOT}/...`。
- **工具名前綴會變成 `mcp__plugin_<plugin-name>_<server-name>__<tool>`**（不是 `mcp__<server>__<tool>`）。文件與 allowlist 範例要用這個前綴。
- allowlist 放使用者**全域** `~/.claude/settings.json`（plugin 提供的工具是全域的）；只放唯讀工具，避免 agent 跑到破壞性命令。
- 取捨：夾帶的 MCP server 會在每個啟用 plugin 的專案啟動，未初始化的專案會回 not-initialized（graceful，但多一個 process）——在 plugin README 講清楚。

## 6. 發佈前驗證

```bash
# JSON 合法性
python3 -c "import json; json.load(open('.claude-plugin/marketplace.json'))"
python3 -c "import json; json.load(open('plugins/<name>/.claude-plugin/plugin.json'))"

# 殘留舊版本字串（應只剩 CHANGELOG 歷史條目）
grep -rn "<old-marketplace-version>" --include="*.json" --include="*.md" . | grep -v CHANGELOG

# 結構
find plugins/<name> -type f | sort
```

裝起來實測：`/plugin marketplace add ...`（或 update）→ `/plugin install <name>@scl-claude-plugins` → `/reload-plugins` → 確認 skill 出現在清單、（若有）MCP 工具以 `mcp__plugin_<name>_<server>__*` 出現。

## 7. 維護「wrapper 型」plugin 的上游相依

`openspec-superpowers-workflow` 以**概念名稱**引用 superpowers skills（如 `/subagent-driven-development`、`/brainstorming`、`/writing-plans`），不綁特定 prompt 檔。好處是執行行為自動跟著上游走；風險是**上游出 major 版時，wrapper 的 `phases.md` 描述會悄悄過時**——文件與實際脫節，形成「comment 寫願景非事實」的信任陷阱（reviewer 讀文件就以為流程如此）。

維護觸發點與方法：

- **每當 superpowers（或任何被 wrapper 引用的上游）出 major 版**，逐項比對 wrapper `phases.md` 的流程描述 vs 上游實際行為，過時就更新並 bump wrapper 版本。
- **比對靠 diff 兩版而非讀 changelog**：plugin cache 會保留新舊版本目錄（`~/.claude/plugins/cache/claude-plugins-official/superpowers/<old>` 與 `<new>`），`diff -rq` 兩版可抓出 skill 改名 / 移除 / prompt 檔合併 / 流程重寫。
- **對 critical 聲明，請直接閱讀上游 `SKILL.md` 原始碼驗證**，不要只信 release notes 的轉述（轉述會簡化或漏掉邊界）。
- 案例：superpowers `6.0.0` 把 SDD 的雙 reviewer（spec + quality）併成單一 `task-reviewer`（一次兩 verdict）+ 結尾一次 whole-branch review，並把 worktree 落點從全域 `~/.config/superpowers/worktrees/` 改為專案內 `.worktrees/` root（worktree 建在 `<root>/<branch>`）→ `openspec-superpowers-workflow` `1.1.0` 對齊（見該 plugin `CHANGELOG.md`）。
