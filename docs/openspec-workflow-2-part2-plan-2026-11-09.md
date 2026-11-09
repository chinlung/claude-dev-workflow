# openspec-superpowers-workflow 2.0（下，PR 3）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 補齊紅燈 eval，讓 `tasks.md` 成為 Phase 4 的執行紀錄並由歸檔核查擋下無理由的未勾項，加上 Phase 2 提問預算與設計紅旗、對齊 OpenSpec 1.16，落地歸檔統計腳本，最後一次出 2.0.0。

**Architecture:** 機械規則進既有的 `reconcile-check.cjs`（R6 由 warn 升 fail）與兩個新 bash 測試；文字規則進 `phases.md` 等參考檔；文字改動前先在 `753baae`（PR 2 之前）跑 eval 取得紅燈。OpenSpec CLI 的敘述由新測試對照真實 `--help` 與 `openspec init` 產生的範本，CI 負責安裝固定版本。

**Tech Stack:** bash、jq、零相依 Node（plugin 內程式碼維持 Node 20 可跑）、OpenSpec CLI 1.16.1（需 Node 22.12 以上）、`claude plugin eval`。

**Spec:** `docs/openspec-workflow-2-part2-design-2026-11-09.md`（使用者 2026-11-09 核准四個決策點：eval 花費、個人設定 repo 小 PR、CI 安裝固定版 OpenSpec、CI 升 Node 22）

## Global Constraints

- repo 是 public：eval 目錄（`evals*/`）永遠不進版控；文件、commit、PR、統計輸出不得出現真實專案名、change 名、session id。每個 commit 前 `git status --short` 看不到 `evals`。
- 不改 `SKILL.md` 的 `description`（已 1506／1536 字）；新規則只進正文與參考檔。
- hook 與 `reconcile-check.cjs` 的契約不變：fail-open 一律 `exit 0`；`reconcile-check.cjs` 退出碼 0 通過、1 檢查失敗、2 用法錯誤、3 verify 無有效 verdict。
- plugin 內的 Node 程式碼只用 Node 20 已有的 API；只有 OpenSpec CLI 本身需要 Node 22.12 以上。
- 測試判定只認命令自身的 exit code：`cmd > out.log; rc=$?`，不接管線判定。
- 新測試的突變打在執行路徑上，每個分支至少兩個觸發輸入，斷言數下限（`MIN`）在案例清單之外計算。
- staging 一律具名 `git add <file>`；commit 用 `git commit --no-gpg-sign`，且是該次 Bash 呼叫的第一個命令、`-C` 寫字面絕對路徑；commit 訊息尾端加 `Claude-Session: https://claude.ai/code/<session-id>`。
- 沙盒內 `gh`、`git push`、`claude plugin eval`、`npm`、`openspec` 對外連線用 `dangerouslyDisableSandbox: true`；Bash 不用裸 `cd`。
- 既有三套測試（`archive-gate`、`skip-gate`、`reconcile-check`）與 `node scripts/validate-fixtures.cjs` 在每個 task 結束時必須全綠。
- eval 每次執行都帶 `--max-cost-usd`（pilot 15、正式 25），總花費上限約 $80；超過先停下回報。
- 文字層的措辭要求：先寫規則再寫理由，禁用「應該盡量」類軟句。

## Review Focus

1. R6 遇到 `skip:` 後面沒有理由（行尾、只有空白、只有標點）：必須 fail，與有理由的 `skip: 範圍外` 區分。
2. 任何縮排深度與任何文字的未勾框都算 task（OpenSpec 實測如此）：巢狀框、粗體 step 框都要被 R6 看見。
3. 歸檔統計遇到 CRLF 的 tasks.md、空的 tasks.md、沒有 tasks.md 的 change：三者分開計，不互相污染。
4. 文件裡的 `openspec/changes/...` 路徑、`openspec init .` 與提到工具名稱的敘述，不可被 cli-claims 誤當成子命令；而一個編造的子命令或旗標必須被抓到。
5. 盲測掃描只掃 candidate 看得到的內容（prompt 本文、case 目錄名、scaffold 內容），grader 檔與 front matter 裡出現禁用字不算違規。
6. CI 缺 openspec 時 cli-claims 必須失敗，不得靜默 skip。
7. 未勾項到 Phase 6 才被發現：`snapshot` 必須先擋下（exit 1、不寫狀態檔），補勾或補 `skip:` 後 snapshot 才成功，且 R5 不因此誤判為 Phase 6 期間的修改。

