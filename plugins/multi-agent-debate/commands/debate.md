---
description: 啟動多代理辯證系統，對需求進行多角度分析與辯論
argument-hint: <需求描述> [--max-rounds N] [--perspectives "角度1,角度2,角度3"]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, TodoWrite, AskUserQuestion
---

# /debate - 多代理辯證系統

啟動多代理辯證流程，透過三個不同角度的 Agent 對需求進行深度分析，並由 Critic Agent 進行批判審查，最終產出最優實踐方案。

## 任務輸入

需求描述：$ARGUMENTS

## 執行流程

### Phase 0：先行辯論查找與需求分析

#### 0a. 先行辯論查找（Prior-Debate Lookup）

在啟動新辯論前，先檢查本地運行目錄是否存在先行辯論產物：

1. 尋找當前目錄或指定路徑下的 `prior-debate.json`（或 `prior-debate-*.json`）
2. 若找到，讀取並驗證其 schema（`schema/prior-debate.schema.json`）：
   - `reuseConstraint.suppressNewFindings` **必須為 `false`**——否則拒絕使用該產物
   - `reuseConstraint.suppressNewDecisions` **必須為 `false`**——否則拒絕使用該產物
   - 確認 `topic` 與當前辯論主題相符
3. 若先行產物有效，將以下資訊注入 orchestrator prompt（**僅作為背景脈絡，不替代新分析**）：
   - 先行決策（`priorDecision`）——供角度配置參考，不可直接採納
   - 已拒絕的替代方案（`rejectedAlternatives`）——提示避免重蹈覆轍
   - 未解決的風險（`unresolvedRisks`）——**必須在本次辯論中重新審查**
   - 未覆蓋的面向（`coverage.notCovered`）——提示本次辯論重點關注
4. 若未找到先行產物，或找到但不適用（topic 不符、verdict 為 REJECTED），直接進行需求分析，不帶任何先行脈絡

**覆蓋聲明**：先行辯論資訊只改變審查重點，不壓制任何新發現或新決策。每次辯論必須獨立得出結論。

#### 0b. 需求分析與角度配置

使用 Task tool 調用 orchestrator agent：
```
Task(
  subagent_type="multi-agent-debate:orchestrator",
  prompt="需求描述：$ARGUMENTS\n\n[若有先行辯論脈絡，附加：]\n先行辯論脈絡（背景參考，不得直接採納）：\n- 先行決策：{priorDecision.selectedProposal}（信心度：{priorDecision.confidenceLevel}）\n- 已拒絕方案：{rejectedAlternatives}\n- 未解決風險（本次必須重新審查）：{unresolvedRisks}\n- 先前未覆蓋（本次需重點關注）：{coverage.notCovered}\n\n請分析需求並決定三個 Agent 的思考角度。"
)
```

等待完成後，獲取三個 Agent 的角度配置。

### Phase 1：初始方案生成（並行）

並行啟動三個 perspective agents：
```
Task(
  subagent_type="multi-agent-debate:perspective-a",
  prompt="需求描述：$ARGUMENTS\n思考角度：{角度A}\n\n請從此角度提出解決方案。",
  run_in_background=true
)

Task(
  subagent_type="multi-agent-debate:perspective-b",
  prompt="需求描述：$ARGUMENTS\n思考角度：{角度B}\n\n請從此角度提出解決方案。",
  run_in_background=true
)

Task(
  subagent_type="multi-agent-debate:perspective-c",
  prompt="需求描述：$ARGUMENTS\n思考角度：{角度C}\n\n請從此角度提出解決方案。",
  run_in_background=true
)
```

收集三個方案後，進入 Phase 2。

### Phase 2：批判審查

使用 Task tool 調用 critic agent：
```
Task(
  subagent_type="multi-agent-debate:critic",
  prompt="請審查以下三個方案並提出挑戰：\n\nAgent A 方案：{方案A}\n\nAgent B 方案：{方案B}\n\nAgent C 方案：{方案C}"
)
```

### Phase 3：反駁與修正（並行）

