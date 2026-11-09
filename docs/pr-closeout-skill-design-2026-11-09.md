# PR 收尾 skill 設計（路線圖 W3，2026-11-09）

> 狀態：已核准（2026-11-09，D1–D7 全照建議）。同日使用者同意改變落點：主體做成本 repo 的新 plugin `pr-closeout`；只有個人設定留在個人設定 repo。
> 依據：`optimization-roadmap-2026-11-09.md` W3-1、W3-2；`pstack-porting-candidates-2026-11-09.md` §2.3、§3.1。

## 1. 為什麼做

收尾 SOP（個人設定 repo 的 `refs/pr-closeout.md`）共六步，前四步全靠模型手動拼命令。2026-11-09 同一天走了三次：

- 每次都要自己寫 GraphQL 或 REST 查三個 endpoint、`merged_at`、`merge_commit_sha`，比對 SHA，再 `ls-remote` 確認遠端分支已刪。
- 每次各漏一點，事後才補：
  - 一次漏看 CI 的安全審查有沒有真的執行，後來才翻 log。
  - 一次 merge 方式要另外查前一個 PR 的 parent 數。
- 有一個缺口現有 SOP 完全看不到：被審過的位元組不等於被合併的位元組。
  - 實例：某 PR 的 review-branch 最後一輪記在 commit A，之後 codex 找到兩個問題，修在 commit B。
  - 合併的是 B。B 的變更只跑過測試與突變，沒有任何審查工具再看過。
  - SOP 第 3 步只證明「合併的是我推上去的」，不證明「合併的是審過的」。
- 個人設定 repo 的 main 沒有分支保護，GitHub 不會因為未解決的 review thread 擋 merge。在那邊，thread 有沒有解決只能靠這次自己查。

## 2. 目標

1. **一支零相依的 node 腳本，把 SOP 前四步的事實讀取機械化。** 輸出 JSON verdict 與分類過的 exit code，模型讀判定結果，不再自己拼查詢。
2. **審查涵蓋檢查。** 合併前比對「最後一次審查涵蓋的每個檔」與「PR head 的每個檔」，有差異就列出未審的檔。
3. **openspec 歸檔檢查（W3-2）。** 專案有 `openspec/` 時，收尾前列出這個 PR 動到、但還沒歸檔的 change。
4. **SOP 升級成 skill。** 流程移進 skill 本文，由使用者說 merge 或收尾時觸發；CLAUDE.md 只留一行。

## 3. 非目標

- **不做輪詢或等待模式。** CI 還在跑就回「pending」，等待由呼叫端處理（Bash 背景 until-loop，或之後再跑一次）。pstack 的 watch 模式在這裡不需要。
- **不做 stack／queue 多 PR 模式。** 慣例是單 PR squash。
- **不自動 merge、不自動刪分支、不自動回覆 review。** 這些都是對外、不可逆的動作，維持由模型逐步執行、使用者授權。
- **不判斷 review 留言的內容。** 腳本只列出留言（作者、位置、是否已解決），內容當作不可信資料原樣交給模型讀。

## 4. 反目標（做了也算失敗的情況）

- **看不見的閘門被當成綠燈。** 例如 `mergeStateStatus` 是 BLOCKED 但可見的 check 全綠。凡是未知值、查詢失敗、欄位缺漏，一律判為未就緒（fail-closed）。
- **review 留言內容被插進 shell 命令。** 任何需要回覆的動作都走 `--input` 檔案，不做字串插值。
- **腳本取代判斷。** SOP 第 1 步要求「說得出各層這次會漏什麼」，這必須由模型寫出來，腳本只提供事實。

## 5. 設計

### 5.1 檔案配置

本 repo 新增 plugin（2026-11-09 改定落點，理由見 5.8）：