以上各有測試：第 1、2、7 項在 Task 4，第 3 項在 Task 1，第 4、6 項在 Task 6，第 5 項在 Task 2。

---

### Task 1: `openspec-archive-stats.cjs`（W0-1 另一半）

**Files:**
- Create: `plugins/openspec-superpowers-workflow/scripts/openspec-archive-stats.cjs`
- Test: `plugins/openspec-superpowers-workflow/tests/archive-stats.test.sh`

**Interfaces:**
- Produces（CLI）：`node openspec-archive-stats.cjs --root <dir> [--root <dir> …] [--since YYYY-MM-DD] [--names]`。`<dir>` 若本身含 `openspec/changes/archive` 就是一個專案，否則其下直接子目錄各自檢查。stdout 一份 JSON：
  - `definition`（字串，說明 task 的定義）、`asOf`（ISO 日期）
  - `totals`：`archived`、`noTasks`（沒有 tasks.md，或有但零個勾選框）、`withTasks`、`incomplete`（至少一個未勾，與路線圖基準同定義）、`incompletePct`（一位小數）、`zeroChecked`（有 task 但完全沒勾）、`incompleteNoReason`（至少一個未勾且該行沒有 `skip:` 加非空理由）、`withSkipReason`
  - `byMonth`：`{"YYYY-MM": {archived, incomplete}}`，月份取自目錄名 `YYYY-MM-DD-` 前綴，不符者歸 `unknown`
  - `projects`：`[{label, archived, incomplete}]`，`label` 預設為專案目錄名 sha256 前六碼，`--names` 才用原名
- task 的定義：tasks.md 中符合 `^\s*-\s*\[( |x|X)\]` 的行，不分縮排深度與內容，與 OpenSpec 解析一致。
- 退出碼：0 成功（含零個專案）；2 用法錯誤或 `--root` 不存在。

- [ ] **Step 1: 寫失敗的測試** `archive-stats.test.sh`，沿用 `reconcile-check.test.sh` 的 `eq` 與 `mktemp -d` 風格，`STATS=${STATS:-…}` 可指向副本。fixture 樹由測試內建：專案甲兩個已歸檔（一個全勾、一個三項皆未勾）、專案乙一個含一行 `skip: 範圍外`、專案丙一個沒有 tasks.md。案例名稱與斷言：
  - `totals on the fixture tree`：`archived=4`、`noTasks=1`、`withTasks=3`、`incomplete=2`、`zeroChecked=1`、`withSkipReason=1`、`incompleteNoReason=1`
  - `labels are hashed by default / basenames with --names`（各兩個專案）
  - `--since drops older months`：邊界日當天保留、前一天排除
  - `CRLF tasks.md counts like LF`、`empty tasks.md counts as noTasks`、`nested and bold-step boxes count`
  - `root without archive dirs → zero totals, exit 0`；`missing --root path → exit 2`
- [ ] **Step 2: 執行確認失敗**：`bash plugins/openspec-superpowers-workflow/tests/archive-stats.test.sh`；Expected: 全部 FAIL，原因是腳本不存在。
- [ ] **Step 3: 實作** `openspec-archive-stats.cjs`，簽名與輸出如 Interfaces。用 `fs.readdirSync` 加 `statSync`，讀不到的目錄略過而不丟例外。
- [ ] **Step 4: 執行確認通過**：同上命令；Expected: 全 PASS，且實際斷言數達 `MIN`。
- [ ] **Step 5: 突變**：複製腳本到 `$TMPDIR`，用 perl 把勾選框的 matcher 改成只認 `[x]`，以 `STATS=<副本>` 重跑；Expected: 至少 `totals`、`nested` 兩案轉 FAIL。再把 `--since` 的比較改成 `<=`，Expected: 邊界案轉 FAIL。
- [ ] **Step 6: 對本機資料跑一次**（只看，不 commit 輸出）：`node …/openspec-archive-stats.cjs --root <projects-root>`，把 `totals` 抄進帳本 Log 作為新基準（對照設計 §4.2 的 133／51／26）。
- [ ] **Step 7: Commit**：`git -C <repo> add plugins/openspec-superpowers-workflow/scripts/openspec-archive-stats.cjs plugins/openspec-superpowers-workflow/tests/archive-stats.test.sh` 後 commit，訊息 `feat(openspec-workflow): archive stats script measures tasks left unchecked at archive`。

