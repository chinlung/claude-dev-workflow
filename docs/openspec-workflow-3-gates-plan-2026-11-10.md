# openspec-superpowers-workflow 3.0 確認點實作計畫

> **狀態（2026-11-11 回填）：** 已完成，Task 1–4 隨 PR #52 合併（main `cd0ccbb`）；勾選框於收尾後回填。與計畫的偏差：Task 5（jev skill 落點）由使用者拿掉；Task 3 只做兩個 eval case，「P1 無觸發會繼續」因 eval 環境沒有 shell 量不到；gate-check 另加 `p3`／`p6b` 模式與 tasks.md 格式檢查（`validate-openspec-workflow.cjs` 不讀 tasks.md），沒有 shell 時改為照規則手動判定；審查時一再找到「該停卻放行」的輸入形式，比對一律改從寬（設計稿 §11）。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把每個 phase 都等使用者確認，改成由 `gate-check.cjs` 依事實決定要不要停：P1、P2 有觸發條件才停，P3、P6b 不停，P5 加上收斂建議。

**Architecture:** 新增唯讀的 validator `gate-check.cjs`，讀 change 目錄與專案設定，用 exit code 回答「停（10）／繼續（0）／錯誤（1）」。skill 文件改成以這個 exit code 作為 Phase 1→2、2→3 的轉換條件；P3、P6b 的確認從文件中拿掉。不加 hook。

**Tech Stack:** Node 22（CommonJS，不加相依套件）、bash 測試套件（與 `tests/reconcile-check.test.sh` 同一寫法）、`claude plugin eval`。

**Spec:** `docs/openspec-workflow-3-gates-design-2026-11-10.md`（下稱「設計」）。證據在 `docs/openspec-hitl-gate-analysis-2026-11-10.md`。

## Global Constraints

- **版本**：plugin `2.2.1` → `3.0.0`；marketplace 頂層 `1.15.4` → `1.16.0`，plugin 條目同步改成 `3.0.0`。
- **exit code 契約**：`gate-check.cjs p1|p2 <change-dir>`。`0` = 繼續，`10` = 停，`1` = 用法錯誤或讀不到 change；skill 文件把 `1` 視同停。
- **偏向問人**：設定檔讀取失敗、`gates` 值無法辨識時，視同 `supervised`，判定為停，理由 id `settings-unreadable`。這和兩個 hook 的 fail-open 方向相反，是刻意的（設計 §4.6）。
- **不碰網路**：gate-check 只讀檔案，不呼叫 Jev 或其他外部服務（設計 §7）。
- **設定檔**：
  - 進版控的 `<project>/.claude/openspec-workflow.md`；
  - gitignored 的 `<project>/.claude/openspec-workflow.local.md`。後者有設定的 key 會覆蓋前者。
  - key 只有兩個：`gates`（`risk-based`｜`supervised`，預設 `risk-based`）和 `high_risk_paths`（glob 清單，預設空）。
- **公開 repo**：commit 訊息與 PR 說明不加 session 連結或 `Claude-Session` trailer；不寫客戶專案名。
- **staging**：一律具名 `git add <file>`，不用 `-A`。
- **eval**：`evals*/` 整個目錄被 gitignore，只在本機用，**不 commit**。

## Review Focus

1. **CRLF 檔案**：在 Windows 上 checkout 的 proposal 和 spec 會有 `\r`，標題比對要先正規化，否則 `## MODIFIED Requirements\r` 漏判，該停卻沒停。→ Task 1 `crlf` 測試。
2. **範例文字裡的 `[needs user]`**：HTML 註解或 code fence 裡的 `[needs user]` 是範例，不是待決事項，不能讓它觸發停。→ Task 1 `needs-user-in-comment` 測試。
3. **設定值打錯**：`gates: risk_based` 這類拼錯的值，要判為停並說明理由，不能默默當成 `risk-based`。→ Task 1 `settings-typo` 測試。
4. **`## Impact` 的路徑寫法不一**：反引號、開頭的 `./`、沒有反引號的純路徑，都要能比對 `high_risk_paths`。→ Task 1 `impact-path-forms` 測試。
5. **change 目錄不對**：不在 `openspec/changes/` 底下，或缺 `proposal.md`，要 exit 1，不能當成「沒有觸發條件 → 繼續」。→ Task 1 `bad-change-dir` 測試。