```text
plugins/pr-closeout/
├── .claude-plugin/plugin.json
├── skills/pr-closeout/SKILL.md     # 流程本文；description 在使用者說 merge／收尾時觸發
├── scripts/pr-closeout.mjs         # 兩個子命令：ready、landed
├── hooks/hooks.json                # PreToolUse：Bash 與 GitHub MCP 的 merge 工具
├── hooks/pr-merge-gate.sh
├── tests/                          # CI 的 validate.yml 會跑 plugins/*/tests/*.test.sh
├── README.md、README.zh-TW.md、CHANGELOG.md
```

個人設定 repo 只留個人設定：

- `pr-closeout/required-checks.json`：各 repo 必須出現的 check 名單。它是個人資料，不能放進公開 repo。腳本預設讀 `~/.claude/pr-closeout/required-checks.json`，可用環境變數 `PR_CLOSEOUT_CONFIG` 覆寫；檔案不存在時就不檢查必跑項。
- `refs/pr-closeout.md`：改成一行指向 skill，「決策層原文」段保留（見 D4）。
- CLAUDE.md 的那一行改指向 skill。

#### 為什麼是本 repo 的獨立 plugin

- **它依賴的東西都在本 repo。** 涵蓋檢查讀的是 code-audit-rigor 寫的 `review-branch-last.json`，歸檔檢查呼叫的是 openspec plugin 的 `reconcile-check.cjs`。放在同一個 repo，那兩邊改格式時，CI 一起測得到。
- **CI 已經涵蓋。** `plugins/*/tests/*.test.sh` 會自動跑。
- **hook 跟著 plugin 出貨。** 安裝後的副本放在 `~/.claude/plugins/`，那是 harness 禁止 sandbox 寫入的路徑，不用動共享的 `settings.json`。
- **不併進現有的 `pr` plugin。** `pr` 只負責寫 PR body，沒有 hook。只想寫描述的人，不該連帶被裝上一道 merge 閘門。

### 5.2 `pr-closeout.mjs ready <owner/repo> <pr> [--expect-head <sha>] [--repo-dir <path>]`

合併前執行。一次 GraphQL 查詢取得以下欄位：

- PR 本身：state、isDraft、mergeable、mergeStateStatus、reviewDecision、headRefOid、baseRefName。
- review threads：每條的 isResolved、isOutdated、path、line、第一則留言的作者。
- head commit 的 statusCheckRollup，含每個 context 的 name、status、conclusion。

另外用 REST 取三個 endpoint 的留言數與作者。查詢 2026-11-09 已實測，單次就能拿到全部欄位。

判定依序如下，命中第一條就停：

| exit | 名稱 | 條件 |
|---|---|---|
| 7 | query-failed | 任一查詢失敗、回傳缺欄位、或出現未知的列舉值 |
| 6 | merge-gate | PR 不是 OPEN、是 draft、reviewDecision 為 CHANGES_REQUESTED、head 不等於 `--expect-head`、或 mergeStateStatus 為 BLOCKED 且 rollup 為 FAILURE／ERROR（pstack `assessGitHubMerge`） |
| 2 | conflict | mergeable 為 CONFLICTING，或 mergeStateStatus 為 DIRTY |
| 3 | unresolved-threads | 有 isResolved 為 false 的 thread。isOutdated 的也算，因為 outdated 只表示行號跑掉，不表示問題解決 |
| 4 | checks-failed | rollup 中任一 context 的 conclusion 不是 SUCCESS／NEUTRAL／SKIPPED。未知值也算失敗 |
| 5 | pending | 有 context 還沒完成，或 rollup 為 PENDING／EXPECTED |
| 0 | ready | 以上都不成立 |

這張表是我排定的優先序，不是 pstack 原樣（見 D1）。建構者檢查後補上的對照如下，都是我的決定：