將 Critic 的挑戰傳遞給各 Agent 進行回應：
```
Task(
  subagent_type="multi-agent-debate:perspective-a",
  prompt="Critic 對你的挑戰：{挑戰內容}\n\n請回應挑戰並表態。",
  run_in_background=true
)
// ... 對 B 和 C 同樣處理
```

### Phase 4：共識檢查

依序檢查共識狀態，**任一條成立即視為收斂**，進入 Phase 5（三項判斷由 orchestrator 於每輪維護，見 `agents/orchestrator.md`「共識檢查邏輯」）：

1. **≥2 個 Agent 同意同一方案** → 達成共識
2. **單一方案總分明顯領先**（與次高分差距 ≥8 分）→ 視為實質收斂，即使未達第 1 條的明確同意

以上皆不成立時：
- 未收斂且 < 最大輪數（`--max-rounds`，預設 10）→ 回到 Phase 2
- 達到最大輪數仍未收斂 → Critic 最終裁決

### Phase 5：使用者互動

每輪結束後，使用 AskUserQuestion 詢問使用者：

```
AskUserQuestion(
  questions=[{
    question: "第 N 輪辯論結束，請選擇下一步",
    header: "辯論進度",
    options: [
      { label: "繼續", description: "進行下一輪辯論" },
      { label: "採納", description: "採納當前最高分方案" },
      { label: "介入", description: "調整方向或追加條件" },
      { label: "重設角度", description: "重新設定思考角度" }
    ],
    multiSelect: false
  }]
)
```

### Phase 5.5：獨立驗證（Validator Gate）

在候選方案確定後（共識達成、使用者選擇「採納」或 Critic 最終裁決後），**必須**先執行驗證關卡才能進入最終輸出：

```
Task(
  subagent_type="multi-agent-debate:validator",
  prompt="請驗證以下候選最終決策。\n\n原始需求：$ARGUMENTS\n\n候選方案：{候選方案完整內容}\n\n辯論過程摘要（含所有 Critic 挑戰與 Agent 回應）：{辯論摘要}\n\n請依照 validator.md 的驗證清單逐一審查，並輸出裁決報告。"
)
```

**路由規則（依裁決結果）：**

| 裁決 (`verdict`) | 後續動作 |
|-----------------|---------|
| `verified` | 直接進入 Phase 6 最終輸出，輸出中標注「Validator: ✅ verified」 |
| `corrected` | 使用 validator 提供的修正後合成版本進入 Phase 6，輸出中附上修正記錄（corrections 欄位內容） |
| `rejected` | 先用 AskUserQuestion 向使用者說明 Validator 拒絕原因；使用者確認後退回 Phase 2 重新執行批判審查；若已達到最大輪數，等待使用者指示 |
| `needs_user_decision` | 立即使用 AskUserQuestion 向使用者呈現 unresolvedQuestions，等待使用者裁決後再決定是否輸出 |

**跳過驗證的唯一允許情況：**

若 validator agent 因工具故障或 agent 不可用而無法執行，必須：
1. 在最終輸出中明確標注「⚠️ Validator 未執行，原因：{具體原因}」
2. 不得靜默跳過（silently skip）——必須有明確的跳過記錄

---

### Phase 6：最終輸出

#### 6a. 結構化產物與結構閘門（Structural Gate）

在輸出最終 markdown 前，先將本次辯論結果組裝為 `debate-output.json`（符合 `schema/debate-output.schema.json`），寫入運行目錄，並執行驗證：

```bash
node ${CLAUDE_PLUGIN_ROOT}/validators/validate-debate-output.cjs debate-output.json
```

此為**結構閘門**，與 Phase 5.5 validator agent 的**語意**裁決互補：機器化確認產物欄位完整、分數 0-10、verdict 合法，且**跨欄位引用完整**——`finalDecision.selectedProposal` 與 `consensus.agreedProposals` 都必須指向真實存在的 `proposals[].id`（防止多輪後選到不存在的方案 id）。此外**覆蓋聲明（`coverage`）為必填**：`covered[{aspect, summary}]` / `notCovered[{aspect, reason}]`，且每個未覆蓋面向都必須附 `reason`——機器強制「覆蓋缺口不得無故省略」。