---

### 前置（不是 task，執行前做一次）

- [x] 開分支：`git switch -c feat/openspec-workflow-3-gates`
- [x] 建立帳本：`/scope-ledger:scope init "依 docs/openspec-workflow-3-gates-design-2026-11-10.md 實作 openspec-superpowers-workflow 3.0 確認點"`
- [x] 跑一次基準測試：`for t in plugins/openspec-superpowers-workflow/tests/*.test.sh; do bash "$t" > /dev/null 2>&1; echo "$t rc=$?"; done`。預期每個都是 `rc=0`；若有不是 0 的，先記下，它不屬於本計畫。

### Task 1: `gate-check.cjs` 與測試套件

**Files:**
- Create: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/gate-check.cjs`
- Create: `plugins/openspec-superpowers-workflow/tests/gate-check.test.sh`

**Interfaces:**
- Consumes: 無（獨立模組；可參考 `reconcile-check.cjs:37` 讀檔時正規化 CRLF 的寫法）。
- Produces:
  - CLI：`node gate-check.cjs <p1|p2> <change-dir>`。
    - stdout 第一行是 `stop` 或 `proceed`；之後每個理由一行，格式 `- <reason-id>: <說明>`。
    - exit `10`／`0`／`1`。
  - `module.exports = { readSettings, checkP1, checkP2 }`。`require` 時不執行 main，沿用 `validate-openspec-workflow.cjs` 的做法。
    - `readSettings(projectRoot) → { gates: 'risk-based'|'supervised', highRiskPaths: string[], error: string|null }`
    - `checkP1(changeDir, settings) → { stop: boolean, reasons: {id: string, detail: string}[] }`
    - `checkP2(changeDir, settings) → 同上`
  - P1 的 reason id：`supervised`、`settings-unreadable`、`no-decisions-section`、`needs-user`、`breaking`、`delta-modified`、`high-risk-path`。
  - P2 的 reason id：`supervised`、`settings-unreadable`、`design-needs-user`。

**判定規則**（照設計 §4.1、§4.2，並固定以下細節）：
- **專案根目錄**：change 目錄往上兩層必須是 `openspec/changes`，否則 exit 1，訊息 `not under openspec/changes`。
- **proposal**：`proposal.md` 不存在 → exit 1。
- **正規化**：所有讀進來的文字先把 `\r\n` 換成 `\n`；掃 `[needs user]` 前先移除 `<!-- … -->` 註解和 ``` 圍起來的 code fence。
- **`## Decisions` 段**：標題符合 `/^##\s+Decisions\b/im`；段落範圍到下一個 `^## ` 為止。
- **`needs-user`**：`## Decisions` 段內有一行符合 `/^\s*[-*]\s*\[needs user\]/i`。`design-needs-user` 用同一個 regex，掃 design.md 的 `## Open Questions` 段。
- **`breaking`**：proposal 符合 `/\bBREAKING\b/`。
- **`delta-modified`**：`specs/**/spec.md` 任一檔符合 `/^##\s+(MODIFIED|REMOVED|RENAMED)\s+Requirements/m`；detail 列出命中的標題種類。
- **`high-risk-path`**：從 `## Impact` 段抽出含 `/` 的 token（去掉反引號和開頭的 `./`），和每個 glob 比對。glob 轉 regex：`**` → `.*`、`*` → `[^/]*`、`?` → `[^/]`，其餘字元跳脫，整串錨定。
- **設定檔 frontmatter**：只解析 `gates: <值>` 和 `high_risk_paths:` 底下的 `  - <glob>` 行。`gates` 出現 `risk-based`、`supervised` 以外的值 → `error` 非 null。

