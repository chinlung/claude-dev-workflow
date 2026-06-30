---
description: "高風險域 PR 的對抗式審查 + 安全閘門自動修 workflow（9-angle review + EV triage + 測試驗證 + 報告）。使用方式：/audit-review-fix [base-ref] [dry] [--profile cheap|thorough|ci] [--votes N] [--focus <glob>] [--angles N] [--no-sweep] [--keep-all] [--max-fix-loc N] [--test-cmd <cmd>] [--model <tier>] [--yes]"
argument-hint: "[base-ref] [dry] [--profile …] [--votes N] [--angles N] [--no-sweep] [--yes]"
allowed-tools: Bash(date:*)
---

啟動 audit-review-fix workflow——給**高風險域 PR**（auth / crypto / payment / IaC / untrusted-input parser / LLM context 組裝）的重武器，一次約 86 agent / ~400k tokens。routine PR 自審請改用 `/review-branch`，別動用這把。

今天是 !`date +%Y-%m-%d`（把這個值當作 `today` 參數，勿手動猜——Workflow 禁用 `Date.now()`，不帶會讓報告檔名錯）。

## 步驟

### 1. 解析參數 `$ARGUMENTS`
- 第一個非旗標 token → `baseRef`（預設 `origin/main`）
- 出現 `dry` / `--dry-run` / `--dry` → `autoFix: false`（只審不修，所有 finding 進報告）；否則 `autoFix: true`
- 出現 `--yes` / `-y` → **非互動模式**：跳過下方所有「軟性確認/詢問」直接啟動（hard error 仍會擋）。注意：**無法**跳過 Workflow tool 自身的權限對話框（那是 harness 層、命令不能繞）
- 出現 `--model <tier>`（`haiku` / `sonnet` / `opus` / `fable`）→ `args.model = <tier>`，**所有 agent 降階壓成本**；不給則沿用 session model。⚠️ 降階犧牲 recall——高風險域審查（本命令的本職）慎用，建議只在 dry-run 探勘或重跑時用
- 出現 `--votes N`（整數 ≥1，預設 1）→ `args.votes = N`：每個 finding 跑 N 個獨立對抗式 verifier，**多數票 REFUTED 才 drop**。**rigor↑ 旋鈕**——auth/payment/crypto 等建議 `3`；routine 用 1。N>1 時每票套不同 lens（correctness / guard-chain / reproduce），verify 階段成本約 ×N
- 出現 `--focus <glob>` → `args.focus = <glob>`（git pathspec，如 `'app/Auth/**'` 或 `'app/ lib/'`）：只審符合路徑的 diff，大 PR 省 token + 範圍紀律。值含空白/萬用字元時用引號包起來
- 出現 `--test-cmd "<cmd>"` → `args.testCmd = <cmd>`：覆寫測試指令（非標準 runner，如 `make test`、monorepo 自訂 script），Baseline 與 Verify-Fix 改跑指定指令、不 auto-detect
- 出現 `--angles N`（整數，預設 9）→ `args.angles = N`：只跑前 N 個審查角度（A-I 已按 recall 排序，前段是核心 bug 角度）。**cost↓**，但少角度 = 少 recall
- 出現 `--no-sweep` → `args.sweep = false`：跳過 Sweep 補漏階段。**cost↓**（省 ~7 agent），代價是放棄「第一輪漏抓」的補抓
- 出現 `--keep-all` → `args.keepAll = true`：關閉 EV 機械式自動 dismiss，low-EV finding 改交 triage agent 判。**rigor↑**（偏執高風險域）
- 出現 `--max-fix-loc N`（整數）→ `args.maxFixLoc = N`：自動修 LOC 上限（與既有 100/50 取 min），超過者改進 user review。**保守自動修**
- 出現 `--profile <name>` → **預設組合**（**先套 profile 設定預設值，後面個別旗標覆寫之**——profile 優先順序低於明確旗標）：
  - `cheap` → `model:'haiku'` + `angles:5` + `sweep:false`（探勘 / 重跑壓成本）
  - `thorough` → `votes:3` + `keepAll:true`（高風險域 max rigor）
  - `ci` → `autoFix:false` + 非互動（等同 `dry --yes`，CI 閘門只報不修）
- `today` = 上方 date 輸出的當天日期（YYYY-MM-DD）

> **數值旗標錯誤處理**：`--votes`、`--angles`、`--max-fix-loc` 必須為有限整數；傳入非數字字串（如 `--votes foo`）、`NaN`、非有限數時，workflow 內部 `num()` helper 會退回安全預設值（`votes→1`、`angles→9`、`maxFixLoc→∞`），不會靜默崩潰或讓 finding 從結果中消失。

