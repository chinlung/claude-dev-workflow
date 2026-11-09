# PR 收尾 skill 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal：** 把收尾 SOP 的事實讀取做成 `pr-closeout.mjs`（`ready`／`landed`），用 merge 閘門 hook 強制合併前跑過它，並把 SOP 升級成 skill。

**Architecture：**
- **腳本。** 一支零相依的 node ESM 腳本。查詢層只負責取得原始 JSON，網路模式先用 `gh`，失敗再用 curl 加 token；測試時改讀 fixture 目錄。判定層把原始 JSON 轉成 verdict，是純函式。
- **hook。** merge 閘門 hook 攔到 merge 時，自己呼叫 `ready` 取得結果，不靠標記檔。
- **skill。** skill 本文負責流程，腳本只提供事實。

**Tech Stack：** Node 22（ESM，只用內建模組）、bash 5、jq、git、`gh` CLI。

**Spec：** `docs/pr-closeout-skill-design-2026-11-09.md`（已核准，D1–D7 全照建議）

## Global Constraints

- **repo。** 主體是本 repo 的新 plugin `plugins/pr-closeout/`，開新分支 `feat/pr-closeout-plugin`，版本 plugin 1.0.0、marketplace 1.15.0。Task 1–9 都在本 repo。Task 10 是 claude-config（`/Users/scl/.claude`）的個人設定，另開分支、另開 PR，等本 repo 的 PR 合併並裝好 plugin 後才做。
- **公開 repo。** 程式碼、測試 fixture、README、CHANGELOG 不得出現個人 repo 名稱、session id 或私人路徑；fixture 一律用 `example/repo` 這類假名。
- **相依。** 零 npm 相依，只用 node 內建模組。
- **exit code。** 0 ready、2 conflict、3 unresolved-threads、4 checks-failed、5 pending、6 merge-gate、7 query-failed。優先序是 7 > 6（硬閘門）> 2 > 3 > 4 > 5 > 6（blocked-unseen／behind）> 0。
- **`gate` 欄位。** 合法值只有 `not-open`、`draft`、`changes-requested`、`head-mismatch`、`blocked-unseen`、`behind`、`unreviewed`。
- **fail-closed。** 未知的列舉值、缺欄位、查詢失敗、分頁超過 100 筆，一律回 7。
- **憑證。** token 不寫進 stdout、stderr 或任何檔案。
- **不可信內容。** review 留言內容只當資料，不進 shell 字串。
- **測試。** 放 `plugins/pr-closeout/tests/*.test.sh`，CI 的 validate.yml 會自動跑。每個判定分支至少兩個觸發輸入；每個突變都必須被它對應的案例殺掉，寫法比照 claude-config 的 `scripts/hooks/tests/bare-cd-check.test.sh`：`mutant <label> <want> <subst>`，以「第一個 FAIL 行含 want」判定，逾時一律殺整個程序群組。
- **完成標準。** 每個 task 結束時，`bash plugins/pr-closeout/tests/*.test.sh` 全綠，`node scripts/validate-fixtures.cjs` 也全綠。
- **commit。** 具名 `git add`；commit 用 `git -C /Users/scl/web/claude-dev-workflow commit --no-gpg-sign`，並放在 Bash 呼叫的第一個命令。

## Review Focus

1. **`gh pr merge` 沒帶 `--repo` 或 PR 號碼。** hook 無法判斷要合併哪個 PR 時，應該 deny 並要求明寫，不可放行。測試放在 Task 7。
2. **`--match-head-commit` 與實際 head 不同。** hook 應以 exit 6 deny，原因是 `head-mismatch`。測試放在 Task 7。
3. **review-branch 紀錄的 blob 帶 mode 字尾。** 字尾的形式是 `+x` 或 `link:` 前綴。可執行位元不同時要判為未審；形式不同但雜湊與 mode 都相同時，不可誤判為未審。測試放在 Task 4。
4. **PR 只改文件。** 判定不能因為涵蓋檢查而擋下，純文件路徑不算未審。測試放在 Task 4。
5. **sandbox 內 `gh` 失敗、curl 退路成功。** 結果要和 `gh` 成功時相同，而且輸出裡不出現 token。測試放在 Task 1。