- [x] **Step 1: 寫失敗的測試** `tests/gate-check.test.sh`
  - 結構照抄 `reconcile-check.test.sh`：helper `eq`、`has`、`make_change`、`mktemp -d` 加 `trap`、`MIN` 下限在案例清單之外計算。
  - `make_change <root> <name>` 建一個 P1 會「繼續」的 change：proposal 只有 ADDED delta，有 `## Decisions` 段且只有 `[default]` 項。
  - 案例：**每個 reason id 至少兩個不同的觸發輸入**，另加 Review Focus 的 5 個案例：

| 案例 | 期望 |
|---|---|
| `proceed-baseline` | exit 0，第一行 `proceed` |
| `supervised`：committed 設定 `gates: supervised` | 10，`- supervised` |
| `supervised-local-overrides`：committed `risk-based`、local `supervised` | 10 |
| `local-risk-based-overrides`：committed `supervised`、local `risk-based` | 0 |
| `settings-typo`：`gates: risk_based` | 10，`- settings-unreadable` |
| `settings-garbage`：frontmatter 沒有結尾的 `---` | 10，`- settings-unreadable` |
| `no-decisions-section` ×2：沒有該段；只有 `## Decision`（單數） | 10 |
| `needs-user` ×2：`- [needs user] …`；`* [Needs User] …` | 10 |
| `needs-user-in-comment`：只出現在 `<!-- -->` 裡，以及只出現在 code fence 裡 | 0 |
| `breaking` ×2：`**BREAKING**`；行內 `BREAKING change` | 10 |
| `delta-modified` ×3：MODIFIED；REMOVED；RENAMED（分別放在兩個 capability 目錄） | 10，detail 含該標題 |
| `crlf`：spec 用 CRLF 寫 `## MODIFIED Requirements` | 10 |
| `impact-path-forms`：glob `src/auth/**`；Impact 分別寫成 `` `src/auth/login.ts` ``、`./src/auth/x.ts`、`src/auth/y.ts` | 三個都 10 |
| `impact-no-match`：路徑在 glob 之外 | 0 |
| `bad-change-dir` ×2：不在 `openspec/changes` 底下；缺 `proposal.md` | 1 |
| `p2-needs-user` ×2：Open Questions 段內 `[needs user]`，大小寫各一 | 10 |
| `p2-defaults-only`：只有 `[default]` | 0 |
| `p2-no-open-questions`：design 沒有該段 | 0 |
| `require-no-main`：`node -e 'require(...)'` 印 `typeof checkP1` | `function`，而且不印 usage |

  - `MIN` 設為實際斷言數。

- [x] **Step 2: 跑測試確認失敗**
  Run: `bash plugins/openspec-superpowers-workflow/tests/gate-check.test.sh > "$TMPDIR/gc.log"; echo rc=$?`（判定只看 `$?`，log 只看摘要）
  Expected: `rc=1`，失敗原因是找不到 `gate-check.cjs`。

- [x] **Step 3: 實作 `gate-check.cjs`**，依上面的 Interfaces 和判定規則。檔頭註解寫明：exit code 契約、偏向問人的理由、設計文件路徑、測試路徑。

- [x] **Step 4: 跑測試確認通過**
  Run: 同 Step 2。Expected: `rc=0`，摘要 `gate-check: N passed, 0 failed`，且 N ≥ MIN。

- [x] **Step 5: 突變測試**（確認測試真的守住執行路徑，不是只測資料）
  逐一對 `gate-check.cjs` 做下列突變，每次跑套件，**每個突變都要 `rc≠0`**，跑完立刻還原（`git checkout -- <file>` 或 `git stash`）：
  1. 讓 `needs-user` 的判斷永遠為 false；
  2. 讓 `breaking` 的判斷永遠為 false；
  3. 移除 `delta-modified` 裡的 `RENAMED`；
  4. 移除 CRLF 正規化；
  5. 移除註解與 code fence 的剝除；
  6. `settings-unreadable` 改成回 `proceed`；
  7. 讓 bad-change-dir 回 0。

  把七個 rc 記在 commit 訊息裡。

