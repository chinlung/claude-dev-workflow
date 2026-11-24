# pr-watch Implementation Plan

> **For agentic workers:** 依 `openspec-superpowers-workflow` Phase 4 執行：superpowers:executing-plans。Task 2–5 改同一個模組、線性相依；Task 6、7 獨立，但檔案少，一樣 inline 做。每個 `### Task N` 完成時把它唯一的勾選框改成 `[x]`。

**Goal:** `pr-closeout` 加上 `watch`／`watch-ack`、防護 hook 與 `pr-watch` skill；code-audit-rigor 的 `/review-pr` 加上只分類模式。

**Architecture:** `pr-closeout.mjs` 共用 `fetchAll()`／`assess()`，`watch` 擁有以 PR 為單位的狀態檔，算出每一輪的事實與停止原因（`STOP_REASONS`）。skill 只依 `watch` 的 JSON 動作；對外動作由 `pr-watch-guard.sh` 在監看期間擋下。

**Tech Stack:** Node（零相依 ESM）、bash 測試（既有的 `bounded`／`fixture`／`jqeq`／mutant runner）。

**Spec:** `openspec/changes/pr-watch/design.md`（權威）、`specs/pr-watch/spec.md`、`proposal.md`

## Global Constraints
- 腳本零相依；GitHub 查詢只經既有的 `gh api` → curl 退路。
- `ready` 的欄位與 exit code 不變，唯一例外：留言 100–1000 則時不再回 exit 7（分頁）。
- `watch` 的 exit：0 繼續、8 停止、7 用法錯誤或無法判斷。
- 狀態檔：`<repo-dir>/.claude/pr-watch.<pr>.local.json`，version 1，只有 `watch` 和 `watch-ack` 會寫，寫法是暫存檔加 rename。
- 留言 key：`<endpoint>:<id>:<sha256(body) 前 16 碼>`。
- `STOP_REASONS = ['not-open','fork','head-not-allowed','query-failed','limit','ready','needs-user','no-progress']`，依此順序判斷，只定義這一份。
- 上限：24 小時或 60 輪；查詢連續失敗 3 次停止；兩次檢查間隔至少 30 秒；寬限期一輪。
- 版號：pr-closeout 1.1.2 → 1.2.0；code-audit-rigor 2.3.0 → 2.4.0；marketplace 1.22.1 → 1.23.0。
- commit 不加 session 連結；staging 一律具名。

## Review Focus
1. 重新啟動：上一段停在 `limit` 或 `needs-user`，`--start` 後第 1 輪不得停止。Task 4 有案例。
2. 剛 push 就啟動，rollup 為 null：第 1 輪不得判定 `ready`。Task 4 有案例。
3. 使用者從本機 push 了 pr-watch 的修正：不得停在 `head-not-allowed`。Task 5 有案例。
4. 本機已修好 CI、還沒 push：停止原因是 `needs-user`，不得是 `no-progress`，也不得重修。Task 4 有案例。
5. 留言跨過 100 則：`ready` 和 `watch` 都要讀完。Task 2 有案例。

---

## 1. ready 補欄位

### Task 1: `ready` 輸出留言清單與 cross-repo 旗標
- [x] 1.1 `extras().comments.items[]` 與 `isCrossRepository` 進 `ready` 輸出，現有案例全綠
已完成（commit b1fd88e）。`items[].updatedAt` 仍保留作為資訊；`watch` 的 key 改用內文雜湊（Task 4），所以每個 item 要另外加上 `bodyHash`，在 Task 2 處理。

## 2. 查詢層

### Task 2: 留言分頁、`bodyHash`、`detailsUrl`
- [x] 2.1 留言端點分頁到 10 頁；`items[].bodyHash`；CheckRun 帶 `detailsUrl`
**Files：** 修改 `plugins/pr-closeout/scripts/pr-closeout.mjs` 的 `fetchAll`、`readFixture`、`GQL`、`extras`、`assess` 的 `checks` 映射；測試加在 `tests/pr-closeout.test.sh` 新節 `# ── pr-watch Task 2`。
**Interfaces：**
- 產出 `restAll(apiPath: string, what: string): any[]`：逐頁抓取，`&page=1..10`，某一頁少於 100 則就停；超過 10 頁 throw `QueryError`。
- fixture 模式下，`<name>.json` 是第 1 頁，`<name>.2.json` 是第 2 頁，依此類推。
- `items[].bodyHash: string`，是 `sha256(body ?? '')` 的十六進位前 16 碼。
- `checks[].detailsUrl: string|null`。