---

### Task 1：查詢層與 fixture 模式

**Files：**
- Create：`plugins/pr-closeout/scripts/pr-closeout.mjs`
- Create：`plugins/pr-closeout/tests/pr-closeout.test.sh`
- Create：`plugins/pr-closeout/tests/fixtures/base/`，內含 `graphql.json`、`pulls-comments.json`、`pulls-reviews.json`、`issues-comments.json`、`compare.json`、`prev-pulls.json`、`prev-commit.json`，內容是一個全綠、可合併的 PR

**Interfaces：**
- Produces：`fetchAll({owner, repo, pr, fixture}) -> Promise<Raw>`
  - Raw 的鍵：`graphql`、`pullsComments`、`pullsReviews`、`issuesComments`、`compare`、`prevPulls`、`prevCommit`。
  - 每個鍵是解析後的 JSON；查詢失敗時丟出 `QueryError(message)`。
- Produces：CLI 介面 `pr-closeout.mjs ready <owner/repo> <pr> [--expect-head <sha>] [--repo-dir <path>] [--fixture <dir>] [--accept-unreviewed <path>=<reason>]...`，stdout 印一個 JSON。

- [ ] **Step 1：寫測試。** `fixture base`：對 base fixture 跑 `ready example/repo 1 --fixture <base>`，期望 exit 0，JSON 的 `.exit == 0`、`.hits == []`。
- [ ] **Step 2：寫測試。** `query fails`：fixture 缺 `graphql.json`，期望 exit 7，`.hits[0].code == "query-failed"`。
- [ ] **Step 3：寫測試。** `gh fails, curl fallback`：PATH 前面放一個 `gh` shim，`api` 子命令一律 exit 1，`auth token` 回固定字串 `TOKEN_SENTINEL`；再放一個 `curl` shim，把 `--data` 原樣存檔，回傳 base fixture 的內容。期望 exit 0，stdout 與 stderr 都不含 `TOKEN_SENTINEL`。
- [ ] **Step 4：跑測試，確認紅。** 執行 `bash /Users/scl/web/claude-dev-workflow/plugins/pr-closeout/tests/pr-closeout.test.sh`。期望看到 FAIL，原因是腳本還不存在。
- [ ] **Step 5：實作 `fetchAll`。**
  - 網路模式查詢順序：
    1. GraphQL：`gh api graphql -f query=… -F n=…`。
    2. 失敗時改用 `gh auth token`，經 `execFile` 傳給 curl 的 `-H "Authorization: bearer …"`，token 走參數陣列、不經 shell。
    3. REST 用同樣兩段式。
  - GraphQL 查詢的欄位：
    - state、isDraft、mergeable、mergeStateStatus、reviewDecision、headRefOid、headRefName、baseRefName。
    - `reviewThreads(first:100)`：pageInfo 與節點的 isResolved、isOutdated、path、line，以及 `comments(first:1)` 的作者 login。
    - head commit 的 statusCheckRollup：state 與 `contexts(first:100)`，含 pageInfo。CheckRun 取 name、status、conclusion、startedAt、completedAt；StatusContext 取 context、state。
  - 有下一頁時丟 `QueryError("more than 100 …")`。
- [ ] **Step 6：跑測試，確認綠。** 指令同 Step 4，期望 3 條都 pass。
- [ ] **Step 7：commit。** 訊息：`feat(pr-closeout): query layer with gh, curl fallback and fixtures`。

### Task 2：GitHub 狀態判定（exit 表）

**Files：**
- Modify：`plugins/pr-closeout/scripts/pr-closeout.mjs`
- Test：`plugins/pr-closeout/tests/pr-closeout.test.sh`

**Interfaces：**
- Consumes：Task 1 的 `Raw`。
- Produces：`assess(raw, {expectHead}) -> {exit, gate, hits:[{code, gate?, detail}], threads:[...], checks:[...]}`。
  - `exit` 依 Global Constraints 的優先序，取 `hits` 中最優先的一條。
  - `hits` 列出全部命中的條件。

