# Superpowers Handoff Reference

**When to read this:** Phase 2（Design Refinement）、Phase 3（Task Planning）、Phase 4（Implementation）開始前，以及每次 Superpowers 工具（brainstorming、writing-plans、subagent-driven-development）產出了需要 sync back 到 OpenSpec 的內容時。

---

## 核心原則

Superpowers 產出**永遠 OVERWRITE** OpenSpec 的對應檔案，**不建立任何獨立的 sidecar 檔案**。

---

## Phase 2 Handoff 模板：brainstorming → design.md

### 輸入
- `openspec/changes/<name>/proposal.md`（OpenSpec 的「why」）
- `openspec/changes/<name>/specs/<capability>/spec.md`（規格需求）

### 執行
```
啟動 /brainstorming skill
輸入：proposal.md 和 specs/ 的內容
執行 Socratic 提問流程
```

### Sync back（必要步驟，不可省略）
```
OVERWRITE openspec/changes/<name>/design.md
with the refined design output from brainstorming
```

### ✅ 正確範例
```
brainstorming 完成，輸出了詳細的設計文件
↓
Write(path: "openspec/changes/user-export/design.md", content: <brainstorming output>)
```

### ❌ 錯誤範例（Anti-pattern AP-1）
```
brainstorming 完成，輸出了詳細的設計文件
↓
Write(path: "design-refined.md", content: <brainstorming output>)  # 建立了獨立的 sidecar 檔案！
```

---

## Phase 3 Handoff 模板：writing-plans → tasks.md

### 輸入
- `openspec/changes/<name>/design.md`（Phase 2 產出）

### 執行
```
啟動 /writing-plans skill
輸入：design.md 內容
產出：2-5 分鐘粒度的任務清單，包含精確檔案路徑和驗證步驟
```

### Sync back
```
OVERWRITE openspec/changes/<name>/tasks.md
with the tasks output from writing-plans
```

### ✅ 正確範例
```
writing-plans 完成，產出任務清單
↓
Write(path: "openspec/changes/user-export/tasks.md", content: <tasks output>)
```

### ❌ 錯誤範例（Anti-pattern AP-2）
```
writing-plans 完成，產出任務清單
↓
Write(path: "plan.md", content: <tasks output>)  # 計畫沒有放在 OpenSpec 資料夾中！
```

---

## Phase 4 Handoff 模板：tasks.md → subagent-driven-development with TDD

### 輸入
- `openspec/changes/<name>/tasks.md`（Phase 3 產出，已由使用者審核）

### 執行
```
啟動 /subagent-driven-development 或 /executing-plans
每個 task 的順序：
  1. 寫測試（RED）
  2. 實作讓測試通過（GREEN）
  3. 重構（REFACTOR）
  4. 任務 reviewer 審查
```

### 禁止在此 Phase 做的事
- 修改任何 spec 檔案（proposal.md、specs/、design.md）
- 修改 tasks.md 的任務描述（可以 check off 完成狀態）

---

## Anti-Patterns 與 Recovery

### AP-1：建立了 sidecar design 檔案（Sidecar Design File）

**症狀：** brainstorming 輸出被寫入 `design-v2.md`、`design-refined.md`、`superpowers-design.md` 等獨立檔案，而不是覆寫 OpenSpec 的 `design.md`。

**為什麼失敗：** OpenSpec 的工作流程假設 `design.md` 是唯一的設計真相來源。如果有多個設計文件，Phase 6 reconcile 時不知道以哪個為準，且 `/opsx:archive` 不會知道 sidecar 檔案的存在。

**Recovery：**
1. 立即確認哪個是最新的設計輸出
2. 用那個內容覆寫 `openspec/changes/<name>/design.md`
3. 刪除 sidecar 檔案

### AP-2：計畫放在 OpenSpec 資料夾外（Plan Outside OpenSpec Folder）

**症狀：** tasks.md 被建立在專案根目錄、`docs/` 或其他位置，而不是 `openspec/changes/<name>/tasks.md`。

**Recovery：**
1. 移動計畫檔案到正確位置：`openspec/changes/<name>/tasks.md`
2. 刪除原始位置的檔案

### AP-3：忘記 Sync Back（Forgot to Sync Back）

**症狀：** brainstorming 或 writing-plans 在對話中完成了，但沒有執行「覆寫 design.md / tasks.md」的步驟，對話結束後 OpenSpec 資料夾中的檔案還是舊版本。

**Recovery：**
1. 在 brainstorming / writing-plans 完成後立即執行 sync back，不要等到後續步驟
2. 驗證：`cat openspec/changes/<name>/design.md` 確認內容是最新的

### AP-4：Phase 6 增量修改而非 Clean Rewrite（Incremental Reconciliation）

**症狀：** Phase 6 reconcile 時，看到 review-notes.md 中的 [DESIGN] Y 項目，直接在舊 design.md 中 append 新段落或修改某幾行，而不是重寫整個文件。

**為什麼失敗：** 增量修補會讓 design.md 變成「帶著歷史瘡疤的文件」，新讀者看到矛盾或過時的資訊。Phase 6 的目標是讓規格讀起來像「一開始就知道所有資訊」。

**Recovery：**
1. 讀完所有 review-notes.md 的 Y 項目之後，用完整的、統一口吻**重寫** design.md（不是修改）
2. 重寫後驗證：文件讀起來是否像一份從頭開始寫的文件，而不是一份帶著修正標記的文件