- [x] **Step 6: 跑全部套件**
  Run: 前置裡的 for 迴圈。Expected: 全部 `rc=0`（CI 會自動列舉新的 `gate-check.test.sh`，見 `.github/workflows/validate.yml:42-46`）。

- [x] **Step 7: Commit**
```bash
git add plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/gate-check.cjs plugins/openspec-superpowers-workflow/tests/gate-check.test.sh
git commit -m "openspec-superpowers-workflow: gate-check.cjs decides whether P1/P2 stop for the user"
```

### Task 2: skill 文件改用 gate-check 作為轉換條件

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/phases.md`。範圍：
  - Phase 1 的 Quality gate（`:100-103`）；
  - Phase 2 的 Trigger 與提問預算（`:109-120`）；
  - Phase 3 的 Quality gate（`:165`）、Phase 4 的 Trigger（`:171`）；
  - Phase 5 收斂段（`:248`）；
  - Phase 6a（`:266-277`）、Step 6b（`:279-281`）、Step 6b5 首句（`:285`）。
- Modify: `.../SKILL.md:38`（Phase map 的 P1 列）、`:58`（How-to 第 3 點）
- Modify: `.../OUTPUT-CONTRACTS.md:28`、`:72`、`:88`，並新增 proposal 的 `## Decisions` 契約
- Modify: `.../PHASE-IDENTIFICATION.md`（Phase 1→2、2→3、3→4 的轉換條件）
- Modify: `plugins/openspec-superpowers-workflow/tests/skill-docs.test.sh`（新增結構斷言）

**Interfaces:**
- Consumes: Task 1 的 CLI 與 reason id。

**文件要寫進去的決定**（照設計 §3、§4，措辭由實作者寫）：
- **Phase 1 結尾**：
  - 寫好 proposal 與 specs，並加 `## Decisions` 段（即使沒有待決事項，也寫「無」）。
  - 跑 `node ${CLAUDE_PLUGIN_ROOT}/skills/openspec-superpowers-workflow/validators/gate-check.cjs p1 openspec/changes/<name>`。
  - **exit 0**：回覆列出採用的 `[default]` 與理由，在同一輪接著進 Phase 2。
  - **exit 10 或 1**：派 `model: "opus"` 的子代理做獨立審查（三個問題照設計 §4.1），把審查結果併進 `## Decisions`，連同 gate-check 的理由一起呈現，然後**停下等核准**。
  - 作者和審查者列為 `[needs user]` 的項目，不得改成 `[default]`。
- **Phase 2**：
  - 提問預算不變。
  - 會改變 WHAT 的問題，在 `## Open Questions` 標 `[needs user]`，其餘標 `[default]`。
  - 寫完 design 後跑 `gate-check p2`：0 → 進 Phase 3；10 或 1 → 先做 opus 審查（對照 `DESIGN-RED-FLAGS.md`），再停下。
  - Phase 3 的 Trigger 改成「`gate-check p2` 回 0，或使用者核准 Phase 2」。
- **Phase 3**：刪掉 Quality gate。改為 tasks.md 寫完後跑 `validate-openspec-workflow.cjs`，通過就進 Phase 4。Phase 4 的 Trigger 改成「Phase 3 的 validator 通過」。
- **Phase 5**：新增「收斂建議」。三個條件照設計 §4.4；建議時只問一題。宣告 `final` 仍只由使用者做，原文 `:248` 保留。
- **Phase 6a**：新增一條規則：把 `## Decisions` 改寫成最終決定，拿掉 `[needs user]`／`[default]` 標記和 `reviewed:` 註解。
- **Step 6b**：改成「把改寫摘要（每個 Y 項落在哪一份檔案）寫進回覆和歸檔 PR 的說明；不停，直接進 6b5」。
- **`supervised`**：在 Phase 1 前面加一段說明兩種模式和兩個設定檔的位置；`supervised` 時 gate-check 一律回 10，所以文件不需要另外寫一條路徑。
- **OUTPUT-CONTRACTS**：`使用者已審核` 改成 `gate-check 通過，或使用者已核准`；tasks.md 那列改成 `validator 通過`。