---

### Task 2: 盲測規則與禁用字掃描（個人設定 repo 另一個 repo）

**Files（repo：`~/.claude`，分支 `feat/eval-blind-scan`，先 `git -C ~/.claude checkout -b feat/eval-blind-scan`；該 repo 另有一個使用者的未追蹤 `skills/show-me`，不得 stage）:**
- Create: `scripts/audit/eval-blind-scan.cjs`
- Create: `scripts/hooks/tests/eval-blind-scan.test.sh`（`run-all.sh` 會自動收錄 `*.test.sh`）
- Modify: `refs/plugin-eval.md`（新增「盲測規則」一節，並在 §4 開頭一句指向它）；`refs/INDEX.md` 若有該檔的觸發描述就補一句

**Interfaces:**
- Produces：`node eval-blind-scan.cjs <eval-dir> [--words a,b,…]`。掃每個 `<case>/prompt.md` 的本文（略過 front matter）、case 目錄名、`<case>/` 下 `graders/` 以外的其他檔。預設禁用詞：英文 `eval`、`judge`、`experiment`、`rubric`、`score`、`compare`、`benchmark`、`candidate`、`arena`（詞界、不分大小寫），中文 `評分`、`評審`（子字串）。**不含** `test`、`測試`、`基準`：本 plugin 的題目是開發工作，這些詞是題目內容本身。命中印 `<相對路徑>:<行號>: <詞>`，exit 1；沒有命中 exit 0；目錄不存在 exit 2。

- [ ] **Step 1: 寫失敗的測試** `eval-blind-scan.test.sh`（風格照同目錄的 `knowledge-usage.test.sh`，`SCAN=${SCAN:-…}` 可指副本），案例：
  - `clean tree → exit 0`
  - `every default word in a prompt body → exit 1 naming that word`（迴圈全部預設詞，每個詞各一個 case）
  - `word in graders/ → exit 0`、`word in front matter → exit 0`
  - `case dir named with eval → exit 1`、`extra file beside prompt.md containing a word → exit 1`
  - `test and 測試 are not flagged by default`（prompt 本文含 TDD 字樣 → exit 0）
  - `missing dir → exit 2`、`--words overrides the list`
- [ ] **Step 2: 執行確認失敗**：`bash scripts/hooks/tests/eval-blind-scan.test.sh`（用 `git -C` 不適用，使用絕對路徑 `bash ~/.claude/scripts/hooks/tests/eval-blind-scan.test.sh`）；Expected: FAIL，腳本不存在。
- [ ] **Step 3: 實作** `eval-blind-scan.cjs`。
- [ ] **Step 4: 通過**：同上命令；Expected: 全 PASS。
- [ ] **Step 5: 突變**：副本中把詞表少一個詞，以 `SCAN=<副本>` 重跑；Expected: 恰好該詞的案例轉 FAIL。把「略過 graders/」拿掉；Expected: `word in graders/` 轉 FAIL。
- [ ] **Step 6: 寫 `refs/plugin-eval.md` 的「盲測規則」**，來源 pstack `playbooks/eval.md`（MIT，© 2026 Lauren Tan，文中註明）：禁用詞表（不含 test、測試，理由寫明；只套用新 suite，不回頭掃舊 `evals/`）；prompt 要像真實使用者請求、只講目標不講量測；不要求受測者列出用了哪些規則；目錄與檔名用像專案的名字；不告訴受測者有其他受測者；judge 只看以中性標籤命名的輸出；兩個版本比較時同一個 judge 同一把尺。並寫明「跑 eval 前先 `node scripts/audit/eval-blind-scan.cjs <eval-dir>`」。
- [ ] **Step 7: 全套與 commit**：`bash ~/.claude/scripts/hooks/tests/run-all.sh`（約 2 分鐘，可能被移到背景）；Expected: exit 0。具名 `git add` 四個檔後 commit，訊息 `feat(evals): blind-testing rules and a forbidden-word scan for eval prompts`。**不 push、不開 PR**，留到 Task 3 用真實 prompt 驗過掃描腳本之後（Task 7 之後與本 repo 的 PR 同期處理）。

---

### Task 3: 三個新 eval suite 與紅燈基準（本機、不進版控）

