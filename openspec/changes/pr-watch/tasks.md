# pr-watch Implementation Plan

> **For agentic workers:** 依 `openspec-superpowers-workflow` Phase 4 執行：superpowers:executing-plans（本計畫的 Task 2→3→4 共用同一個模組、線性相依，不適合 SDD）。每個 `### Task N` 完成時把它唯一的勾選框改成 `[x]`。

**Goal:** 在 `pr-closeout` plugin 加上 `watch`／`watch-ack` 子命令與 `pr-watch` skill：每一輪的事實與停止判定由腳本算，skill 只做動作。

**Architecture:** `pr-closeout.mjs` 共用既有的 `fetchAll()`／`assess()`，新增一個擁有狀態檔的 `watch` 判定（新留言、允許的 head、是否跑完、進度簽章、停止條件），`watch-ack` 只寫入已看過的留言與允許的 head。`skills/pr-watch/SKILL.md` 用內建 `/loop` 驅動 `watch`，依 `watch.stop` 與 `hits[]` 採取動作。

**Tech Stack:** Node（零相依 ESM，與現有腳本一致）、bash 測試（現有 `bounded`／`fixture`／`jqeq` 輔助函式、mutant runner）。

**Spec:** `openspec/changes/pr-watch/design.md`、`specs/pr-watch/spec.md`、`proposal.md`

## Global Constraints
- 腳本零相依；GitHub 查詢只經既有的 `gh api` → curl 退路，不新增 token 路徑。
- `ready` 的現有欄位與 exit code 不得改變（0/2/3/4/5/6/7）；`watch` 的 exit：0 繼續、8 停止、7 用法錯誤或查詢失敗。
- 狀態檔路徑 `<repo-dir>/.claude/pr-watch.<pr>.local.json`；只有 `watch`、`watch-ack` 寫它，寫法為暫存檔＋rename。
- 留言 key＝`<endpoint>:<id>:<updatedAt>`，endpoint 取 `pulls/comments`、`pulls/reviews`、`issues/comments`；body 去空白後為空的 review 不算新留言。
- 停止原因（`watch.stop.reason`）恰為：`not-open`、`head-not-allowed`、`fork`、`query-failed`、`limit`、`no-progress`、`ready`、`needs-user`，依此順序取第一個。
- 上限：24 小時（自 `startedAt`）或 60 輪。
- 版號：`pr-closeout` 1.1.2 → 1.2.0；marketplace 1.22.1 → 1.23.0。
- commit 不加 session 連結（公開 repo）；staging 一律具名。

## Review Focus
1. 狀態檔是舊版或手動改壞的 JSON → 必須 exit 7，不得重建（重建會把所有已處理的留言重新當成新的）。Task 2 有案例。
2. 同一則留言在兩輪之間被編輯 → 必須重新出現在 `newComments`。Task 3 有案例。
3. 使用者 push 了 pr-watch 的修正、但還沒 `watch-ack --allow-head` → 必須停在 `head-not-allowed`，而不是繼續在別人的 commit 上動作。Task 3 有案例。
4. CI 全綠、只剩未解決 thread，但這一輪剛好有一則新留言 → 不得停在 `needs-user`／`ready`。Task 3 有案例。
5. 本機在錯誤的分支上執行 → exit 7 `wrong-branch`，不得以本機 HEAD 算進度簽章。Task 3 有案例。

---

## 1. ready 補欄位

### Task 1: `ready` 輸出留言清單與 cross-repo 旗標
- [ ] 1.1 `extras().comments.items[]` 與 `isCrossRepository` 進 `ready` 輸出，現有案例全綠
**Files:** Modify `plugins/pr-closeout/scripts/pr-closeout.mjs`（`GQL` 常數、`extras()`）；Modify `plugins/pr-closeout/tests/fixtures/base/graphql.json`（加 `"isCrossRepository": false`）；Test `plugins/pr-closeout/tests/pr-closeout.test.sh`（新節 `# ── pr-watch Task 1`）
**Interfaces:** Produces `extras(raw, pr).comments.items: Array<{endpoint: 'pulls/comments'|'pulls/reviews'|'issues/comments', id: number, updatedAt: string|null, author: string|null, emptyBody: boolean}>`；`prOf(...).isCrossRepository: boolean`（GQL 加這個欄位）；`ready` 輸出 `isCrossRepository`。
1. 寫失敗測試：fixture 的三個留言檔各放一則（review 一則 body 為 `"  "`），斷言 `.comments.items | length == 3`、review 那筆 `emptyBody == true`、`pulls/comments` 那筆 `updatedAt` 等於 fixture 的 `updated_at`、review 那筆 `updatedAt` 等於 `submitted_at`；斷言 `.isCrossRepository == false`。
2. 跑 `bash plugins/pr-closeout/tests/pr-closeout.test.sh`，預期這幾條 FAIL。
3. 實作：`extras()` 逐端點映射；`emptyBody` 只對 reviews 計算，其他兩端點恆為 false。
4. 重跑全套，預期全部 PASS（含既有 `ready` 案例）。
5. commit：`git add plugins/pr-closeout/scripts/pr-closeout.mjs plugins/pr-closeout/tests/pr-closeout.test.sh plugins/pr-closeout/tests/fixtures/base/graphql.json`。