- 通過（exit 0，`VALID`）→ 進入 6b 最終 markdown 輸出
- 失敗（exit 1，`INVALID`）→ 先修正產物組裝（欄位缺漏、id 不一致）後重跑；若根因是辯論結果本身不自洽，比照 Phase 5.5 `rejected` 路由退回 Phase 2。**不得靜默跳過**：若 validator 因工具故障無法執行，在最終輸出標註「⚠️ 結構驗證未執行，原因：...」

#### 6b. 最終 markdown 輸出

輸出格式：

```markdown
# 🎯 最終方案

## 採納方案: [方案名稱]
**來源**: Agent [X]（[共識狀態]）
**總分**: X/30
**Validator 裁決**: `verified` | `corrected` | ⚠️ 未執行（原因：...）

[完整方案內容]

### 修正記錄（Validator corrected 時出現）
[來自 validator 的 corrections 欄位內容]

## 📊 評分明細

| Agent | 可行性 | 效益 | 風險控制 | 總分 |
|-------|--------|------|----------|------|
| A     | X/10   | X/10 | X/10     | X/30 |
| B     | X/10   | X/10 | X/10     | X/30 |
| C     | X/10   | X/10 | X/10     | X/30 |

<details>
<summary>📜 辯論過程（點擊展開）</summary>

[完整辯論記錄]

</details>
```

## 覆蓋聲明（Coverage Declaration）

覆蓋聲明的**機器可讀形式是 6a `debate-output.json` 的 `coverage` 欄位**（`covered[{aspect, summary}]` / `notCovered[{aspect, reason}]`，由結構閘門強制為必填、每個未覆蓋面向須附 `reason`）。以下 markdown 表格由該欄位衍生，讓覆蓋狀況可在不讀完整個對話記錄的情況下被審查：

```markdown
## 🗂️ 覆蓋聲明

| 面向 | 狀態 | 摘要 |
|------|------|------|
| [面向 1] | 已覆蓋 | [1-2 句說明討論深度] |
| [面向 2] | 已覆蓋 | [1-2 句說明討論深度] |
| [面向 3] | 未覆蓋 | 原因：[為何本次辯論未能涵蓋] |

**先行辯論脈絡**：[若有使用先行產物，記錄 artifactRef 及對本次辯論的影響；若無，寫「無先行辯論脈絡」]
```

最終輸出後，選擇性地將本次辯論摘要寫入本地 `prior-debate.json`（僅在 orchestrator 判斷本次辯論結果具備後續重用價值時），格式符合 `schema/prior-debate.schema.json`，其中 `reuseConstraint.suppressNewFindings` 和 `reuseConstraint.suppressNewDecisions` **必須為 `false`**。

## 使用範例

```bash
# 基本用法
/debate 我想為電商網站新增商品推薦功能

# 指定最大輪數
/debate 重構使用者認證系統 --max-rounds 5

# 自訂思考角度
/debate 設計新的快取策略 --perspectives "效能優先,成本優先,簡單優先"
```

## 參數說明

- `--max-rounds N`：最大辯論輪數（預設 10）
- `--perspectives "角度1,角度2,角度3"`：自訂三個思考角度

## 參考文件

- **Phase 2 批判審查方法論**：`references/CRITIQUE-METHODOLOGY.md`（Critic 在第一輪審查前讀；評分校準有疑問、挑戰品質退化或最終裁決前重讀）
- **辯論品質退化處理**：`references/ANTI-PATTERNS.md`（Orchestrator/Critic/Validator 當辯論品質退化時讀；包含五種常見失敗模式與 Recovery）
- **先行辯論產物合約**：`schema/prior-debate.schema.json`（Phase 0 查找先行辯論時讀；定義 reuseConstraint 必要欄位與不得壓制新發現的規則）

## 注意事項

1. **進度追蹤**：使用 TodoWrite 追蹤每個 Phase 的進度
2. **錯誤處理**：如果某個 Agent 失敗，記錄錯誤並詢問使用者是否重試
3. **文件語言**：所有輸出使用繁體中文