**Files（皆在 `plugins/openspec-superpowers-workflow/` 下，整個目錄 gitignored）:**
- Create: `evals-design/`、`evals-trigger/`、`evals-phase6/`，各含一份 `.gitignore`（內容 `*`，前面加一行說明註解）與 `README.md`（設計、基準表）
- 每個 case：`NN-<像專案的名字>/prompt.md`（front matter 照既有 `evals/02-*/prompt.md`）與 `graders/*.md`

**Interfaces:**
- Consumes：Task 2 的 `eval-blind-scan.cjs`；既有 `evals/` 的 case 寫法、`refs/plugin-eval.md` §4 的 grader 陷阱。
- Produces：每個 suite 的基準表（case、對應缺陷、`753baae` 的 with／without 分數、紅或綠、綠則寫「缺陷不在文字層」）。

案例（情境細節與 grader 措辭由實作者寫，須遵守 §4 陷阱：prompt 開頭加中性的「空 checkout」說明、不計數會被 agent 自己引用的字面、反向 case 要有 outcome grader）：

| suite | case | 缺陷 | 檢查 |
|---|---|---|---|
| evals-design | 01 做完兩項就勾 | P-B | 用 `scaffold_script` 預放 OpenSpec 格式 tasks.md（三項）；要求實作前兩項（各建一個小檔）；`{source: file}` 檢查前兩項為 `[x]`、第三項仍為 `[ ]` |
| evals-design | 02 不做的項要寫 skip | P-B | 使用者說第三項不做了；該行仍為 `[ ]` 且含 `skip:` 加非空理由，沒有被刪 |
| evals-design | 03 要求跳過提問 | P-E | 已核准的 proposal 與 specs 貼在訊息裡；使用者說跳過提問直接寫 design.md；design.md 已建、最後訊息零問句（llm）、含假設區段 |
| evals-design | 04 未說跳過 | P-E | 最後訊息問句不超過 2 題（llm），design.md 仍然寫出並列出假設 |
| evals-trigger | 01 單模組小修 | P-C | 回覆逐面列出八個契約面的結論（regex 八個關鍵字為次要，llm 為主） |
| evals-trigger | 02 權限邊界變更 | P-C | 走 workflow：用了 Skill 或建出 `openspec/changes/<name>/proposal.md` |
| evals-trigger | 03 無 openspec 目錄的功能請求 | P-C | 同樣走 workflow |
| evals-phase6 | 01 最後一輪未標 final 就要歸檔 | P-D | 使用者說「歸檔吧」；回覆不進入歸檔、要求確認收斂（llm） |
| evals-phase6 | 02 整份重寫 | D | scaffold 放 spec／design／review-notes／tasks；重寫後無補丁語言、tasks.md 內容不變 |
| evals-phase6 | 03 憲法項走 config.yaml | D | `[CONSTITUTION] Y` 寫進 `openspec/config.yaml`，不進 spec |

- [ ] **Step 1: 撰寫三個 suite**。先 `claude plugin eval --help` 讀完整輸出，確認 `scaffold_script`、`--eval-dir`、`--runs`、`--max-cost-usd` 的現行寫法；每個 eval 目錄放 `.gitignore`。
- [ ] **Step 2: 盲測掃描**：`node ~/.claude/scripts/audit/eval-blind-scan.cjs plugins/openspec-superpowers-workflow/evals-design`（另兩個同），Expected: 全部 exit 0；有命中就改 prompt，不改詞表。
- [ ] **Step 3: 取出基準版本**：`git -C <repo> worktree add "$TMPDIR/os-base" 753baae`；把三個 eval 目錄複製進 `$TMPDIR/os-base/plugins/openspec-superpowers-workflow/`。Expected: 該目錄的 `hooks/` 沒有 `archive-gate.sh`。
- [ ] **Step 4: pilot（`--runs 1`）**，在基準 plugin 目錄、每個 suite 各一次：`claude plugin eval . --eval-dir evals-design --ablation with-without --judge-model sonnet --allow-tools Write Edit -j 4 --no-publish --runs 1 --max-cost-usd 15`。Expected: 依 `refs/plugin-eval.md` §3 的健康檢查通過（`.suite.plugins` 列出目標 plugin、無 `cannot pass with the granted tools`、非 `$0.00`）。**讀每個 case 的產出**確認 with 組真的依 plugin 文字行事，特別是 superpowers 在 sandbox 內是否可用（設計 §7 的第一個風險）。grader 有歧義就改 grader 再 pilot，記錄在 suite 的 README。
- [ ] **Step 5: 正式基準（`runs: 3`）**，同一基準 worktree，三個 suite 各跑一次；把每題 with／without 分數填進各 suite README 的基準表。Expected: 每個缺陷（P-B、P-D、P-E）至少一題 with 組低於 1.00 為紅；若沒有，如實記「缺陷不在文字層」，不改題湊紅。
- [ ] **Step 6: 記帳本 Log 並清理**：基準表的摘要寫進帳本 Log；`git -C <repo> worktree remove --force "$TMPDIR/os-base"`；`git status --short` 確認看不到 `evals`。無 commit。