**步驟：**
1. 寫失敗測試：
   - (a) fixture 的 `pulls-comments.json` 放 100 則、`pulls-comments.2.json` 放 1 則：`ready` exit 0，`.comments.pullsComments == 101`。
   - (b) 10 頁都滿：exit 7。
   - (c) `bodyHash` 長度 16，兩則內文相同時雜湊相同。
   - (d) 給 CheckRun 一個 `detailsUrl`：`.checks[0].detailsUrl` 回出相同的值。
   - 原本的「100 則就 exit 7」案例，如果有的話，改寫成 (b)。
2. 跑 `env NO_MUTANTS=1 bash plugins/pr-closeout/tests/pr-closeout.test.sh`，預期這些案例 FAIL。
3. 實作。
4. 全套 PASS。`pr-merge-gate.test.sh` 也要 PASS。
5. commit（具名）。

## 3. watch

### Task 3: 狀態檔、`--start`、`watch-ack`
- [x] 3.1 `loadState`／`startState`／`saveState` 與 `watch-ack`；壞檔、`too-soon`、`not-started` 都回 exit 7 且檔案不動
**Files：** 修改 `pr-closeout.mjs`（`parseArgs` 接受 `watch`、`watch-ack`、`--start`、`--now`、`--comment`；新增狀態函式並 export）；測試新節 `# ── pr-watch Task 3`。
**Interfaces：**
- 產出 `statePath(repoDir, pr)`。
- `loadState(file, pr): State|null`：檔案不存在回 null；壞 JSON、`version !== 1`、`pr` 不符一律 throw `QueryError`。
- `startState(prev: State|null, pr, now): State`：保留 `prev.seen`，其他欄位重設。
- `saveState(file, s)`：寫 `<file>.tmp.<pid>` 再 `renameSync`；`.claude/` 不存在就建立。
- `State` 的欄位照 design.md「組成 2」的表格。
- CLI：`watch-ack --repo-dir <p> --pr <n> --comment <key>...`。

**步驟：**
1. 寫失敗測試（`--repo-dir` 指向暫存目錄）：
   - 狀態檔不存在時跑 `watch-ack`：exit 7。
   - ack 兩個 key，其中一個重複：`seen` 去重。
   - 壞 JSON、`version: 2`、`pr` 不符：exit 7，檔案位元組不變（`cmp`）。
   - `startState` 保留 `seen`、`round` 歸零：透過 `watch --start` 驗證，所以這一條要等 Task 5 才會轉綠；這裡先用 `node -e` 直接 import 測。
2. 跑全套，預期 FAIL。
3. 實作。
4. 跑全套，PASS。
5. commit（具名）。

### Task 4: `watchVerdict` 純函式、停止判定與突變
- [x] 3.2 `watchVerdict` 依 design 的步驟 5–7 算出 `watch{}` 與停止原因，每個原因兩個觸發輸入，突變全部被殺死
**Files：** 修改 `pr-closeout.mjs`（export `STOP_REASONS`、`watchVerdict`）；測試新節 `# ── pr-watch Task 4`。用 `node --input-type=module -e` import 函式，餵 JSON 情境。
**Interfaces：**
- 輸入：`watchVerdict(verdict: ReadyVerdict|null, queryError: string|null, state: State, local: {head, branch, headKnown, headAllowed, unpushed, dirty}, extra: {runAttempts: Record<runId, number>}, now: Date)`。
- 回傳 `{state: State, watch: Watch, exit: 0|8}`。
- 這個函式不做 I/O；git 與 REST 的事實由 Task 5 準備好再傳入。

**步驟：**
1. 寫失敗測試，每列至少兩個觸發輸入：
   - `not-open`：MERGED；CLOSED。
   - `fork`：`isCrossRepository` 為 true（CI 綠、CI 紅各一）；欄位缺漏時算查詢失敗。
   - `head-not-allowed`：`headKnown` 為 false；`headKnown` 為 true 但 `headAllowed` 為 false。
   - `query-failed`：連續第 3 次；第 1、2 次反而 exit 0、`queryFailed` 為 true。
   - `limit`：`startedAt` 是 25 小時前；`round` 是 60。
   - `ready`：寬限期之後的 base 情境；加一則已在 `seen` 裡的留言。
   - `needs-user`：寬限期之後只剩未解決的 thread；`unpushed` 為 1 而遠端 CI 紅（Review Focus 4）。
   - `no-progress`：settled 且 checks-failed，連跑兩輪簽章相同；換一個不同的失敗 check 再跑一次。
   - 反例：rollup 為 null 的第 1 輪（Review Focus 2）；第 1 輪的 base 情境（寬限期）；pending 連續 5 輪；只剩 thread 但有新留言；缺必跑 check 的 checks-failed 算還沒跑完；`limit` 或 `needs-user` 停止後 `startState` 加第 1 輪（Review Focus 1）；review 內文改了（雜湊不同所以是新留言）；空 body 的 review 不算新留言；id 為 null 算查詢失敗。