- **thread 先於 BLOCKED。** 有 conversation-resolution 保護的 repo，有未解決 thread 時 mergeStateStatus 也是 BLOCKED。先判 thread（exit 3），才能把 thread 逐條列給使用者，而不是只回一個籠統的 6。
- **mergeStateStatus 各值的處理：**
  - BLOCKED 且 rollup 失敗：歸 exit 4。
  - BLOCKED，但 thread 與 check 都正常：exit 6，原因標「被看不見的閘門擋住」。這包含 reviewDecision 為 REVIEW_REQUIRED 的情況，也就是 §4 反目標的那一格。
  - BEHIND：exit 6，原因標「base 要求最新」。
  - UNSTABLE：只有非必要的 check 失敗，已由 exit 4 涵蓋。
  - HAS_HOOKS 與 CLEAN：可放行。
  - UNKNOWN：歸 exit 5。
- **mergeable 為 UNKNOWN 回 5，不回 7。** 這是 GitHub 剛 push 後還在計算的正常值，等一下再跑即可。真正的未知列舉值才回 7。
- **所有檢查都跑完才決定 exit。** JSON 的 `hits[]` 列出全部命中的條件，exit code 取最優先的那個。例如對已合併的 PR 跑 `ready`，會回 6，但涵蓋檢查與歸檔檢查的結果照樣寫進 JSON。
- **exit 6 的原因寫在 `gate` 欄位。** 可能的值有 `not-open`、`draft`、`changes-requested`、`head-mismatch`、`blocked-unseen`、`behind`、`unreviewed`，SKILL.md 依這個欄位分流處理。
- **適用範圍。** skill 放在使用者層，也會用在設有 required reviewer 的其他 repo，所以上面每一格都要有測試案例。

JSON 另外帶三組資訊，供模型寫判斷，不參與 exit code：

- **前例。** 前一個已合併 PR 的 merge commit parent 數，以及建議的合併方式。
- **base 落後。** `baseBehind`：PR 的 base 已經前進幾個 commit。check 失敗、且失敗出在 PR 沒動到的檔時，提示可能是 base 過舊（pstack CI 分類規則）。
- **留言清單。** 三個 endpoint 的留言數、作者、時間。

查詢途徑：先用 `gh api graphql`。失敗時改用 `gh auth token` 取 token，以 curl 加 header 直打 GraphQL 與 REST，兩次都失敗才回 7。2026-11-09 實測 sandbox 內兩條路都通，但 CLAUDE.md 記載過 gh 在 sandbox 內會失敗，退路仍保留。token 不寫入輸出、不寫入任何檔。

### 5.3 審查涵蓋檢查（「審過的＝合併的」）

`ready` 帶 `--repo-dir` 時，再讀 `<gitdir>/review-branch-last.json`。這是 review-branch 每輪結束時存的狀態，裡面有 `branch` 與每個檔的 blob 雜湊 `scopedFiles[].blob`。比對方式：

- 以 PR head 的 tree 為準，逐檔比對 blob 雜湊。
- PR 改到、但不在 scopedFiles 裡的檔，或 blob 不同的檔，列進 `unreviewed[]`。
- 純文件路徑（`.md`、`docs/` 等）另列，不算未審。

比對逐檔進行而不是比 commit SHA，原因是 review-branch 審的是工作樹，它記下的 `head` 不一定等於被審的內容；blob 才是被審的位元組。pstack 用的是 `git patch-id`，但 patch-id 只適合比整個 patch，回答不了「哪個檔沒審」。

結果的嚴重度見 D2。沒有 review-branch 紀錄時（例如這輪用的是 code-audit-rigor 或 codex），回報 `coverage: "unknown"`。

### 5.4 openspec 歸檔檢查（W3-2）

`--repo-dir` 指向的 repo 有 `openspec/` 時才執行：

- 列出 PR diff 裡動到的 `openspec/changes/<name>/`，排除 `archive/`。
- 對每個仍存在、尚未歸檔的 change，回報 `unarchivedChanges[]`。
- 若本機有 reconcile-check 的狀態檔，附上 `verify` 的結果（fresh、stale:<artifact>、no-verdict）。

嚴重度見 D3。

### 5.5 `pr-closeout.mjs landed <owner/repo> <pr> --expect-head <sha> --repo-dir <path> [--branch <name>]`

合併後執行，把 SOP 第 3、4 步的驗證機械化：