---

### Task 4: tasks.md 回到執行紀錄（W2-3）

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/reconcile-check.cjs`（`checkR6`）
- Modify: `plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh`
- Create: `plugins/openspec-superpowers-workflow/tests/fixtures/openspec-workflow/tasks-format/tasks.md`（標準範例：兩個 `## ` 分組、三個 `### Task N` 標題，每個 Task 一個勾選框，步驟用編號清單）
- Modify（文字層）：`phases.md`（Phase 1 步驟 2 的 tasks 草稿說明、Phase 3 的 sync-back 格式規則、Phase 4 逐項勾與出口檢查、6c 刪除「用 `--yes` 略過」改為帶 `skip:` 的警告屬預期）、`SUPERPOWERS-HANDOFF.md`（Phase 3 與 4 模板；「可以 check off」限 Phase 4）、`SKILL.md` 正文規則 4、`RECONCILIATION-CRITERIA.md`（R6 由 warn 改 fail）、`OUTPUT-CONTRACTS.md` Phase 3 列、`PHASE-IDENTIFICATION.md`、`README.md`

**Interfaces:**
- Consumes：既有 `checkR6(ctx)` 回傳 `{status, detail}`。
- Produces：`R6` 規則 = tasks.md 中每個符合 `^\s*-\s*\[ \]` 的行，必須同行含 `skip:\s*\S`（冒號後至少一個非空白字元）才算有理由；至少一行沒有 → `fail`，`detail` 列出每一行；沒有任何勾選框 → `warn`；其餘 `pass`。
- Produces：`snapshot` 在記錄雜湊前先跑 R6；R6 為 fail 時 exit 1、不建立也不更新狀態檔，stdout 列出缺理由的行；通過才照舊寫 snapshot 並印狀態檔路徑。

- [ ] **Step 1: 改測試（紅）**：把既有「R6：未勾選 task 沒有 skip: → warn」改為期望 `fail` 且 `check` exit 1，並新增案例：
  - `R6 skip with reason → pass`（兩種：行尾 ` — skip: 範圍外`、行中）
  - `R6 skip with empty reason → fail`（`skip:` 在行尾、`skip:` 後只有空白、`skip:` 後只有標點，三個輸入）
  - `R6 nested unchecked box → fail`、`R6 bold-step unchecked box → fail`
  - `R6 zero boxes → warn, exit 0`、`R6 all checked → pass`、`R6 checked line mentioning skip: → pass`
  - `format sample passes R6 once ticked`：把 `tasks-format/tasks.md` 的框全改 `[x]` 後 `check` 通過
  - `snapshot refuses while R6 fails`：兩個輸入（無理由的未勾項、空理由），exit 1 且狀態檔不存在
  - `snapshot succeeds after ticking, then check passes R5`：補勾後 snapshot 成功，之後 `check` 的 R5 為 pass（補勾發生在 snapshot 之前，不被當成 Phase 6 期間的修改）
  - `check still fails R6 when tasks.md is edited back after snapshot`：snapshot 後把某框改回 `[ ]` 且無理由，R5 與 R6 皆 fail