- [x] **Step 1: 寫失敗的測試**：在 `skill-docs.test.sh` 加三條斷言：
  - `phases.md` 用到的每個 `validators/*.cjs` 檔名都存在（抽取規則：`` `?validators/([a-z-]+\.cjs) ``）；
  - `phases.md` 含 `gate-check.cjs p1` 與 `gate-check.cjs p2`；
  - `phases.md` 不再含 `Do NOT proceed to Phase 2 until user explicitly approves`。

  `MIN` 調成新的斷言數。
- [x] **Step 2: 跑測試確認失敗**
  Run: `bash plugins/openspec-superpowers-workflow/tests/skill-docs.test.sh > "$TMPDIR/sd.log"; echo rc=$?`
  Expected: `rc=1`（後兩條失敗）。
- [x] **Step 3: 依上面的決定修改五份文件**。改完 grep 一次舊措辭：`command grep -rn -E 'User reviews task breakdown|User approves Phase [23]|Present the rewritten spec files' plugins/openspec-superpowers-workflow/skills`，預期沒有任何命中。
- [x] **Step 4: 跑測試確認通過**：同 Step 2，Expected `rc=0`；再跑 `cli-claims.test.sh`，確認對 CLI 的描述沒有被改壞，Expected `rc=0`。
- [x] **Step 5: Commit**
```bash
git add plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/{phases,SKILL,OUTPUT-CONTRACTS,PHASE-IDENTIFICATION}.md plugins/openspec-superpowers-workflow/tests/skill-docs.test.sh
git commit -m "openspec-superpowers-workflow: phases stop on gate-check, P3 and P6b no longer wait"
```

### Task 3: 本機 eval（不 commit）

**Files:**
- Create（gitignored）：
  - `plugins/openspec-superpowers-workflow/evals-design/05-p1-trigger-stops/`
  - `.../06-p1-no-trigger-proceeds/`
  - `.../07-p3-no-stop/`

**Interfaces:**
- Consumes: Task 2 的 skill 行為。

- [x] **Step 1: 先讀** `~/.claude/refs/plugin-eval.md`，並以 `evals-design/03-add-report-archive/` 為範本（prompt 的 frontmatter、「空 checkout」前言、grader 寫法）。
- [x] **Step 2: 寫三個 case**：

| case | prompt 給的內容 | graders |
|---|---|---|
| 05 | proposal 與 spec delta 含 `## MODIFIED Requirements`，要 agent「完成 Phase 1」 | `file_exists design.md: false`（weight 2）；llm：回覆說明停下的理由，並請使用者核准 |
| 06 | ADDED-only，`## Decisions` 只有 `[default]` 項，要 agent「完成 Phase 1」 | `file_exists design.md: true`（weight 2）；llm：回覆列出採用的預設，沒有要求核准 |
| 07 | 已核准的 design.md，要 agent「拆任務」 | `file_exists tasks.md: true`；llm：回覆沒有要求使用者審 tasks.md，並表示接著進 Phase 4 |

- [x] **Step 3: 跑** `claude plugin eval plugins/openspec-superpowers-workflow/evals-design --ablation with-without --judge-model sonnet --allow-tools Write Edit`，結果落檔，判定讀 exit code。
  Expected：05、06、07 的 with 分數高於 without；01–04 的 with 分數不低於 2026-11-09 的結果（`evals-design/results/2026-11-09T02-53-41-306Z/aggregate-result.json`）。若 Δ = 0、全部 0 分或 `$0.00`，先懷疑 eval 本身壞了。
