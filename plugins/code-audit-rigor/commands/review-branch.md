---
description: "兩輪程式碼審查：第一輪產生建議清單，第二輪子代理驗證每項建議。使用方式：/review-branch [base-branch] [--focus <pathspec>]"
argument-hint: "[base-branch] [--focus <pathspec>]"
---

對當前分支相對於 `$ARGUMENTS`（預設為 main 或 master）進行兩輪程式碼審查。

## 前置：確認分支與差異（機械化清單）

1. `git branch --show-current` 確認當前分支
2. 用 `git merge-base HEAD <base-branch>` 找到分歧點
3. `git diff <merge-base>...HEAD --name-only` 取得所有變更檔案清單——**此清單是覆蓋核對表的唯一基準**（Phase 3 必須逐檔核銷），不可事後憑記憶重建。若帶 `--focus <pathspec>`（如 `--focus 'src/auth/**'`），改用 `git diff <merge-base>...HEAD --name-only -- <pathspec>`，只審符合路徑的變更——大 PR 省 token + 範圍紀律；此時覆蓋核對表的基準即為**過濾後**的清單
4. 若無 `$ARGUMENTS`（或僅提供 `--focus`），自動偵測 base branch（依序嘗試 `main`、`master`）

## 前置：解析適用審查規則（path-matched rule packs）

對清單中的檔案類型解析語言特化規則（仿 alibaba/open-code-review 分層規則鏈，first-match wins）：

1. **專案層**：`<repo>/.reviewrules/manifest.json` 若存在，優先使用
2. **使用者層**：`~/.claude/review-rules/manifest.json` 若存在
3. **內建層**：本 plugin 的規則庫 `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json`

讀取匹配到的 rule docs：每份含「Review focus」（該檔案類型該獵什麼）與「Do NOT report」suppression list（該檔案類型的已知誤報類別）。Phase 1 審查時注入這些重點；Phase 1 產生的建議若命中 suppression list，需說明為何不適用，否則不列入。

## Phase 1：產生建議清單

對所有變更檔案進行全面審查，每個建議記錄：

| 欄位 | 說明 |
|------|------|
| 檔案 | 完整檔案路徑 |
| 行號 | 問題所在行號或範圍 |
| 引用程式碼 | 問題行的**逐字引用**（quotedCode，供 Phase 2 機械驗證；憑記憶改寫視同無效） |
| 分類 | 安全性 / 邏輯錯誤 / 效能 / 風格 |
| 問題 | 問題描述 |
| 建議修復 | 具體修復方式 |

審查面向（在以下通用面向之上，套用前置步驟解析到的語言特化規則）：
- **安全性**：注入、XSS、權限繞過、敏感資料外洩
- **邏輯錯誤**：條件判斷錯誤、邊界情況遺漏、狀態不一致、級聯遺漏
- **效能**：N+1 查詢、不必要的迴圈、遺漏索引、熱路徑阻塞
- **風格**：命名不一致、死碼、重複邏輯（僅標記有實質影響的）

產出建議清單後，輸出摘要表格供使用者預覽。

## Phase 2：子代理驗證

對每個建議生成獨立子代理（可並行），每個子代理：

1. **引用錨定驗證（機械步驟，先做）**：用 Grep 在宣稱的檔案中搜尋該建議的「引用程式碼」——
   - 在宣稱行號 ±10 行內找到 → 錨定成功，續行
   - 在檔案其他位置找到 → 修正行號後重新確認問題仍成立
   - 整個檔案都找不到 → 重讀檔案一次重新引用；若支撐該建議的程式碼確實不存在，判**誤報**（記憶重建的引用）
   - （錨定是逐字文字比對，Grep 是正確工具——不要用 codegraph 做這步）
2. **讀取上下文**：問題所在函式的完整實作
3. **追蹤調用鏈**：找出所有呼叫該函式的調用者——**專案有 `.codegraph/` 索引時優先用 codegraph**（`codegraph_callers` 查調用者、`codegraph_impact` 查變更影響面；能抓到 grep 漏掉的 dynamic-dispatch 呼叫點：callback、DI、event handler）；無索引才 fallback 用 Grep 搜尋方法名
4. **檢查相關測試**：搜尋覆蓋該行為的測試檔案
5. **分析上下游依賴**：確認變更是否影響其他元件