- [ ] **Step 2: 執行確認失敗**：`bash plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh`；Expected: 新的 `fail` 案例 FAIL（目前只 warn），其餘既有案例仍 PASS。
- [ ] **Step 3: 實作** `checkR6` 如 Interfaces；所有 detail 行附行號。`snapshot` 先呼叫 `checkR6`，fail 時 exit 1 且不寫狀態檔。
- [ ] **Step 4: 通過**：同上；Expected: 全 PASS，`archive-gate`、`skip-gate` 兩套仍綠。
- [ ] **Step 5: 突變**：副本中把 `skip:\s*\S` 改成 `skip:`；Expected: 三個空理由案例轉 FAIL。把 `fail` 改回 `warn`；Expected: 所有 `fail` 案例轉 FAIL。把只掃行首縮排 0 的限制加上（`^-` 取代 `^\s*-`）；Expected: 巢狀案例轉 FAIL。
- [ ] **Step 6: 文字層**：依 Files 逐檔改。`phases.md` 6a 的第一步改成：先把每個未勾項補勾或補 ` — skip: <理由>`（只動框與 skip 後綴，不改任務描述），再執行 `snapshot`；Phase 5 發現某項沒做完時只記 `[CODE] N` 條目，留到這一步處理。Phase 3 規則寫明：每個 Task 標題下只留一個勾選框，writing-plans 產出的步驟框改為編號清單，理由一句（OpenSpec 計每個框為 task；`task-brief` 以標題切段）。Phase 4 寫明：任務通過完成條件後在同一輪改成 `[x]`；出口檢查是 `openspec instructions apply --change <name> --json` 的 `progress.remaining` 為 0，或每個剩餘項帶 `skip:` 理由。完成後 `grep -rn "check off\|--yes" plugins/openspec-superpowers-workflow --include=*.md` 逐筆確認沒有與新規則矛盾的敘述。
- [ ] **Step 7: 全套與 commit**：三套測試加 `node scripts/validate-fixtures.cjs`，Expected: 全綠。具名 `git add` 後 commit，訊息 `feat(openspec-workflow): unchecked tasks need a skip reason to archive; tasks.md keeps one box per task`。

---

### Task 5: Phase 2 提問預算與設計紅旗（W2-4）

**Files:**
- Create: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/DESIGN-RED-FLAGS.md`
- Create: `plugins/openspec-superpowers-workflow/tests/skill-docs.test.sh`
- Modify: `phases.md`（Phase 2）、`SKILL.md` 正文（指向新檔，不動 description）、`SUPERPOWERS-HANDOFF.md`（Phase 2 模板）、`README.md`

**Interfaces:**
- Produces：`DESIGN-RED-FLAGS.md` 恰有八個 `## ` 標題（淺模組、資訊洩漏、依時序切分、穿透方法、分裂的擁有權、同事兩種做法、可匯入的內部、手動同步清單），每條含「徵兆」「自問」「處置」三行；檔首一行註明改寫自 `cursor/plugins` 的 pstack（MIT，© 2026 Lauren Tan）。
- `skill-docs.test.sh` 的斷言：SKILL.md `description` 不超過 1536 字（用 node 解析 front matter 計字元）；SKILL.md 正文提到的每個 `*.md` 檔名都存在於同目錄；`DESIGN-RED-FLAGS.md` 恰八個 `## ` 標題且含出處行。

- [ ] **Step 1: 寫失敗的測試** `skill-docs.test.sh`，案例：`description within 1536 chars`、`every .md referenced by SKILL.md exists`、`red flags file has eight headings and attribution`。先把 SKILL.md 的指向寫進正文但不建新檔 → 第二、三案 FAIL。Expected: 這兩案 FAIL，第一案 PASS。
- [ ] **Step 2: 建 `DESIGN-RED-FLAGS.md`**，內容為八條紅旗的改寫（不逐字抄），前提寫明「下一位貢獻者是只看自己打開的檔的 agent」。
- [ ] **Step 3: 改 Phase 2**：依設計 §4.4 的六點寫成條列：先分類（可觀察的事實自己查）、全 phase 至多 2 題且只問改變「做什麼」的、其餘寫成 design.md 的 `## Open Questions` 並附預設、使用者說跳過就零題直接寫、能實驗回答的做拋棄式 prototype 放 `$TMPDIR` 或 scratch 不放進 `openspec/`、覆寫 design.md 前對照紅旗並把命中與處置寫進 `## Trade-offs`。註明本上限優先於 brainstorming skill 的預設節奏。
- [ ] **Step 4: 通過**：`bash plugins/openspec-superpowers-workflow/tests/skill-docs.test.sh`，Expected: 全 PASS。突變：副本中刪掉一個紅旗標題；Expected: 第三案轉 FAIL；把 description 改長到 1537 字；Expected: 第一案轉 FAIL。
- [ ] **Step 5: 全套與 commit**：四套測試加 `validate-fixtures` 全綠後，具名 `git add`，訊息 `feat(openspec-workflow): Phase 2 asks at most two questions, writes assumptions down, and checks design red flags`。這項的行為證明在 Task 7 的 eval，不在本 task。

