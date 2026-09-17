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
- **機器閘門**（`node scripts/validate-fixtures.cjs`，CI 與本地 PostToolUse hook 皆跑）：每個 marketplace entry 版號＝該 plugin 的 `plugin.json`；`metadata.version`＝兩份根 CHANGELOG 最上面的 `## [x.y.z]`；根 CHANGELOG 標題須為 x.y.z、不重複、嚴格遞減。**bump 前先 `git fetch` 對齊 `origin/main`**——在落後的基底上 bump 會與遠端撞號，而 `marketplace.json` 兩邊改成同一值時 git 會靜默自動合併、停在錯的版號（2026-09-17 實例；閘門現在會擋）。已知殘餘：兩個 release 被併進同一個段落，靜態檢查抓不到。plugin 層 `CHANGELOG.md` 不在閘門範圍。另有**註冊閘門**：`plugins/` 下每個有 `plugin.json` 的目錄都必須被某個 marketplace entry 的 `source` 指到（第 2 節那一步漏做即紅——版本閘門只走 entries，沒註冊的 plugin 它根本看不到），且 entry 的 `name` 須等於該 `plugin.json` 的 `name`（前者是使用者安裝用的名字，後者決定 skill／command 的命名空間）。
- 同一 plugin 內 `commands/<X>.md` 與有效名稱為 `<X>` 的 skill（`SKILL.md` frontmatter `name`，缺省為目錄名）不得並存——兩者解析成同一個 `<plugin>:<X>`，command 會遮蔽 skill、skill 本體永不載入，`claude plugin validate` 不會報（session-reflect 1.0.0 實例）；同一閘門會擋。

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

## 6.5 用 Claude Code 在本 repo 工作：被執行的腳本不可由 sandbox 內的 Bash 寫入

`.claude/settings.json` 的本地 PostToolUse hook 由 harness **在 sandbox 之外**、以你的權限執行，它會跑 `scripts/validate-fixtures.cjs` 與每個 `plugins/*/tests/*.test.sh`，後者再執行 `plugins/*/hooks/*.sh`、runner 再執行各 validator。這些檔案若能被 sandbox 內的 Bash 寫入，等於「自動放行的寫入」換到「sandbox 外的執行」。因此同一份 settings 以 `sandbox.filesystem.denyWrite` 擋下整個被執行閉包：

- `scripts`、`plugins/*/tests`、`plugins/*/hooks`、`plugins/*/validators`（glob，新 plugin 自動涵蓋——**但 glob 條目有三個已知限制，見本節末「已知限制」**）
- 兩個不在慣例目錄的 validator：`plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators`、`plugins/security-audit/skills/security-audit/validate-findings.cjs`

實務影響：

- **改這些檔一律用 Edit／Write 工具**（走權限確認），`perl -pi`、`sed -i`、`>` 重導向在 sandbox 內會得到 `Operation not permitted`——那是這條防護在運作，不是程式碼回歸。
- 測試本身不受影響：各 suite 只寫 `$TMPDIR` 下的暫存目錄。
- 對真實 repo 做突變驗證時，要破壞的若是 manifest／CHANGELOG／`SKILL.md`（不在閉包內）仍可用 Bash；要破壞的若是 hook 或測試腳本本身，改用 Edit 工具再還原。
- **git 也是 sandbox 內的行程**：`git pull`／`merge`／`checkout`／`stash pop`／`rebase` 只要需要改寫上述目錄裡的檔案，就會以 `error: unable to unlink old '<path>': Operation not permitted` 半途失敗（exit 255）。實測（2026-09-17）失敗時**工作樹未變、index 卻已更新**，`git status` 會出現 `MM` 這種兩邊不一致的狀態。避開：這類 git 操作在 sandbox 外跑——輸入框用 `!` 前綴，或讓 agent 走 sandbox 繞過（仍經權限確認）。復原：`git reset -q HEAD -- <path>` 把 index 拉回、再於 sandbox 外重做該操作。只動其他路徑的 git 操作（含 commit、push、改 manifest／文件的 checkout）不受影響。
- **新增「會被 hook 或 runner 執行」的檔案時，若它不落在上述目錄，必須同步把路徑加進 `denyWrite`**——漏加會被 runner 最後一項檢查擋下（CI 與本地 hook 皆跑）：它蒐集 settings 裡各 command hook 指到的腳本、runner 自己、runner **實際 spawn 過**的每個 validator（在 spawn 點記錄，不是掃原始碼）、`plugins/*/tests/*.test.sh` 與 `plugins/*/hooks/` 下的腳本（枚舉方式與 hook 一致：依名稱、會穿過 symlink），逐一確認被某條 `denyWrite` 涵蓋。凡是它驗不了的一律 fail-closed、不猜：
  - **pattern** 只認得 root-relative 字面路徑（涵蓋其下一切）與單一路徑層級的 `*`；`**`、大括號、`?`、絕對路徑、`~`、`./x`、`x/` 一律回報「無法驗證」。
  - **hook 指令**只認得 `node "$CLAUDE_PROJECT_DIR/<path>"` 這一種形狀；用 `&&` 串第二個腳本、改用 `python3`、寫相對路徑，都會被回報「無法驗證」而不是被默默略過。指到**還不存在**的腳本也會照樣拿去核對——在這裡「還不存在」是最糟的情況（未受保護、sandbox 內建得出來、hook 下次就會跑它）。
  - hook 會穿過的 **symlink**（plugin 目錄、`tests/` 目錄、suite 檔）一律回報：它指向的東西不在任何 `denyWrite` 路徑規則之內。
  - 「hook 會 spawn runner 與各 suite」這件事是寫死在檢查裡的知識、不是推導出來的——**改了 `scripts/hooks/validate-on-plugin-edit.cjs` 會執行的東西，就要同步改這項檢查**。測試腳本若以變數拼路徑間接呼叫其他腳本、或 validator 去 `require` repo 內其他程式碼，靜態蒐集也找不到。