- [ ] **Step 1：寫測試。** 每個案例都以 base fixture 加一個 `jq` 修改，用 helper `ready_case <want> <label> '<jq on graphql.json>' [args]` 執行。下列每列兩個觸發輸入：

  | want | 觸發輸入（兩個） |
  |---|---|
  | 6，`not-open` | state=MERGED；state=CLOSED |
  | 6，`draft` | isDraft=true，兩種 mergeStateStatus（CLEAN、BLOCKED） |
  | 6，`changes-requested` | reviewDecision=CHANGES_REQUESTED，兩種 rollup 狀態 |
  | 6，`head-mismatch` | `--expect-head` 給不同 SHA；給一個 64 位 SHA |
  | 2 | mergeable=CONFLICTING；mergeStateStatus=DIRTY |
  | 3 | 一條未解決的 thread；一條未解決但 isOutdated=true |
  | 4 | 一個 context 的 conclusion=FAILURE；conclusion=TIMED_OUT（不在白名單） |
  | 4 | mergeStateStatus=BLOCKED 且 rollup=FAILURE；BLOCKED 且 rollup=ERROR |
  | 5 | 一個 context 的 status=IN_PROGRESS；mergeable=UNKNOWN |
  | 6，`blocked-unseen` | BLOCKED 加全綠；BLOCKED 加 reviewDecision=REVIEW_REQUIRED |
  | 6，`behind` | mergeStateStatus=BEHIND，兩種 rollup |
  | 7 | mergeStateStatus=WEIRD；mergeable 缺欄位 |
  | 0 | mergeStateStatus=CLEAN；HAS_HOOKS |

  另加兩條：
  - `hits lists all`：衝突與未解決 thread 同時發生，期望 exit 2、`.hits | length == 2`。
  - `threads listed`：exit 3 時，`.threads[0]` 含 `path` 與 `line`。
- [ ] **Step 2：跑測試，確認紅。**
- [ ] **Step 3：實作 `assess`。** 判定邏輯就是那張表。conclusion 的白名單是 SUCCESS、NEUTRAL、SKIPPED；mergeStateStatus 的已知集合是 CLEAN、HAS_HOOKS、UNSTABLE、BLOCKED、BEHIND、DIRTY、UNKNOWN，不在集合內就回 7。
- [ ] **Step 4：跑測試，確認綠。**
- [ ] **Step 5：加突變。** 每個 gate 值與每個 exit code 各一個突變，例如把 `isOutdated` 的 thread 排除在外，必須被「未解決但 outdated」那個案例殺掉；再跑一次確認全部殺掉。
- [ ] **Step 6：commit。** 訊息：`feat(pr-closeout): ready verdict with the full exit table`。

### Task 3：附加資訊與必跑 check（D6）

**Files：**
- 設定檔：`$PR_CLOSEOUT_CONFIG`，預設 `~/.claude/pr-closeout/required-checks.json`，格式為 `{"<owner>/<repo>": {"required": ["<check name>"], "minSeconds": {"<check name>": 30}}}`。檔案不存在時不檢查必跑項；格式錯誤回 7。測試用 fixture 裡的假設定檔，不碰真檔
- Modify：`pr-closeout.mjs`
- Test：同上

**Interfaces：**
- Produces：JSON 新增以下欄位：
  - `precedent: {pr, parents, method: "squash"|"merge"|"unknown"}`
  - `baseBehind: <int>`
  - `comments: {pullsComments: n, pullsReviews: n, issuesComments: n, authors: [...]}`
  - `suspectedSkip: [name]`
- 必跑名單上的 check 沒出現在 rollup 時，加一條 hit：`{code: "checks-failed", detail: "required check missing: <name>"}`，exit 4。

- [ ] **Step 1：寫測試。**
  - `required missing`：base fixture 拿掉 security-review 的 context，期望 exit 4，detail 含 `required check missing: security-review`。
  - `required missing 2`：拿掉 validate-fixtures，同樣期望 exit 4。
  - `suspected skip`：security-review 的 startedAt 到 completedAt 只有 12 秒，期望 exit 0、`.suspectedSkip == ["security-review"]`。
  - `not suspected`：時長 45 秒，`.suspectedSkip == []`。
  - `precedent`：`prev-commit.json` 有 1 個 parent 時 `.precedent.method == "squash"`，2 個 parent 時為 `"merge"`。
  - `comments`：三個 REST fixture 各放 1 筆留言，`.comments` 的三個計數都是 1。
  - 不在名單上的 repo：只檢查一般 check，不檢查必跑項。
  - 設定檔不存在：同上，exit 0。
  - 設定檔不是合法 JSON：exit 7。