---

### Task 6: 對齊 OpenSpec 1.16 與 CI（W2-5）

**Files:**
- Create: `plugins/openspec-superpowers-workflow/tests/cli-claims.test.sh`
- Create: `plugins/openspec-superpowers-workflow/tests/openspec-version`（單行 `1.16.1`）
- Modify: `.github/workflows/validate.yml`（`node-version` 20 → 22；在跑套件之前加一步安裝 OpenSpec）
- Modify: `phases.md`（Prerequisites 的 CLI 與指令對照表、Phase 4 主推工具、Decision Quick Reference，並新增「`/opsx:*` 與階段對照」一節，含 `update` 與 `onboard`）、`SKILL.md`（階段表第 4 列）、`PHASE-IDENTIFICATION.md`（以 `status --json` 判斷進度）、`SUPERPOWERS-HANDOFF.md`（Phase 4 預設 executing-plans）、`README.md`

**Interfaces:**
- Produces（`cli-claims.test.sh` 的案例）：
  - `every "openspec <sub>" in plugin docs is a real subcommand`：只看程式碼區塊與行內程式碼中以 `openspec` 開頭、第二個詞為小寫英數與連字號、且不含 `/` 的片段；對照 `openspec --help` 的命令表
  - `every --flag on such a line exists in that subcommand's --help`
  - `docs cover every upstream /opsx name`：在隔離的 `XDG_CONFIG_HOME` 與 `HOME` 下執行 `openspec config set profile custom` 與 `openspec config set workflows '[十二個名稱]'`，再 `openspec init . --tools claude`，取 `.claude/commands/opsx/*.md` 的檔名為集合；`phases.md` 的對照節必須提到集合中每一個名稱，且文件中出現的每個 `/opsx:<名稱>` 都在集合內
  - `known-wrong claims are gone`：`phases.md` 不得含「no direct CLI equivalent」與「use `--yes` to proceed」
  - `format sample parses as one task per Task heading`：對 `tasks-format/tasks.md` 的拷貝（放進暫存專案的 change 目錄，補齊必要產物）執行 `openspec instructions apply --change <name> --json`，`progress.total` 等於 Task 標題數
  - `CI without openspec fails`：`CI=true` 且 `openspec` 不在 PATH → exit 1；本機不在 PATH → 印明顯的 SKIP 訊息後 exit 0

- [ ] **Step 1: 寫失敗的測試** `cli-claims.test.sh`，`DOCS_DIR`、`OPENSPEC_BIN` 可覆寫以便突變。Expected 先跑：`docs cover every upstream /opsx name` 與 `known-wrong claims are gone` FAIL（目前文件沒有對照表且含錯誤敘述），子命令與旗標兩案 PASS。**記下這個紅燈輸出**。
- [ ] **Step 2: 改文字**：依設計 §4.5 的事實更正與對照表（含 `update` 一列、`onboard` 一列）改 `phases.md` 等檔；CLI 備援指令保留 `--yes`，並寫明有 `skip:` 項時非互動歸檔必須帶 `--yes`（1.16.1 實測不帶會因讀不到 stdin 而 exit 1）；對照表中 bulk-archive 的要求寫成「每個 change 都有新鮮的 `reconcile-check.cjs` 結果」，不是 `/opsx:verify`；Phase 4 主推 executing-plans，SDD 列為 task 彼此獨立時，與 CLAUDE.md 決策樹一致。
- [ ] **Step 3: 通過**：`bash plugins/openspec-superpowers-workflow/tests/cli-claims.test.sh`（需要 `openspec` 在 PATH 與 Node 22.12 以上）；Expected: 全 PASS。
- [ ] **Step 4: 突變**：複製 docs 到暫存目錄後以 `DOCS_DIR=<副本>` 重跑 —— 加一行 `openspec frobnicate`；Expected: 子命令案 FAIL。加 `openspec archive foo --nonsense`；Expected: 旗標案 FAIL。加 `/opsx:frobnicate`；Expected: 第三案 FAIL。從對照節刪掉 `verify`；Expected: 第三案 FAIL。`PATH` 去掉 openspec 且 `CI=true`；Expected: exit 1。
- [ ] **Step 5: 改 CI**：`validate.yml` 的 `node-version: '22'`；新增步驟 `npm install -g --ignore-scripts "@fission-ai/openspec@$(cat plugins/openspec-superpowers-workflow/tests/openspec-version)"`，位置在 `Run every plugin test suite` 之前。本機先以暫存 prefix 驗證 `--ignore-scripts` 的全域安裝仍能產生可執行的 `openspec`：`npm install -g --ignore-scripts --prefix "$TMPDIR/npm-g" @fission-ai/openspec@1.16.1` 後執行 `"$TMPDIR/npm-g/bin/openspec" --version`，Expected: `1.16.1`。
- [ ] **Step 6: 全套與 commit**：五套測試加 `validate-fixtures` 全綠。具名 `git add` 後 commit，訊息 `feat(openspec-workflow): align docs with OpenSpec 1.16 and check the claims against the CLI in CI`。**Push 後 CI 必須看到 `validate-fixtures` 綠**，特別確認 cli-claims 在 CI 真的執行而非 SKIP（看 run log 的 `found N suites` 與該套件輸出）。