### 2. 前置檢查
- **Hard（不滿足一律停，`--yes` 也擋）**：在 git repo 內，且 baseRef 存在（`git rev-parse --verify <baseRef>`）。不存在 → 建議改正確 base 或 `HEAD~N`，**不要**硬跑（會空審浪費 token）
- **Soft（degrade 而非停）**：有可跑的測試指令（Laravel `php artisan test` / Node `npm test` / Python `pytest`）。沒有時 Baseline 與 Verify Fix 兩階段會降級——無 `--yes` 先告知使用者再續；有 `--yes` 直接續、僅在最終回報註明降級

### 3. 啟動 workflow
Read `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js`（`${CLAUDE_PLUGIN_ROOT}` 由 harness 展開為本 plugin 安裝路徑，機器無關），把**完整檔案內容**當 `script` 傳給 Workflow tool：

```
Workflow({
  script: <檔案完整內容>,
  args: { baseRef: <解析值>, autoFix: <解析值>, today: "<當天日期>", model: <省略或值>, votes: <省略或值>, focus: <省略或值>, testCmd: <省略或值>, angles: <省略或值>, sweep: <false 或省略>, keepAll: <true 或省略>, maxFixLoc: <省略或值> }
})
```

`model` 只在使用者帶 `--model` 時放入；省略時別塞 `undefined` 字串。Workflow 啟動會跳權限對話框顯示成本與描述，使用者可在此取消——`--yes` 也不繞過它，命令層不需另外再問。

### 4. 回報結果（依回傳 `status`）

Workflow 回傳結構化結果；workflow 本身只會用 Write tool 產出 Markdown 報告，不會自動寫 JSON。若需要可驗證 artifact，將 Workflow 回傳物件原樣寫入 `audit-review-fix-result.json`，再用 `${CLAUDE_PLUGIN_ROOT}/validators/validate-audit-review-fix-result.cjs` 驗證。schema `${CLAUDE_PLUGIN_ROOT}/schema/audit-review-fix-result.schema.json` 支援 raw Workflow return 形狀，也支援 normalized `summary/items` artifact 形狀。

`status` 枚舉（`computeStatus()` 產生前五種狀態；`EMPTY_DIFF` 由 Scope 中止路徑直接回傳）：

| status | 意義 |
|--------|------|
| `CLEAN` | 找不到應修項目 |
| `READY_FOR_COMMIT` | 修復完成、測試通過、無人類待辦 |
| `REQUIRES_USER_REVIEW` | 有 MUST_FIX 觸及 public API / schema / 多種可行解法，**或**有 skipped |
| `REQUIRES_FOLLOW_UP` | 僅有 DEFER_OUT_OF_SCOPE，無待修/待審項 |
| `TESTS_FAILED` | 修復後測試失敗，**不可 commit** |
| `EMPTY_DIFF` | 沒有變動 |

各 finding 在結構化輸出中附有 `crossReferences`（file/lines/quotedCode/note）以確保引用可驗證。可用 finding validator 逐項驗證：`node ${CLAUDE_PLUGIN_ROOT}/validators/validate-finding.cjs <finding.json>`。

依 `status` 的回報行為：
- `READY_FOR_COMMIT` → 摘要 Applied 修復；提醒人工 review 後**自行 `/commit`**（workflow 不自動 commit，commit message 該由人寫「為什麼」）
- `REQUIRES_USER_REVIEW` → 逐項列出 User Review Required + **Skipped**（agent 判定不安全拒修 / dry-run 未修）待人類決策
- `REQUIRES_FOLLOW_UP` → 列出 Deferred 項目（真 bug 但結構性大），建議開成後續 PR/issue
- `TESTS_FAILED` → 警告**不可 commit**，列出 applied 供決定 rollback 或續修
- `CLEAN` / `EMPTY_DIFF` → 告知無應修項 / 無變更

一律附上報告路徑 `audits/workflow-audit-<date>.md`。

## 續跑（中斷或改 script 後）
用首次回傳的 `scriptPath` + `resumeFromRunId` 呼叫 Workflow——同 session / 同 script / 同 args 下，已完成階段秒回快取，不重燒 token。

## 與其他審查工具的分界
- routine PR 自審 / 單行修正 → `/review-branch`
- 高風險域**互動式**逐步量化審（不要自動修）→ `/code-audit-rigor`
- 高風險域**一次跑完批次審 + 安全閘門自動修 + 報告** → 本命令