- [ ] **Step 2：跑測試，確認紅。**
- [ ] **Step 3：實作。** `prevPulls` 取第一筆 `merged_at` 不為 null 的 PR，`prevCommit` 的 parents 數量 1 對應 squash、2 對應 merge。`baseBehind` 取自 `compare.behind_by`。
- [ ] **Step 4：跑測試，確認綠；加突變。** 至少兩個：拿掉必跑名單的比對、時長門檻改成 0。確認都被殺掉。
- [ ] **Step 5：commit。** 訊息：`feat(pr-closeout): required checks, suspected skips, precedent and comments`。

### Task 4：審查涵蓋檢查（D2、D2b）

**Files：**
- Modify：`pr-closeout.mjs`
- Test：同上，以 `mkdtemp` 建 git repo 當 `--repo-dir`

**Interfaces：**
- Produces：`coverage(repoDir, {headRefName, headOid, baseRef, accept}) -> {status: "covered"|"unreviewed"|"unknown", reason?, unreviewed:[path], docsOnly:[path], accepted:[{path, reason}]}`。
- `status` 為 `unreviewed` 時，加一條 hit `{code: "merge-gate", gate: "unreviewed"}`，exit 6。

- [ ] **Step 1：寫測試。** fixture repo 的建法：base commit，加上分支的兩個檔 `a.sh`、`b.md`；`.git/review-branch-last.json` 照 review-branch 格式寫入 `branch` 與 `scopedFiles[{file, blob}]`。案例如下：

  | 期望 | 情境 |
  |---|---|
  | covered，exit 0 | blob 完全相同 |
  | unreviewed，exit 6 | `a.sh` 在審查後又改過，`.coverage.unreviewed == ["a.sh"]` |
  | unreviewed | 分支新增 `c.sh`，不在 scopedFiles 裡 |
  | unreviewed | 紀錄是 `<hash>`，head 是 100755 |
  | covered | 紀錄是 `<hash>+x`，head 是 100755 |
  | covered | 未審的只有 `b.md`，列進 `.coverage.docsOnly` |
  | unknown，exit 0 | 沒有 review-branch-last.json |
  | unknown | 紀錄的 branch 與 PR 的 headRefName 不同 |
  | unknown | 本地沒有 head commit |
  | covered | 對 `a.sh` 帶 `--accept-unreviewed a.sh=codex r3 已審`，`.coverage.accepted[0].reason` 為「codex r3 已審」 |
  | 用法錯誤，exit 7 | `--accept-unreviewed a.sh=`（沒有理由） |

- [ ] **Step 2：跑測試，確認紅。**
- [ ] **Step 3：實作。**
  - 變更清單用 `git -C <dir> diff --name-only <merge-base(origin/<base>, head)> <head>`。
  - blob 用 `git ls-tree <head> -- <path>` 取得 mode 與 hash，正規化成 review-branch 的格式：`<hash>`、`<hash>+x`、`link:<hash>`。
  - 純文件路徑的判斷是 `/\.(md|mdx|txt|rst|adoc)$|^docs?\//`。
- [ ] **Step 4：跑測試，確認綠；加突變。** 至少三個：mode 正規化、純文件豁免、放行理由必填。確認都被殺掉。
- [ ] **Step 5：commit。** 訊息：`feat(pr-closeout): reviewed bytes equal merged bytes`。

### Task 5：openspec 歸檔檢查（W3-2，D3）

**Files：**
- Modify：`pr-closeout.mjs`
- Test：同上

**Interfaces：**
- Produces：`.openspec`，形狀是 `{present: bool, unarchivedChanges: [{name, verify: "fresh"|"stale:<x>"|"no-verdict"|"unavailable"}]}`。只警告，不影響 exit。