---

### Task 7: 綠燈 eval 與 2.0.0 出貨

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/.claude-plugin/plugin.json`（version 2.0.0）、`.claude-plugin/marketplace.json`（該 plugin 的 version 2.0.0 與 description、`metadata.version` 1.13.3 → 1.14.0）、`plugins/openspec-superpowers-workflow/CHANGELOG.md`、`plugins/openspec-superpowers-workflow/README.md`

**Interfaces:**
- Consumes：Task 3 的三個 suite 與基準表；既有 `evals/` 的基準 +0.60。

- [ ] **Step 1: 綠燈 eval**：在本分支 plugin 目錄，三個新 suite 各 `runs: 3` 正式跑（命令同 Task 3 Step 4，去掉 `--runs 1`，`--max-cost-usd 25`）。Expected: Task 3 判為紅的題目 with 組 1.00 或接近；若某題仍紅，讀產出判斷是 plugin 文字不足（回 Task 4／5 補）還是 grader 問題。
- [ ] **Step 2: 舊 suite 回歸**：`claude plugin eval . --ablation with-without --judge-model sonnet --allow-tools Write Edit -j 4 --no-publish --max-cost-usd 25`（`evals/`）。Expected: 平均 Δ 不低於 +0.55，with 組八題維持 1.00；明顯下降就是回歸，先讀產出。
- [ ] **Step 3: 版本一致**：`grep -rn "1\.5\.0" --include=*.json --include=*.md .` 逐筆確認要不要改；plugin.json、marketplace.json、CHANGELOG、README 的版本與描述一致。`claude plugin validate plugins/openspec-superpowers-workflow` 與 `claude plugin validate .`，Expected: 無錯誤。
- [ ] **Step 4: CHANGELOG 2.0.0**：一個條目涵蓋 PR 2 與本 PR。**Breaking** 逐項列：歸檔閘門、skip-gate v2（聲明檔）、R6 未勾項無 `skip:` 理由即 fail、tasks.md 每 Task 一個框、Phase 2 提問上限。**Added**：`reconcile-check.cjs`、`openspec-archive-stats.cjs`、`DESIGN-RED-FLAGS.md`、cli-claims 測試。**Notes**：eval 基準與 Δ，已安裝副本需 `claude plugin update openspec-superpowers-workflow`。
- [ ] **Step 5: 全套**：所有 `plugins/*/tests/*.test.sh`、`node scripts/validate-fixtures.cjs`、`bash scripts/hooks/validate-on-plugin-edit.test.sh` 全綠；`git status --short` 看不到 `evals`。
- [ ] **Step 6: Commit**：具名 `git add` 版本檔與 CHANGELOG、README，訊息 `release(openspec-workflow): 2.0.0 (marketplace 1.14.0)`。
- [ ] **Step 7: 記錄與後續**：eval 摘要與歸檔統計新基準寫進帳本 Log。之後走 CLAUDE.md 的自審流程（simplify → review-branch 加 codex → security-review → push → PR → CI），個人設定 repo 分支的 push 與 PR 一併處理。

---

## 完成後（不屬於 task）

- `reconcile-check.cjs`、`archive-gate.sh` 的 2.0.0 行為在已安裝副本要靠 `claude plugin update` 才會生效；合併後提醒使用者。
- 兩週後重跑 `openspec-archive-stats.cjs` 與 `knowledge-usage.cjs`，對照設計 §6 的目標。
- 路線圖的 W2-6（schema fork spike）、W3 以後仍待排程。
