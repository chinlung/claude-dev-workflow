# Audit / Review / Fix 工作流程說明（跨專案版）

> **Trigger 條件**：
> - 對高風險域 PR 做 rigorous review 時（auth / crypto / payment / IaC / parser / LLM context 組裝）
> - 需要量化決策 + 自動修復閘門 + 對抗式驗證紀錄時
> - 想批次自動審 + 修一輪而非互動式跑 `/code-review` → `/code-audit-rigor`
>
> **不適用**：routine PR review、style fix、單行修正——用 `/review-branch` 即可。

---

## 1. 跨專案重用方式

### 最簡：`/audit-review-fix` 指令（推薦）

任意專案 session 直接打 `/audit-review-fix [base-ref] [dry] [旗標…]`——命令（本 plugin 的 `commands/audit-review-fix.md`）會自動注入當天日期、解析參數、做前置檢查、Read 本腳本（`${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js`）並呼叫 Workflow。`today` 不用手動帶。

旗標：`--profile cheap|thorough|ci`（預設組合）、`--votes N`（多票對抗式，rigor↑）、`--focus <glob>`（限定路徑，cost↓）、`--test-cmd "<cmd>"`（覆寫測試指令）、`--model <tier>`（降階）、`--yes`（非互動）。範例：
- `/audit-review-fix` — 預設 origin/main 審 + 修
- `/audit-review-fix origin/develop dry` — 只審不修
- `/audit-review-fix --profile thorough --focus 'app/Auth/**'` — Auth 模組 3 票對抗式
- `/audit-review-fix --profile ci --yes` — CI 閘門：只報不修、非互動

### 直接從 refs 載入並執行（命令不可用時的手動後備）

在任何專案 session 中：

```
1. Read ${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js
2. 把內容當作 script 參數傳給 Workflow tool：
   Workflow({
     script: <檔案內容>,
     args: { baseRef: 'origin/main', autoFix: true, today: 'YYYY-MM-DD' }
   })
```

**重要**：`today` 必傳——Workflow tool 禁用 `Date.now() / new Date()`（會破壞 resume），預設 hardcoded 是過時日期。

### 從既有 run 續跑

```
Workflow({
  scriptPath: '<session-id>/workflows/scripts/audit-review-fix-wf_*.js',
  resumeFromRunId: 'wf_*'
})
```

同 session、同 script、同 args → 已完成階段秒回快取。

---

## 2. 什麼時候用這套流程

| 場景 | 用什麼 |
|---|---|
| 一般 PR 自審、style check | `/review-branch`（既有），輕量 |
| 高風險域 PR（auth / crypto / payment / IaC / parser / LLM context 組裝） | **本工作流程**（量化 + 對抗式） |
| 需要逐項 finding 紀錄與 dismissal 論證 | **本工作流程**（強制 cross-references + steel-manning） |
| Routine 小 fix | 一般 commit 即可，不必跑此流程 |

判斷標準（user CLAUDE.md「漏抓真 bug 的代價遠高於誤判」）：
- 漏抓一個 bug 的代價 > 5-30 分鐘 × N 個 false positive 投資時間 → 用本流程
- 否則用 routine flow

---

## 3. 九階段拆解