- [ ] **Step 1：寫測試。**
  - 沒有 `openspec/`：`.openspec.present == false`。
  - PR 動到 `openspec/changes/foo/tasks.md` 且 head 時該目錄還在：`unarchivedChanges[0].name == "foo"`，exit 不變。
  - PR 只動 `openspec/changes/archive/2026-11-09-foo/`：列表為空。
  - 找不到 reconcile-check 腳本：`verify == "unavailable"`。
- [ ] **Step 2：跑測試，確認紅；實作；確認綠。** reconcile-check 的位置：取 `~/.claude/plugins/cache/*/openspec-superpowers-workflow/*/skills/openspec-superpowers-workflow/validators/reconcile-check.cjs` 版本排序最新的一份；路徑可用 `RECONCILE_CHECK` 環境變數覆寫，供測試使用。
- [ ] **Step 3：加突變。** 把 archive 的排除拿掉，確認被殺掉。
- [ ] **Step 4：commit。** 訊息：`feat(pr-closeout): list unarchived openspec changes`。

### Task 6：`landed`

**Files：**
- Modify：`pr-closeout.mjs`
- Create：fixture `landed/pull.json`、`landed/open-pulls.json`
- Test：同上，用 bare origin 加 clone

**Interfaces：**
- Produces：CLI `pr-closeout.mjs landed <owner/repo> <pr> --expect-head <sha> --repo-dir <path> [--branch <name>] [--fixture <dir>]`。
  - 結果為 exit 0、6、7。
  - JSON 欄位：`{mergedAt, mergeCommit, onBase: bool, headMatches: bool, branch?: {openPulls, remote: bool, local: bool}}`。

- [ ] **Step 1：寫測試。** 建一個 bare origin 與 clone，在 origin 的 main 上做一個 squash commit 當 `merge_commit_sha`。

  | 期望 | 情境 |
  |---|---|
  | exit 0 | 已合併、head 相符、在 main 上 |
  | exit 6 | `merged_at` 為 null |
  | exit 6 | head 不符 |
  | exit 6 | merge commit 不是 origin/main 的祖先 |
  | exit 6，`.branch.remote == true` | 帶 `--branch`，但遠端分支還在 |
  | exit 6 | 只有本地分支還在 |
  | exit 6 | open PR 數 1 |
  | exit 0 | 全部刪乾淨 |
  | exit 7 | `git fetch` 失敗（用 git shim 模擬） |

- [ ] **Step 2：跑測試，確認紅；實作；確認綠。** 先 `git -C <dir> fetch origin <base>`；判祖先用 `merge-base --is-ancestor <mc> origin/<base>`，不用原分支的 tip。
- [ ] **Step 3：加突變。** 至少兩個：祖先判定改成用分支 tip、拿掉遠端分支檢查。確認都被殺掉。
- [ ] **Step 4：commit。** 訊息：`feat(pr-closeout): landed verifies merge, head and branch cleanup`。

### Task 7：merge 閘門 hook（D7）

**Files：**
- Create：`plugins/pr-closeout/hooks/pr-merge-gate.sh`
- Create：`plugins/pr-closeout/hooks/hooks.json`
  - PreToolUse 兩個 matcher：`Bash`，以及 `mcp__.*GitHub.*__merge_pull_request`（GitHub MCP 的 merge 工具；前綴依安裝方式不同，所以用正則）。
  - 指令一律寫成 `bash "$CLAUDE_PLUGIN_ROOT/hooks/pr-merge-gate.sh"`，timeout 30。
  - **不加 `if` 篩選。** `if` 只比對命令開頭，`git … && gh pr merge …` 這類複合命令會漏掉。改在 hook 裡用 shell 內建的 `case` 先篩掉不含 `merge` 的輸入，所以每次 Bash 呼叫只多一次不啟動子程序的字串比對。
- Create：`plugins/pr-closeout/tests/pr-merge-gate.test.sh`