- [x] **Step 4: 跑** `evals-phase6/` 和 `evals/`，同樣的參數。Expected：01–08 不退步（`evals/` 的基準見記憶「openspec workflow eval suite」：1.5.0 版 8 題 with 全 1.00）。
- [x] **Step 5:** 不 commit。把 Δ 寫進 Task 4 的 CHANGELOG 條目。

### Task 4: 版本、CHANGELOG、README

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/.claude-plugin/plugin.json`（version、description 加一句 gate-check）
- Modify: `.claude-plugin/marketplace.json`（頂層 `1.16.0`；條目 `3.0.0`；description 加一句）
- Modify: `plugins/openspec-superpowers-workflow/CHANGELOG.md`（新增 `## [3.0.0] - <合併日>`，分 Changed／Added／Tests 三段；寫明 breaking：預設不再於 P2、P3、P6b 停，`gates: supervised` 可恢復舊行為）
- Modify: `plugins/openspec-superpowers-workflow/README.md`（確認點與設定檔一節）
- Modify: 根目錄 `README.md`、`README.zh-TW.md`：只在它們描述到確認點時才改；先 grep 確認

**Interfaces:**
- Consumes: Task 1 的 reason id、Task 3 的 Δ。

- [x] **Step 1:** `command grep -rn -F '2.2.1' --include='*.json' --include='*.md' . | command grep -v node_modules` 列出所有舊版本字串，逐一判斷是否要改（CHANGELOG 的歷史條目不改）。
- [x] **Step 2:** 修改上列檔案。
- [x] **Step 3: 驗證**
  - Run: `jq -r '.version' plugins/openspec-superpowers-workflow/.claude-plugin/plugin.json; jq -r '.version, (.plugins[] | select(.name=="openspec-superpowers-workflow") | .version)' .claude-plugin/marketplace.json`
    Expected: `3.0.0`、`1.16.0`、`3.0.0`。
  - Run: `node scripts/validate-fixtures.cjs; echo rc=$?`，Expected `rc=0`。再跑全部套件，Expected 全部 `rc=0`。
- [x] **Step 4: Commit**
```bash
git add plugins/openspec-superpowers-workflow/.claude-plugin/plugin.json .claude-plugin/marketplace.json plugins/openspec-superpowers-workflow/CHANGELOG.md plugins/openspec-superpowers-workflow/README.md docs/openspec-hitl-gate-analysis-2026-11-10.md docs/openspec-workflow-3-gates-design-2026-11-10.md docs/openspec-workflow-3-gates-plan-2026-11-10.md
git commit -m "openspec-superpowers-workflow 3.0.0: gates stop on facts (marketplace 1.16.0)"
```

### 收尾（不是 task）

- [x] 對整個分支 diff 做 `/simplify`，重跑全部套件。
- [x] commit 前自審：`/review-branch` 加 `codex_review`（scope: working-tree）。finding 先進 scope-ledger 帳本再處理。
- [x] push 前跑 `/security-review`；開 PR（不附 session 連結）；跟到 CI 綠燈。
- [x] 合併後：依記憶「計畫收尾時回填勾選」，在本計畫全部勾選並加狀態行。

---

## 自我檢查紀錄

- **設計覆蓋**：
  - §3、§4.1–4.6 → Task 1、2；
  - §5 的檔案表 → Task 1、2、4（eval 在 Task 3）；
  - §6 出貨前驗證 → Task 1 Step 5、Task 3；上線後量測不在本計畫，合併 4–6 週後另做；
  - §7（jev skill 落點）→ 使用者 2026-11-10 決定拿掉，不實作；等用真實 review-notes 量過效益再議；
  - §9、§10 的決定 → Global Constraints 與 Task 2。
- **執行方式**：使用者選 Native（superpowers:executing-plans）。
- **型別一致**：reason id 只在 Task 1 定義，Task 2 沿用同一組名稱。
- **延後**：reconcile-check 對 Phase 6a 殘留的 `[needs user]` 標記加 warn，設計沒有要求，不做；若之後有需要，列入 follow-ups。