2. 跑全套，預期 FAIL。
3. 實作，照 design.md「組成 2」的步驟 5–7。
4. 加突變，每個突變必須被指定的案例殺死：
   - 停止原因順序：把 `ready` 排到 `limit` 前面，由 `limit` 案例殺死。
   - pending 輪也累計沒有進展，由 pending 連續 5 輪的案例殺死。
   - 拿掉寬限期，由第 1 輪 base 情境的案例殺死。
   - 拿掉 `staleRemote`，由 Review Focus 4 的案例殺死。
   - key 改用 id，由 review 被編輯的案例殺死。
   - 查詢失敗門檻改成 1，由第 1 次查詢失敗的案例殺死。
   - 拿掉「缺必跑 check 算還沒跑完」，由對應的案例殺死。
5. 跑全套（含突變），全部 PASS 或 killed。
6. commit（具名）。

### Task 5: `watch` CLI 與本機 git 事實
- [ ] 3.3 `watch` 從 CLI 端到端跑通：bare remote fixture、`wrong-branch`、祖先判斷、`unpushed`、`dirty`、`run_attempt`、`stateIgnored`
**Files：** 修改 `pr-closeout.mjs`（`main` 的 `watch` 分支、`localFacts(repoDir, verdict)`、`runAttempts(owner, repo, checks)`，fixture 模式讀 `runs.json`）；測試新節 `# ── pr-watch Task 5`（`mktemp -d` 建 repo 加 bare remote，分支名與 fixture 的 `headRefName` 相同；fixture 的 `headRefOid` 用 jq 改成本機 commit 的 SHA）。
**Interfaces：**
- 使用 Task 3 的狀態函式與 Task 4 的 `watchVerdict`。
- 產出 CLI：`watch <owner/repo> <pr> --repo-dir <p> [--start] [--fixture <d>] [--now <iso>]`。

**步驟：**
1. 寫失敗測試：
   - 沒有 `--start` 也沒有狀態檔：exit 7。
   - `--start` 建立狀態檔，第 1 輪 exit 0。
   - 本機在別的分支：exit 7，detail 含 `wrong-branch`，不寫檔。
   - PR head 等於本機 HEAD，之後再 commit 一次：`unpushed` 為 1，`headAllowed` 為 true（Review Focus 3）。
   - PR head 是本機沒有的 SHA：`head-not-allowed`。
   - 未 commit 的修改：`dirty` 為 true。
   - `runs.json` 給 attempt 2：`failedRuns[0].attempt` 為 2。
   - `.claude/` 被忽略或沒被忽略：`stateIgnored` 分別為 true 和 false。
   - 間隔 10 秒再跑一次：`too-soon`。
2. 跑全套，預期 FAIL。
3. 實作。
4. 跑全套，PASS。
5. commit（具名）。

## 4. 防護與只分類

### Task 6: 防護 hook `pr-watch-guard.sh`
- [ ] 4.1 監看期間擋下對外動作，沒有在監看時立即放行
**Files：** 新增 `plugins/pr-closeout/hooks/pr-watch-guard.sh`、`plugins/pr-closeout/tests/pr-watch-guard.test.sh`；修改 `hooks/hooks.json`（Bash matcher 加第二個 hook，另加 MCP matcher）。
**步驟：**
1. 寫失敗測試（`CLAUDE_PROJECT_DIR` 指向暫存目錄，stdin 餵 PreToolUse 的 JSON）：
   - 沒有狀態檔時，`gh pr comment 1 -b x` 放行。
   - `active` 為 true 時，以下每一個都被擋下：`resolveReviewThread`、`gh pr comment`、`gh pr review`、`gh issue comment`、`/replies`、`addPullRequestReview`、`minimizeComment`，以及 MCP 工具名稱 `mcp__github__add_issue_comment`。
   - `active` 為 true 時，`git status` 放行。
   - `active` 為 false 時，`gh pr comment` 放行。
   - 擋下時輸出 `permissionDecision: "deny"`，原因寫明怎麼停止監看。