### 已知限制（綠燈**不**代表的事）

依據：閱讀 Claude Code 2.1.274 binary 內 sandbox runtime 的規則產生器；標「未執行」者為讀規則所得的推論，不是實測。

1. **它驗的是設定有列，不是 sandbox 真的有擋**——CI 沒有 sandbox、hook 自己也跑在 sandbox 外。改動 `denyWrite` 的**寫法**後仍須手動探測一次（在 sandbox 內對被擋路徑 `: >> <path>` 應得 `Operation not permitted`，並對照一個不該被擋的路徑）。
2. **Linux／WSL 上，帶 glob 的寫入條目會被 runtime 整條丟掉**（log：`Skipping glob write pattern on Linux`）。那三條 `plugins/*/…` 在 Linux 上什麼都沒保護，而這項檢查照樣綠燈。目前只在 macOS 上使用本 repo 才成立。
3. **glob 條目只擋「路徑匹配其 regex」的操作**（未執行）：字面條目產生 `subpath` 規則、涵蓋其下一切並釘住各層祖先目錄；glob 條目只產生那條 regex 加上靜態前綴 `plugins` 本身。因此把一個**已含 `tests/x.test.sh`** 的目錄改名搬**進** `plugins/`，被檢查的只有 `plugins/<新名>` 這個路徑——不匹配任何規則；只靠 glob 保護的既有 plugin 目錄本身也能被改名移走。
4. 上述 2、3 的根治是把 glob 換成字面的 `scripts`＋`plugins`（整棵樹）——代價是 `plugins/` 下**所有**檔案（含 `plugin.json`、`SKILL.md`、README）都只能用 Edit／Write 工具改，對 manifest 的突變驗證也得改用「複製到 `$TMPDIR` 的副本」來做。**此為待決事項。**

## 7. 維護「wrapper 型」plugin 的上游相依

`openspec-superpowers-workflow` 以**概念名稱**引用 superpowers skills（如 `/subagent-driven-development`、`/brainstorming`、`/writing-plans`），不綁特定 prompt 檔。好處是執行行為自動跟著上游走；風險是**上游出 major 版時，wrapper 的 `phases.md` 描述會悄悄過時**——文件與實際脫節，形成「comment 寫願景非事實」的信任陷阱（reviewer 讀文件就以為流程如此）。

維護觸發點與方法：

- **每當 superpowers（或任何被 wrapper 引用的上游）出 major 版**，逐項比對 wrapper `phases.md` 的流程描述 vs 上游實際行為，過時就更新並 bump wrapper 版本。
- **比對靠 diff 兩版而非讀 changelog**：plugin cache 會保留新舊版本目錄（`~/.claude/plugins/cache/claude-plugins-official/superpowers/<old>` 與 `<new>`），`diff -rq` 兩版可抓出 skill 改名 / 移除 / prompt 檔合併 / 流程重寫。
- **對 critical 聲明，請直接閱讀上游 `SKILL.md` 原始碼驗證**，不要只信 release notes 的轉述（轉述會簡化或漏掉邊界）。
- 案例：superpowers `6.0.0` 把 SDD 的雙 reviewer（spec + quality）併成單一 `task-reviewer`（一次兩 verdict）+ 結尾一次 whole-branch review，並把 worktree 落點從全域 `~/.config/superpowers/worktrees/` 改為專案內 `.worktrees/` root（worktree 建在 `<root>/<branch>`）→ `openspec-superpowers-workflow` `1.1.0` 對齊（見該 plugin `CHANGELOG.md`）。