| 檢查 | 不成立時 |
|---|---|
| `merged_at` 有值 | exit 6 |
| `head.sha` 等於 `--expect-head` | exit 6 |
| `merge_commit_sha` 是 origin/main 的祖先（先 `git fetch origin`，用 `merge-base --is-ancestor`） | exit 6 |
| 帶 `--branch` 時：該分支沒有 open PR、遠端 `ls-remote` 查不到、本地 `branch --list` 也沒有 | exit 6，並列出還在的地方 |

刪分支本身不在腳本裡，原因見非目標。正常流程是：先跑 `landed` 但不帶 `--branch`，確認已合併；接著刪分支；最後再跑一次帶 `--branch` 的 `landed`，確認刪乾淨了。

### 5.6 skill 本文（SKILL.md）

- **步驟。** 沿用 `refs/pr-closeout.md` 的六步，每步標明要跑哪個子命令、各 exit code 怎麼處理。例如 exit 3 時，把未解決的 thread 逐條列給使用者，不自行 resolve。
- **CI 分類規則。** 寫進本文，來源是 pstack babysit：
  - flake 只重跑一次。
  - 同樣的失敗出現第二次，就去讀 job log。
  - 失敗出在 PR 沒動到的檔，先以 baseBehind 判斷是否 base 過舊。
  - 只有失敗出在本次 diff 裡，才值得修一個 commit。
- **description。** 觸發條件是使用者說「merge」或「走收尾 SOP」。合併仍需使用者明說，skill 本文第一段重申「merge 不自動觸發」。

### 5.7 測試

- **fixture 驅動，不打網路。** `--fixture <dir>` 讓腳本讀預錄的 GraphQL 與 REST JSON，取代網路查詢。
- **每個 exit code 至少兩個觸發輸入。** 外加未知列舉值、欄位缺漏、查詢失敗三種 fail-closed 案例。
- **涵蓋檢查。** 用 `mkdtemp` 建 git repo 與假的 `review-branch-last.json`，測已審、未審、純文件、無紀錄四種情況。
- **突變。** 每個判定分支各有一個突變，而且必須被它對應的案例殺掉，比照 bare-cd-check.test.sh 的做法。
- **真實驗證一次。** 對歷史 PR 實跑 `ready` 與 `landed`，結果寫進 PR body。用的是本 repo #42：它已合併，也剛好示範了未審的 commit B。
  - 建構者實際比對過：#42 的 review-branch 紀錄停在 `f4e9c48`，和合併後的 tree 有 6 個檔 blob 不同，另有 `hooks/archive-gate.sh` 根本不在紀錄裡。
  - 這份紀錄是本 repo `.git/review-branch-last.json` 的唯一一份，下一次在本 repo 跑 review-branch 就會覆蓋。實作前要先另存，2026-11-09 我嘗試另存時被權限拒絕。

## 6. 待裁決（附建議）