```
┌─────────────────────────────────────────────────────────────────┐
│ Scope          1 agent gather diff (baseRef...HEAD + worktree)  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Baseline       1 agent snapshot pre-existing test failures      │
│                (僅 autoFix=true 跑；Verify Fix 據此只算新增      │
│                 regression，避免把既有 failure 誤判為本次破壞)   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Review         9 angles parallel pipeline:                      │
│                  A. line-by-line     F. reuse                    │
│                  B. removed-behavior G. simplification           │
│                  C. cross-file       H. efficiency               │
│                  D. language-pitfall I. altitude                 │
│                  E. wrapper-proxy                                 │
│                each angle: up to 6 candidate findings            │
└─────────────────────────────────────────────────────────────────┘
                              ↓ (pipeline, no barrier — verify happens
                                 as each angle finishes finding)
┌─────────────────────────────────────────────────────────────────┐
│ Verify         per-candidate adversarial verifier × votes 票    │
│                  vote: CONFIRMED / PLAUSIBLE / REFUTED          │
│                  必須附 crossReferences (file:line)              │
│                多數票 REFUTED 才 drop（recall；votes>1 套 lens） │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Sweep          fresh reviewer 找前 9 angles 漏的：              │
│                  - moved code dropping guard                    │
│                  - setup/teardown asymmetry                     │
│                  - symmetry violations                          │
│                  - boy-scout opportunities                      │
│                + verify any new sweep findings                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Triage         EV math 自動 DISMISS：                           │
│                  EV = conf × points − (1-conf) × 2 × points     │
│                  EV < 0 → DISMISS（67% 信心門檻）                │
│                剩下的進 triage agent 分類：                     │
│                  - MUST_FIX                                     │
│                  - BOY_SCOUT_FIX  ←  不可全盤拒絕 pre-existing   │
│                  - DEFER_OUT_OF_SCOPE                           │
│                  - DISMISS                                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Fix            自動修復閘門（deterministic JS，不交給 agent）：  │
│                  MUST_FIX     + !requiresUserDecision + <100 LOC│
│                  BOY_SCOUT    + !requiresUserDecision + <50 LOC │
│                                + behaviorChangeRisk='none'      │
│                同 file::line dedup：只修最高嚴重度者，sibling   │
│                  進 Skipped（verify/report 仍保留全部 finding） │
│                sequential apply（避免 file conflict）           │
│                每修必附測試（contract test that fails w/o fix） │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Verify Fix     framework-agnostic test runner：                 │
│                  - PHP/Laravel: php artisan test + pint         │
│                  - JS/TS: npm test + prettier                   │
│                  - Python: pytest + ruff                        │
│                有 baseline：比對失敗鍵 + 失敗數，只有「新增      │
│                key 或失敗數上升」才算 regression（涵蓋 jest      │
│                檔案級 FAIL <file> 同檔新失敗）；無 baseline 才   │
│                退回 "Tests: N failed" regex（best-effort）       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Report         Markdown → <project>/audits/workflow-audit-DATE.md│
│                Sections: Executive / Scope / Applied / Required │
│                           / Deferred / Dismissed / Tests / Reco  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 參數說明

| arg | 預設 | 說明 |
|---|---|---|
| `baseRef` | `origin/main` | git diff 對照基準 |
| `autoFix` | `true` | `false` 則只審不修，所有 finding 進 report |
| `today` | `'2026-05-29'` (hardcoded) | **必傳**正確日期，否則報告檔名錯誤 |
| `model` | （省略）| 傳 `'haiku'`/`'sonnet'`/`'opus'`/`'fable'` → 所有 agent 統一降階壓成本；省略 ≡ 沿用 session model。⚠️ 降階犧牲 recall，高風險域慎用 |
| `votes` | `1` | 每個 finding 跑 N 個獨立對抗式 verifier，多數 REFUTED 才 drop（recall mode）。**rigor↑**——auth/payment/crypto 建議 `3`。N>1 每票套不同 lens；verify 成本約 ×N |
| `focus` | （省略）| git pathspec（如 `'app/Auth/**'`）。只審符合路徑的 diff——大 PR 省 token + 範圍紀律。透過 `git diff … -- <focus>` 套用 |
| `testCmd` | （省略）| 覆寫測試指令（如 `'make test'`）。Baseline 與 Verify-Fix 跑指定指令、不 auto-detect；非標準 runner 必備，否則兩階段降級 |
| `angles` | `9` | 只跑前 N 個審查角度（A-I 已按 recall 排序）。**cost↓**，少角度=少 recall。clamp 到 [1,9]（`0` 也夾成 1） |
| `sweep` | `true` | `false`（`--no-sweep`）跳過 Sweep 補漏階段。**cost↓** ~7 agent，代價是放棄補抓第一輪漏掉的 |
| `keepAll` | `false` | `true`（`--keep-all`）關閉 EV 機械式自動 dismiss，low-EV 改交 triage agent。**rigor↑** |
| `maxFixLoc` | `∞` | 自動修 LOC 上限（與既有 100/50 取 min），超過者改進 user review（不丟）。保守自動修 |

### 常見組合

**完整自動審 + 修**：
```js
{ baseRef: 'origin/main', autoFix: true, today: '2026-06-15' }
```

**只審不修（dry run）**：
```js
{ autoFix: false, today: '2026-06-15' }
```

**審 PR feature branch**：
```js
{ baseRef: 'origin/feature/foo-base', autoFix: false, today: '2026-06-15' }
```

---

## 5. 回傳結構與 status 對應

Workflow 回傳物件；workflow 本身只寫 Markdown 報告到 `audits/`，不會自動寫 JSON。若需要可驗證 artifact，將下方 raw Workflow return 原樣寫入 `audit-review-fix-result.json`（schema: `${CLAUDE_PLUGIN_ROOT}/schema/audit-review-fix-result.schema.json` 同時支援 raw return 與 normalized `summary/items` 形狀）。驗證方式：

```bash
node ${CLAUDE_PLUGIN_ROOT}/validators/validate-audit-review-fix-result.cjs audit-review-fix-result.json
```

`status` 枚舉與 workflow 狀態來源嚴格對齊——`computeStatus()` 產生前五種狀態，`EMPTY_DIFF` 由 Scope 中止路徑直接回傳；validator 會把 raw return 正規化成 `summary/items` 後檢查 status/count 組合：

```js
{
  status: 'CLEAN' | 'READY_FOR_COMMIT' | 'REQUIRES_USER_REVIEW' | 'REQUIRES_FOLLOW_UP' | 'TESTS_FAILED' | 'EMPTY_DIFF',
  reportPath: 'audits/workflow-audit-YYYY-MM-DD.md',
  testsPass: boolean,
  counts: { totalReviewed, applied, skipped, userReviewRequired, deferred, dismissed },
  applied: [{ id, file, summary, fixSummary, filesModified, testsAdded }],
  userReviewRequired: [{ id, file, severity, summary, reason }],
  deferred: [{ id, file, severity, summary, reason }],
  skipped: [{ id, file, severity, summary, skipReason }],
}
```

| status | 意義 | 下一步 |
|---|---|---|
| `CLEAN` | 找不到應修項目 | 直接 commit |
| `READY_FOR_COMMIT` | 修復完成、測試通過、無人類待辦 | review applied 後 commit |
| `REQUIRES_USER_REVIEW` | 有 MUST_FIX 觸及 public API / schema / 多種可行解法，**或**有 skipped（agent 判定不安全拒修 / dry-run 未修）| 逐項人工決策 |
| `REQUIRES_FOLLOW_UP` | 僅有 DEFER_OUT_OF_SCOPE（真 bug 但結構性大，不屬本次 PR），無待修/待審項 | 將 deferred 項目開成後續 PR/issue |
| `TESTS_FAILED` | 修復後測試失敗 | 不可 commit；檢查 applied 並決定 rollback 或進一步修 |
| `EMPTY_DIFF` | 沒有變動 | 無事可做 |

---

## 6. Token 預算與成本

預估 agent 呼叫數：
- Baseline: 1（僅 autoFix=true 時）
- 9 finders × 6 candidates × 1 verifier ≈ **63**
- Sweep: 1 + ~6 verifiers ≈ **7**
- Triage: ~10（EV-positive 才走 triage agent）
- Fix: 0-5（看 eligible 數）
- Verify Fix: 1
- Report: 1

**總計 ~86 agent calls**，預估 ~400k tokens（依 diff 大小）。

要壓 budget（由效果大到小）：
1. `--focus <glob>` 縮小審查範圍——大 PR 最有效，直接砍 diff 大小
2. `--angles N`（減審查角度）+ `--no-sweep`（跳補漏）——直接砍 agent 數
3. `--model haiku`（或 `--profile cheap` = haiku + angles 5 + no-sweep）統一降階；亦可 session 級 `/model`。⚠️ 犧牲 recall，高風險域慎用
4. `autoFix:false`（或 `dry`）跳過 Fix + Verify Fix 兩階段

反向要**加 rigor**（不在乎成本）：`--votes 3` 多票對抗式 + `--keep-all` 關自動 dismiss（或 `--profile thorough`）。

---

## 7. 紀律檢查清單

採納任何 finding 前（手動或 workflow 都適用）：

- [ ] **親自 Read 被指控的程式碼**（不靠 diff 縮略）
- [ ] **問自己「我真的讀了，還是在猜？」**——猜的就先 Read 再說
- [ ] **附 `file:line` 引用**——空引用直接駁回（hallucination 預警）
- [ ] **STRIDE + CWE 標籤**（security finding 必填）
- [ ] **算 EV**：`EV = conf × points − (1-conf) × 2 × points`，< 0 即 DISMISS
- [ ] **Steel-man 反向**：framework 是否已防護？呼叫鏈上游是否已守衛？
- [ ] **多 agent 共識不算驗證**：n 個 agent 同向錯誤 ≠ 真相

修復 + 提交前：

- [ ] **每個修復附測試契約**（test 必須能在沒修復時失敗）
- [ ] **跑全套測試** → 確認零迴歸
- [ ] **跑 formatter**（依語言選 Pint / Prettier / Ruff）
- [ ] **跑 PR 範圍測試**（static review 不跑測試會漏型別錯誤）
- [ ] **Commit message 寫「為什麼」非「做了什麼」**

---

## 8. Workflow 不會做什麼

| 不做 | 原因 |
|---|---|
| 自動 commit | 太危險；commit message 是「為什麼」的歷史紀錄，應該人類寫 |
| 自動 push | 同上 |
| 修觸及 public API / schema 的 finding | 標為 `requiresUserDecision`，退回人類 |
| 修 `behaviorChangeRisk != 'none'` 的 finding | 即使是 boy-scout 範疇也退回 |
| 修 ≥ 50 LOC 的 boy-scout finding | 退回 |
| 修 ≥ 100 LOC 的 MUST_FIX | 退回（這通常代表需要拆 PR） |
| Ops 工程（health check / monitoring / heartbeat） | 標為 `DEFER_OUT_OF_SCOPE` |
| 改變相依套件 | 不會碰 composer.json / package.json |

---

## 9. 設計來源

蒸餾自既有工具：
- `/code-review --xhigh` 的 9-angle 找尋 + 1-vote verify pattern
- `/security-review` 的 STRIDE + 信心數字化
- `/code-audit-rigor` 的 5 原則 + 4 框架（EV math + STRIDE+CWE + score calibration + mandatory crossReferences）
- user CLAUDE.md「漏抓真 bug 的代價遠高於誤判」+ boy-scout 條件 + 測試強制
- 2026-05-29 NewebPay state machine 修復實戰中發現「pre-existing 不可全盤拒絕」這個校正

---

## 10. Cross-reference

- `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js` — workflow script 本體（隨本 plugin 發佈）
- （外部選讀，未隨本 plugin 發佈）作者個人 `refs/workflow-gotchas.md` — Workflow tool 深度坑（寫動態 budget 迴圈 / 巢狀 workflow / agent 內呼叫外部能力 / retry & resume 時讀）
- （外部選讀）使用者級 `CLAUDE.md` — user 級紀律（boy-scout 條件、code review 規則）
- 既有 plugin commands（觸發手動逐步流程）：
  - `/review-branch` — routine 兩輪審
  - `/pr-review-toolkit:review-pr` — GitHub PR review
  - `/code-audit-rigor:code-audit-rigor` — 量化框架單獨使用
  - `/commit-commands:commit` — 單純 commit
  - `/commit-commands:commit-push-pr` — commit + push + open PR