## 2. 狀態檔

### Task 2: 狀態檔讀寫與 `watch-ack`
- [ ] 2.1 `watch-ack` 可加 key 與 head；壞掉或不認得的狀態檔回 exit 7 且不被覆寫
**Files:** Modify `plugins/pr-closeout/scripts/pr-closeout.mjs`（`parseArgs` 接受 `watch`、`watch-ack`、`--state`、`--comment`、`--allow-head`；新增狀態函式）；Test 同上檔新節 `# ── pr-watch Task 2`
**Interfaces:** Produces `loadState(file: string, pr: number): State | null`（檔案不存在回 null；壞 JSON、`version !== 1`、`pr` 不符一律 throw `QueryError`）；`saveState(file: string, s: State): void`（寫 `<file>.tmp.<pid>` 再 `renameSync`）；`State = {version: 1, pr: number, startedAt: string, allowedHeads: string[], seen: string[], round: number, lastSignature: string|null, noProgressRounds: number}`；CLI `watch-ack --state <file> --pr <n> [--comment <key>]... [--allow-head <40/64-hex>]...`，輸出 `{exit, state}`。
1. 寫失敗測試（狀態檔放 `$tmp`）：(a) 不存在的狀態檔 + `watch-ack` → exit 7（ack 不建檔）；(b) 合法檔 + 兩個 `--comment` → `.seen` 含兩者且不重複；(c) 合法檔 + `--allow-head` 非 hex → exit 7；(d) 壞 JSON → exit 7，檔案位元組不變（`cmp`）；(e) `version: 2` → exit 7；(f) `pr` 不符 → exit 7。
2. 跑全套，預期 FAIL。
3. 實作 `loadState`／`saveState`／`watch-ack` 分支；重複 key 去重；不認得的 flag 沿用 `UsageError`。
4. 跑全套，PASS。
5. commit（具名兩檔）。

## 3. watch 判定

### Task 3: `watch` 子命令
- [ ] 3.1 `watch` 輸出 `watch{}` 與正確的停止原因，每個原因至少兩個觸發輸入
**Files:** Modify `plugins/pr-closeout/scripts/pr-closeout.mjs`（新增 `watchVerdict()` 與 CLI 分支）；Test 同上檔新節 `# ── pr-watch Task 3`（以 `mktemp -d` 建 git repo＋bare remote 當 `--repo-dir`，分支名與 fixture 的 `headRefName` 相同）
**Interfaces:** Consumes Task 1 的 `comments.items`、`isCrossRepository`，Task 2 的 `loadState`／`saveState`。Produces 純函式 `watchVerdict(verdict: ReadyVerdict, state: State|null, local: {head: string, branch: string, unpushed: number}, now: Date): {state: State, watch: Watch}`，其中 `Watch = {round, newComments: string[], headAllowed: boolean, settled: boolean, unpushed: number, noProgressRounds: number, stop: {reason, detail}|null, stateIgnored: boolean}`；CLI `watch <owner/repo> <pr> --state <file> --repo-dir <path> [--fixture <dir>]`，exit 0/8/7。`stateIgnored` 由 `git -C <repo-dir> check-ignore -q -- <state>` 的 rc 決定（0 → true）。
1. 寫失敗測試，每列至少兩個觸發輸入：
   - `not-open`：graphql `state` 為 `MERGED`；為 `CLOSED`。
   - `head-not-allowed`：狀態檔 `allowedHeads` 不含 fixture head；ack 一個別的 SHA 之後仍不含。
   - `fork`：`isCrossRepository: true`（兩種：PR 其餘全綠／PR 有 checks-failed）。
   - `query-failed`：graphql 檔缺；`isCrossRepository` 缺欄位。
   - `limit`：`startedAt` 為 25 小時前；`round` 為 60。
   - `no-progress`：同一 fixture 連跑兩次（第二次 exit 8）；第一次與第二次之間只改 `seen` 以外的無關欄位。
   - `ready`：base fixture（exit 0、無留言）；base 加一則已在 `seen` 的留言。
   - `needs-user`：只有未解決 thread；只有衝突（`mergeable: CONFLICTING`）。
   - 反例（必須 exit 0、`stop == null`）：只剩未解決 thread 但有一則新留言（Review Focus 4）；check 為 pending；第一輪（狀態檔不存在 → 建立，`allowedHeads == [fixture head]`）。
   - 編輯過的留言：key 已在 `seen`，fixture 改 `updated_at` → 出現在 `newComments`（Review Focus 2）。
   - 錯誤分支：`--repo-dir` 的 HEAD 在別的分支 → exit 7、detail 含 `wrong-branch`（Review Focus 5）。
   - 狀態檔壞掉時跑 `watch` → exit 7 且檔案不變（Review Focus 1）。