| # | 問題 | 建議 |
|---|---|---|
| D1 | exit code 的優先序：衝突、未解決 thread、check 失敗同時發生時，回哪一個 | 照 5.2 表格：查詢失敗 > merge gate > 衝突 > thread > check 失敗 > pending。理由是越前面的越不能靠「再等一下」解決。JSON 會列出所有命中的條件，不只第一個 |
| D2 | 審查涵蓋檢查找到未審檔時，算擋下（exit 6）還是只警告 | 擋下，但只在「有 review-branch 紀錄、而且同一個分支」時擋；沒有紀錄時只回報 unknown。理由：那個例子正是有紀錄卻漏了的情況，而強制每次都要有紀錄，會把用 code-audit-rigor 的高風險 PR 也擋下 |
| D3 | openspec 未歸檔的 change 算擋下還是警告 | 警告。依 workflow，Phase 6 可以在 merge 之後做，PR 本來就可能帶著未歸檔的 change 合併 |
| D4 | `refs/pr-closeout.md` 怎麼處理 | 縮成一行指向 skill，「決策層原文」段保留在原處。理由：Knowledge Architecture 規定流程放 skill 本文，原文段是給日後核對摘要用的 |
| D5 | 腳本放哪 | 原建議放個人設定 repo 的 skill 目錄；2026-11-09 改為本 repo 的 `plugins/pr-closeout/`，測試放同 plugin 的 `tests/`，由 CI 收（見 5.1） |
| D2b | 涵蓋檢查擋下後，怎麼解除 | 首選是對未審的檔再跑一輪 review-branch，它的跨輪記憶只會重審有變動的檔。另外允許逐檔放行：`--accept-unreviewed <path>=<理由>`，理由是必填的一句話（例如「codex r3 已審」）。放行的檔與理由寫進 JSON，由 skill 抄進帳本 Log。突變測試要涵蓋「沒有理由的放行無效」 |
| D6 | CI 的安全審查「綠勾但沒真的跑」要不要由腳本抓 | 要，但只抓兩種看得到的徵兆。一是每個 repo 一份必須出現的 check 名單：名單上的 check 沒出現在 rollup 裡就回 4，這能抓到 `paths-ignore` 讓 check 根本沒產生的情況。二是時長下限：claude-code-action 這類 check 低於 30 秒，回報 `suspectedSkip`，只警告不擋。讀 job log 找 `Skipping action` 不做，因為要在 sandbox 外跑，而且 REST 端點回 403。名單是個人資料，放個人設定 repo 的 `pr-closeout/required-checks.json`，key 是 owner/repo（見 5.1） |
| D7 | 要不要加 hook，擋住沒跑 `ready` 就 merge | 要。它符合 CLAUDE.md 的閘門判準：讀的是環境事實，下游消費者是 merge 決策。做法是 PreToolUse hook 攔 `gh pr merge`、`gh api …/merge` 與 GitHub MCP 的 `merge_pull_request`，攔到時自己呼叫 `ready`，exit 0 才放行，否則 deny。使用者可以用 `PR_CLOSEOUT_OK=1` 放行一次。代價是範圍多出 hook 腳本、plugin 的 `hooks.json` 接線與 hook 測試，工作量約多一半。（寫計畫時修正：原本是讓 `ready` 寫標記檔到 `$TMPDIR` 再由 hook 讀取，但 sandbox 內外的 `$TMPDIR` 是不同目錄，hook 讀不到 sandbox 裡寫的標記；而且 sandbox 寫得到 `$TMPDIR`，標記可以偽造。改成 hook 自己查詢就沒有這兩個問題，代價是每次 merge 多一次約 2 秒的查詢。hook 不做涵蓋檢查，因為它無法可靠地知道 PR 對應哪個本機目錄，那一步留在 skill 流程裡） |

## 7. 留給實作者決定的事

- GraphQL 查詢的確切寫法與分頁。thread 或 check 超過 100 個時要分頁，或直接判 7。
- JSON 的欄位命名。
- 「純文件路徑」的清單，可以沿用 security-review push nudge hook 的豁免清單。

## 8. 風險

- **GitHub 的列舉值會增加。** 例如新的 mergeStateStatus，這時腳本會回 7。這是刻意的 fail-closed，代價是 GitHub 改版後要更新腳本。
- **涵蓋檢查只認 review-branch 的紀錄。** codex 與 code-audit-rigor 不留機器可讀的紀錄，用它們審的變更一律是 unknown。要補上，得讓它們也留紀錄，那是另一個工作包。
- **`landed` 要 fetch。** sandbox 外才能 fetch 私有 repo 時，要記得關掉 sandbox。
- **已安裝的副本不會自己更新。** plugin 合併後要跑 `claude plugin update pr-closeout`，hook 與腳本才會生效。
- **必跑名單檔可被改寫。** 從以 `~/.claude` 為專案目錄的 session 裡，sandbox 寫得到 `~/.claude/pr-closeout/`，可以拿掉名單上的 check。個人設定 repo 那邊要把這個目錄加進 `sandbox.filesystem.denyWrite`。