**Interfaces：**
- Consumes：`pr-closeout.mjs ready`，預設路徑 `$CLAUDE_PLUGIN_ROOT/scripts/pr-closeout.mjs`，可用環境變數 `PR_CLOSEOUT_SCRIPT` 覆寫，供測試使用。
- 行為：
  - 從 stdin 的 hook JSON 解析目標：
    - Bash 命令裡的 `gh pr merge <n|url> --repo <o/r> [--match-head-commit <sha>]`；
    - `gh api … repos/<o>/<r>/pulls/<n>/merge`；
    - MCP 的 `tool_input.owner`、`repo`、`pullNumber`。
  - 呼叫 `ready <o/r> <n> [--expect-head <sha>]`，exit 0 才放行；其他一律 deny，理由欄位帶 exit、gate 與 hits 的摘要。
  - 命令內含 `PR_CLOSEOUT_OK=1` 時放行。
  - 命令和 merge 無關時，靜默放行。
  - 看得出是 merge、卻解析不出 repo 或 PR 號碼時 deny，要求明寫 `--repo` 與號碼。
  - 這支 hook 是閘門，所以 `ready` 腳本找不到或 node 缺少時也 deny，並在訊息裡寫明怎麼用 bypass。

- [ ] **Step 1：寫測試。** 用假的 `ready` 腳本，依環境變數回指定的 exit 與 JSON。

  | 期望 | 情境 |
  |---|---|
  | 放行 | `gh pr merge 3 --repo o/r --squash`，ready 回 0 |
  | 放行 | 同上，改用 MCP 輸入 |
  | deny，理由含 `exit 3` | ready 回 3 |
  | deny | ready 回 6、gate 為 `head-mismatch`，且假 ready 收到 `--expect-head abc` |
  | deny，含「--repo」 | `gh pr merge 3`，沒帶 `--repo` |
  | 放行 | `PR_CLOSEOUT_OK=1 gh pr merge 3 --repo o/r` |
  | 不呼叫 ready | `git commit -m "gh pr merge later"`：引號內的字不算命令 |
  | deny | ready 腳本不存在 |
  | 放行 | `gh api repos/o/r/pulls/3/merge -X PUT`，ready 回 0 |

  另外，每個解析分支至少兩個輸入。
- [ ] **Step 2：跑測試，確認紅；實作；確認綠。** 命令的斷詞沿用 `plugins/openspec-superpowers-workflow/hooks/archive-gate.sh` 的作法：perl tokenizer、heredoc 剝除、只認命令位置。注意 here-string `<<<` 不能當成 heredoc，判斷是否為 heredoc 時不要加「下一個字元不是 `<`」這個條件，原因見 claude-config 的 bare-cd-check 修正。測試加一條：`cat <<< x` 換行後接 `gh pr merge 3 --repo o/r`，期望照樣攔到。
- [ ] **Step 3：加突變。** bypass、解析、exit 判定各一個，確認都被殺掉。
- [ ] **Step 4：實機驗證一次。** 對一個已合併的 PR 下 `gh pr merge <n> --repo …`，期望被 hook 以 `not-open` deny，而且 GitHub 端沒有任何改變。
- [ ] **Step 5：commit。** 訊息：`feat(hooks): pr-merge-gate runs pr-closeout ready before any merge`。

### Task 8：skill 本文與真實驗證

**Files：**
- Create：`plugins/pr-closeout/skills/pr-closeout/SKILL.md`
- Test：在 `plugins/pr-closeout/tests/pr-closeout.test.sh` 加兩條：SKILL.md 的 frontmatter 有 `name: pr-closeout` 與 description；本文提到的每個子命令都存在於腳本的 usage。

- [ ] **Step 1：寫 SKILL.md。**
  - description 包含「merge」「走收尾 SOP」「收尾」。
  - 本文第一段：「merge 不自動觸發，使用者明說才做」。
  - 腳本一律寫成 `node ${CLAUDE_PLUGIN_ROOT}/scripts/pr-closeout.mjs`。
  - 六步各標明要跑的命令，以及各 exit 與 gate 怎麼處理：
    - exit 3：逐條列出 thread，不自行 resolve。
    - gate `unreviewed`：首選再跑一輪 review-branch，或附理由放行。
    - exit 5：背景 until-loop 等待後再跑。
  - CI 分類規則四條。
  - `suspectedSkip` 與 `precedent` 的用法。
  - 第 5、6 步（專案記憶、帳本收帳）照原 SOP，寫成通用說法，不提個人路徑。