2. 跑全套，預期 FAIL。
3. 實作 `watchVerdict()`：
   - 停止原因依 Global Constraints 的順序判斷。
   - `needs-user` 的條件：沒有新留言；`hits` 不含 `checks-failed`、`pending`；而且 `hits` 不為空或 `unpushed > 0`。
   - 進度簽章：`JSON.stringify([sorted hits code+detail, verdict.head, local.head, newComments.length])`。
   - `noProgressRounds`：簽章與 `lastSignature` 相同就加一，否則歸零；`>= 1` 就停在 `no-progress`。
   - 每次執行 `round` 加一並存檔，停止的那一輪也照樣存檔。
4. 跑全套，PASS。
5. commit（具名）。

### Task 4: `watch` 的突變測試
- [ ] 4.1 五個突變各被自己的案例殺死
**Files:** Modify `plugins/pr-closeout/tests/pr-closeout.test.sh`（summary 區的 `mutant` 呼叫）
1. 加突變（`mutant <label> <殺它的案例名子字串> <perl 替換>`）：
   - 刪掉 `emptyBody` 排除，由「空 body review 不算新留言」的案例殺死。
   - key 拿掉 `updatedAt`，由「編輯過的留言」的案例殺死。
   - `needs-user` 不檢查新留言，由 Review Focus 4 的案例殺死。
   - `noProgressRounds >= 1` 改成 `>= 2`，由 `no-progress` 的案例殺死。
   - `head-not-allowed` 的判斷改成恆為 true（允許），由 `head-not-allowed` 的案例殺死。
2. 跑 `bash plugins/pr-closeout/tests/pr-closeout.test.sh`，最後一行的 mutant 判定全部是 killed，整套 exit 0。
3. commit（具名）。

## 4. skill 與文件

### Task 5: `pr-watch` SKILL.md 與文件斷言
- [ ] 5.1 `skills/pr-watch/SKILL.md` 寫好，docs 測試確認停止原因與禁止動作
**Files:** Create `plugins/pr-closeout/skills/pr-watch/SKILL.md`；Create `plugins/pr-closeout/tests/pr-watch-docs.test.sh`（CI 的 `plugins/*/tests/*.test.sh` glob 會自動納入）
**Interfaces:** Consumes Task 2–3 的 CLI 與 `watch.stop.reason` 值。
1. 寫失敗的 docs 測試：
   - (a) SKILL.md 提到的每個停止原因，都必須出現在腳本裡；腳本的每個停止原因，也都必須出現在 SKILL.md。從腳本抽取原因的方式：讀 `STOP_REASONS` 陣列常數，這個常數由 Task 3 定義，Task 5 不得另抄一份。
   - (b) SKILL.md 不得把這些命令寫成要執行的動作：`gh pr merge`、`resolveReviewThread`、`gh pr comment`、`/replies`、`git push --delete`。如果有提到，必須出現在「不做」那一節。
   - (c) frontmatter 有 `name: pr-watch`，description 含「盯 PR」。
2. 跑 `bash plugins/pr-closeout/tests/pr-watch-docs.test.sh`，預期 FAIL（檔案不存在）。
3. 寫 SKILL.md，依 design.md「組成 4」的五段：啟動、每一輪、push、停止、不做。要寫明：
   - 只執行 `/review-pr` 的第 1、2 步。
   - 本機命令只能從 head 的 workflow 檔推導。
   - 通知內容只放 PR 編號和停止原因。
   - 狀態檔沒被忽略時，提示加 `*.local.json`。
4. 跑 docs 測試和 `pr-closeout.test.sh`，全部 PASS。
5. commit（具名）。

### Task 6: 周邊文件與版號
- [ ] 6.1 README、CHANGELOG、設計文件註記、版號同步，全部測試綠
**Files:** Modify `plugins/pr-closeout/skills/pr-closeout/SKILL.md`（exit 5 那一列）、`plugins/pr-closeout/README.md`、`README.zh-TW.md`、`CHANGELOG.md`、`.claude-plugin/plugin.json`；`.claude-plugin/marketplace.json`；根目錄 `CHANGELOG.md`、`CHANGELOG.zh-TW.md`；`docs/pr-closeout-skill-design-2026-11-09.md`（非目標節）
1. `pr-closeout` SKILL exit 5 那一列補一句：「要長時間盯著改用 pr-watch」。
2. README（中英兩份）加 pr-watch 一節：用法、停止原因、不做的事、狀態檔與 `*.local.json`。
3. 設計文件的非目標補一句：輪詢由 pr-watch 這一層負責，腳本仍然不保存狀態。
4. 版號：`plugin.json` 和 marketplace 裡 pr-closeout 那一筆都改成 1.2.0，marketplace 本身改成 1.23.0。CHANGELOG 三份各加一條。
5. 用 `grep -rn "1\.1\.2" plugins/pr-closeout .claude-plugin` 確認沒有漏改的舊版號（CHANGELOG 的歷史條目除外）；`git diff --stat` 讀回修改的檔案清單，和本 Task 的 Files 逐項比對。
6. 跑 `node scripts/validate-fixtures.cjs` 和 `for s in plugins/*/tests/*.test.sh; do bash "$s" > "$TMPDIR/s.log" 2>&1 || echo "FAIL $s"; done`，不得有任何 FAIL。
7. commit（具名）。