2. 跑 `bash plugins/pr-closeout/tests/pr-watch-guard.test.sh`，預期 FAIL。
3. 實作。沒有任何 `pr-watch.*.local.json` 時，第一個判斷就用 shell glob 放行，不啟動 jq。
4. 跑 guard、merge-gate、pr-closeout 三套，全部 PASS。
5. commit（具名）。

### Task 7: `/review-pr --triage-only`
- [ ] 4.2 只分類模式寫進 review-pr.md，docs 測試把關
**Files：** 修改 `plugins/code-audit-rigor/commands/review-pr.md`；新增 `plugins/code-audit-rigor/tests/review-pr-triage.test.sh`。
**步驟：**
1. 寫失敗測試：
   - `argument-hint` 含 `--triage-only`。
   - 有「只分類模式」一節，寫明只保留清單裡的 id、跑完 Phase 2 就結束。
   - `## Phase 3` 和 `## Phase 4` 下一行都含「只分類模式到此為止」。
2. 跑測試，預期 FAIL。
3. 改 review-pr.md。
4. 跑 code-audit-rigor 所有 `tests/*.test.sh`，PASS。
5. commit（具名）。

## 5. skill 與文件

### Task 8: `pr-watch` SKILL.md 與 docs 測試
- [ ] 5.1 SKILL.md 寫好，停止原因與 `STOP_REASONS` 雙向一致，禁止動作只出現在「不做」那一節
**Files：** 新增 `plugins/pr-closeout/skills/pr-watch/SKILL.md`、`plugins/pr-closeout/tests/pr-watch-docs.test.sh`。
**步驟：**
1. 寫失敗的 docs 測試：
   - 用 `node -e` import `STOP_REASONS`，和 SKILL.md 裡的停止原因雙向比對。
   - `gh pr merge`、`resolveReviewThread`、`gh pr comment`、`/replies`、`git push --delete` 只能出現在 `## 不做` 之後。
   - frontmatter 有 `name: pr-watch`，description 含「盯 PR」。
   - 含 `--triage-only` 和 `watch-ack`。
2. 跑測試，預期 FAIL。
3. 寫 SKILL.md，照 design.md「組成 5」，包括檢查間隔、通知的退路，以及 sandbox 內 rerun 的退路。
4. 跑測試，PASS。
5. commit（具名）。

### Task 9: 周邊文件與版號
- [ ] 5.2 README、CHANGELOG、設計文件註記、版號同步，全 repo 測試綠
**Files：**
- pr-closeout：SKILL.md 的 exit 5 那一列、`README.md`、`README.zh-TW.md`、`CHANGELOG.md`、`plugin.json`
- code-audit-rigor：`README.md`、`CHANGELOG.md`、`plugin.json`
- 共用：`.claude-plugin/marketplace.json`、根目錄的兩份 CHANGELOG、`docs/pr-closeout-skill-design-2026-11-09.md`

**步驟：**
1. 改上列文件。
2. 改版號（見 Global Constraints）。用 `grep -rn '"1\.1\.2"\|"2\.3\.0"\|"1\.22\.1"' plugins/pr-closeout plugins/code-audit-rigor .claude-plugin` 確認沒有漏改的舊版號。
3. `git diff --stat` 讀回改到的檔，和本 Task 的 Files 逐項比對。
4. 跑 `node scripts/validate-fixtures.cjs`，再跑 `for s in plugins/*/tests/*.test.sh; do bash "$s" > "$TMPDIR/s.log" 2>&1 || echo "FAIL $s"; done`，結果不得有任何 FAIL。
5. commit（具名）。

### Task 10: 沙盒 PR 實測
- [ ] 5.3 在 private 沙盒 PR 上跑完一段完整流程，結果寫進 review-notes
**步驟：**
1. 建 private 沙盒 repo：一個 Python 檔加一個會失敗的測試 workflow，開 PR，用 workflow_dispatch 讓 `github-actions[bot]` 留一則 inline 留言。
2. 在沙盒 repo 用本分支的 plugin 啟動 pr-watch，依序觀察：
   - 寬限期
   - CI 失敗被分類
   - bot 留言送去只分類模式
   - 停止原因與停止報告
   - 本機修正、push、`--start` 重新啟動
   - 監看期間防護 hook 擋下一次 `gh pr comment`
3. 讀回 GitHub 的狀態：thread 是否仍未解決、PR 上有沒有新留言。把觀察寫進 `review-notes.md`，Round 1 標為 Sandbox。
4. 刪除沙盒 repo（使用者確認後）。