驗證判定（每項附**信心度 0-100**——誠實估計此建議為真的機率，不要用「不確定」規避）：
- **已驗證** — 確認問題存在且建議修復正確，附上具體證據（調用者程式碼、測試缺失、依賴衝突等）
- **誤報** — 經查驗問題不存在或建議不正確，附上反駁證據（含「引用錨定失敗」這一類）

信心度 < 67% 屬**邊界情況**：不要逕自二選一，先回原始碼再讀一次，把信心推到 67% 以上或 33% 以下再判；仍卡在中間則標為邊界、在報告點出交使用者判斷（避免把「其實沒把握」硬塞進「已驗證」或「誤報」任一桶）。

## Phase 3：結構化輸出與最終報告

### 結構化輸出：`review-branch-results.json`

Phase 2 完成後，將審查結果寫入 `review-branch-results.json`，須符合以下合約（schema: `${CLAUDE_PLUGIN_ROOT}/schema/review-branch-results.schema.json`）：

```json
{
  "branch": "<branch-name>",
  "scopedFiles": [
    { "file": "src/foo.ts", "status": "reviewed" },
    { "file": "docs/bar.md", "status": "skipped", "skipReason": "純文件，無程式邏輯" }
  ],
  "suggestions": [
    {
      "file": "src/foo.ts",
      "line": 42,
      "quotedCode": "逐字引用的問題程式碼",
      "description": "問題描述",
      "severity": "HIGH"
    }
  ],
  "verifications": [
    { "id": "V-001", "verdict": "PASS", "notes": "驗證通過說明" },
    { "id": "V-002", "verdict": "FAIL", "notes": "驗證失敗說明" }
  ]
}
```

欄位合約：
- `branch`：當前分支名稱（非空字串）
- `scopedFiles`：前置步驟 3 機械清單中的**所有**檔案；`status` 為 `reviewed` 或 `skipped`；`skipped` 時必須附 `skipReason`（Coverage 核對表的機器可讀版本）
- `suggestions`：所有第一輪建議（含誤報），每項包含 `file`、`line`（整數 ≥ 1）、`quotedCode`（Phase 2 錨定驗證用的逐字引用）、`description`、`severity`（`CRITICAL|HIGH|MEDIUM|LOW|INFO`）
- `verifications`：Phase 2 每個子代理的驗證結果；`verdict` 為 `PASS|FAIL|SKIP`；可附 `notes`

寫出 JSON 後，執行驗證指令（必須通過才能進入最終 Markdown 表格）：

```bash
node ${CLAUDE_PLUGIN_ROOT}/validators/validate-review-branch-results.cjs review-branch-results.json
```

驗證失敗表示 JSON 格式不符合合約（缺欄位、型別錯誤、skipped 缺 skipReason 等），需修正後重跑，確認 `VALID` 後繼續。

接著執行覆蓋核對（coverage reconciliation）：

```bash
node ${CLAUDE_PLUGIN_ROOT}/validators/coverage-reconcile.cjs review-branch-results.json
```

此步驟驗證覆蓋完整性（超出 schema 檢查範圍）：

- `scopedFiles` 非空——有檔案在範圍內
- 無重複的 `scopedFiles` 條目
- `suggestions` 中出現的每個檔案都必須存在於 `scopedFiles`（未列入 = 覆蓋缺口）
- 所有 `skipped` 條目必須有 `skipReason`

兩個驗證都必須通過（`VALID` 和 `PASS`）才能進入最終 Markdown 表格。

### 最終 Markdown 報告

僅呈現「已驗證」的建議（`verdict: PASS`），格式為 markdown 表格：

```markdown
## 已驗證的審查建議

| # | 檔案 | 行號 | 分類 | 問題 | 修復建議 | 驗證證據 |
|---|------|------|------|------|---------|---------|
```

末尾附統計：
- 第一輪建議總數
- 已驗證數量
- 誤報數量（附簡要原因摘要，含引用錨定失敗數）

**Coverage 核對表（必附）**——對照前置步驟 3 的機械檔案清單逐檔核銷：

```markdown
## Coverage

| 檔案 | 狀態 |
|------|------|
| src/foo.ts | reviewed |
| docs/bar.md | skipped（純文件，無程式邏輯） |
```

每個清單中的檔案必須出現在 reviewed 或 skipped(原因) 其中一欄；有檔案兩欄都不在 = 審查不完整，回頭補審，不可直接交報告。

若使用者確認要修復，依分類優先順序（安全性 > 邏輯錯誤 > 效能 > 風格）逐一修復。