- [ ] **Step 2：真實驗證。** 輸出存在 repo 外的 scratchpad，供 PR body 引用；寫進 PR body 時要去識別化。
  - 對本 repo #42 跑 `ready`，帶 `--repo-dir /Users/scl/web/claude-dev-workflow`。
  - 若 #42 那份 review-branch 紀錄已被覆蓋，改用使用者另存的副本，或記錄為「無法重現」。
  - 期望：exit 6、`gate == "not-open"`；`.coverage` 列出 commit B 帶進來的檔。
  - 再對另一個已合併的 PR 跑 `landed`，期望 exit 0。
- [ ] **Step 3：跑全部測試。** 跑 `plugins/pr-closeout/tests/*.test.sh` 與 `node scripts/validate-fixtures.cjs`，期望全綠。
- [ ] **Step 4：commit。** 訊息：`feat(pr-closeout): skill body`。

### Task 9：plugin 打包與發布準備

**Files：**
- Create：
  - `plugins/pr-closeout/.claude-plugin/plugin.json`：name `pr-closeout`、version `1.0.0`，其餘欄位比照 openspec plugin 的格式。
  - `plugins/pr-closeout/README.md`、`README.zh-TW.md`、`CHANGELOG.md`（`[1.0.0]`）。
- Modify：
  - `.claude-plugin/marketplace.json`：新增條目（version 1.0.0），`metadata.version` 改為 1.15.0。
  - 根目錄的 `CHANGELOG.md` 與 `CHANGELOG.zh-TW.md`：加 `[1.15.0]`。
  - 根目錄的 `README.md` 與 `README.zh-TW.md`：plugin 清單加一段。

- [ ] **Step 1：寫檔。** README 寫清楚四件事：
  - 兩個子命令與 exit 表。
  - 設定檔 `PR_CLOSEOUT_CONFIG` 的格式與預設位置。
  - merge 閘門的行為與 `PR_CLOSEOUT_OK=1`。
  - 安裝後要 `claude plugin update pr-closeout` 才拿得到新版。
- [ ] **Step 2：驗證。** 跑 `node scripts/validate-fixtures.cjs`，期望全綠；版本一致性與 dir completeness 檢查都要過。也跑 `claude plugin validate plugins/pr-closeout`。
- [ ] **Step 3：commit。** 訊息：`release(pr-closeout): 1.0.0 (marketplace 1.15.0)`。

### Task 10：claude-config 的個人設定（本 repo PR 合併並安裝 plugin 之後）

**Files（`/Users/scl/.claude`，分支 `feat/pr-closeout-config`）：**
- Create：`pr-closeout/required-checks.json`，本 repo 用 `["security-review", "validate-fixtures"]`、`minSeconds: {"security-review": 30}`；claude-config 用 `["tests"]`。
- Modify：
  - `.gitignore`：allowlist 加 `pr-closeout/`，否則兩台機器不會同步。
  - `settings.json`：`sandbox.filesystem.denyWrite` 加 `~/.claude/pr-closeout`。
  - `refs/pr-closeout.md`：檔頭改成一行指向 `pr-closeout` skill，「決策層原文」段保留。
  - `refs/INDEX.md`：更新該條目。
  - `CLAUDE.md`：Git 節「PR 收尾 SOP」那一行改指向 skill。動之前先讀 `refs/claude-md-authoring.md`。

- [ ] **Step 1：裝好 plugin。** `claude plugin update`（或 install）`pr-closeout`，再以 `claude plugin list` 確認版本為 1.0.0。
- [ ] **Step 2：寫檔。** 跑 `bash /Users/scl/.claude/scripts/hooks/claude-md-lint.sh`，必須通過。
- [ ] **Step 3：實際用一次。** 走這個 claude-config PR 自己的收尾：`ready` 回 0，merge 閘門放行，`landed` 回 0。
- [ ] **Step 4：跑全套並 commit。** `bash /Users/scl/.claude/scripts/hooks/tests/run-all.sh` 必須 ALL GREEN；commit 訊息 `feat: pr-closeout config, refs and CLAUDE.md point to the plugin skill`。
