# OUTPUT-CONTRACTS.md

> **用途**：定義 OpenSpec + Superpowers 工作流程每個 Phase 的耐久性產出合約（durable output contracts），以及各 Phase 的覆蓋定義。讓產出狀況可在不讀完整個對話記錄的情況下被審查和驗證。
>
> **讀取時機**：Phase 6 歸檔前（覆蓋核查）；當你不確定某個 Phase 的「完成」定義；當 OpenSpec validator 回報缺少 artifact 時。

---

## 合約摘要

| Phase | 必要產出 | 覆蓋定義 | 非覆蓋 / 延後項目 |
|---|---|---|---|
| 1 | `proposal.md`, `specs/*/spec.md`, `design.md`（stub）, `tasks.md`（stub）, `review-notes.md`（empty） | 所有功能需求 | 跨功能限制（constitution）、詳細設計 |
| 2 | `design.md`（overwritten, final） | Phase 1 需求的架構覆蓋 | 實作細節、任務分解 |
| 3 | `tasks.md`（overwritten, final） | 所有設計決策映射到可執行任務 | 跨功能任務（constitution）、測試策略細節 |
| 4 | 程式碼、測試 | 每個任務有測試（TDD RED→GREEN），每個 SPEC 需求有對應測試 | 效能基準、end-to-end 測試（除非 spec 要求） |
| 5 | `review-notes.md` 條目 | 所有審查意見已分類並標記（Y/N + tag） | Spec 修改（Phase 5 禁止修改 spec） |
| 6 | 重寫後的 spec 檔案（`proposal.md`, `specs/*/spec.md`, `design.md`）、RECONCILIATION-CRITERIA.md 核查 | 所有 Y 項目對應到正確 artifact | 未決的 `[CONSTITUTION]` 項目（單獨處理） |

---

## Phase 1：Spec Definition

### 必要產出（Required Outputs）

| 檔案 | 內容要求 | 可驗證條件 |
|------|---------|-----------|
| `proposal.md` | 功能目的、能力列表、使用者故事 | 非空；使用者已審核通過 |
| `specs/<capability>/spec.md` | `### Requirement:` 區塊每個第一段含 SHALL 或 MUST | `openspec validate --strict` 通過 |
| `design.md` | Stub（說明將由 Phase 2 覆寫） | 存在即可；Phase 1 不要求完整設計 |
| `tasks.md` | Stub（說明將由 Phase 3 覆寫） | 存在即可；Phase 1 不要求完整任務 |
| `review-notes.md` | 空白檔案，供 Phase 5 使用 | 存在即可 |

### 覆蓋定義

- **覆蓋**：功能需求（WHAT）、使用者可見行為、邊界條件
- **未覆蓋（正常）**：架構決策（Phase 2）、實作細節（Phase 4）、跨功能規則（constitution）
- **未覆蓋（需明示）**：若某個功能需求因時間或範圍被推延，必須在 `proposal.md` 加上 `> **Out of scope for this change:** [item] — [reason]` 說明

### 有效 / 無效需求寫法範例

```markdown
# ✅ 有效：SHALL/MUST 在第一段
### Requirement: Export CSV
Users MUST be able to export their data as a CSV file.

# ✅ 有效：MUST 在第一句後加說明
### Requirement: Rate Limiting
The API SHALL enforce per-user rate limits.
- Default: 100 requests/minute
- Configurable per plan

# ❌ 無效：SHALL 只出現在 bullet list 中（openspec validate 會拒絕）
### Requirement: Export CSV
Users can export their data.
- The export SHALL be in CSV format.

# ❌ 無效：第一段無 SHALL/MUST
### Requirement: Export CSV
This feature allows users to download data.
All exports must be validated before download.
```

---

## Phase 2：Design Refinement

### 必要產出

| 檔案 | 內容要求 | 可驗證條件 |
|------|---------|-----------|
| `design.md` | 完整設計文件（OVERWRITE stub）；包含架構、API、資料模型、錯誤處理 | 內容非 stub；使用者已審核 |

### 覆蓋定義

- **覆蓋**：Phase 1 每個需求的架構決策、邊界條件處理、安全考量
- **未覆蓋（正常）**：實作細節（Phase 4 決定）、測試策略（Phase 4）
- **未覆蓋（需明示）**：若某個需求的設計決策被推延或存在未解決歧義，在 `design.md` 加上 `> **Deferred design decision:** [item] — [reason]`

---

## Phase 3：Task Planning

### 必要產出

| 檔案 | 內容要求 | 可驗證條件 |
|------|---------|-----------|
| `tasks.md` | 完整任務清單（OVERWRITE stub）；每個任務含精確檔案路徑、驗證步驟 | 內容非 stub；每個設計決策有對應任務；使用者已審核 |

### 覆蓋定義

- **覆蓋**：每個設計決策（Phase 2）映射到一或多個可執行任務
- **任務→需求追溯**：`tasks.md` 中的每個任務應可追溯到至少一個 Phase 1 需求
- **未覆蓋（需明示）**：若某個需求沒有對應任務（例如暫時跳過），在 `tasks.md` 加上一行說明 `> **Not tasked:** [requirement] — [reason]`

---

## Phase 4：Implementation

### 必要產出

| 產出 | 要求 |
|------|------|
| 程式碼 | 每個任務完整實作，通過任務 reviewer |
| 測試 | TDD 順序（RED→GREEN）；每個 SPEC 需求有對應測試 |

### 覆蓋定義

SPEC 需求覆蓋核查（Phase 4 完成時）：

| 類別 | 說明 |
|------|------|
| **已覆蓋（tested）** | 有對應測試且測試通過的需求 |
| **未覆蓋（untested）** | 有需求但測試無法執行（需明示原因） |
| **範圍外（outOfScope）** | Phase 1 就已明示不在本次範圍 |

- **不允許** 留有無測試的已實作需求而不標注為 untested + 原因
- **不允許** 以「功能可用」代替明確的測試通過記錄

### 先行運行（Prior Run）規則

若參考先前實作記錄（prior run artifact）：
- `priorRunRef.suppressesFindings` **必須為 `false`**
- 先行運行資訊只作為上下文參考，不替代本次 TDD 流程
- Reviewer 發現的問題不因先前運行通過而自動豁免

---

## Phase 5：Review & Feedback

### 必要產出

| 檔案 | 內容要求 | 可驗證條件 |
|------|---------|-----------|
| `review-notes.md` | 每輪審查的所有意見，含 tag 和 Y/N | 無遺漏審查意見；格式符合 `phases.md` 規範 |

### 覆蓋定義

- **覆蓋**：所有審查意見已記錄並標記（`[REQUIREMENT]`、`[DESIGN]`、`[CODE]`、`[CONSTITUTION]`）
- **N 項目**：Code-only 修正，無需 spec 更新
- **Y 項目**：需 spec 或 constitution 更新，必須在 Phase 6 處理
- **未覆蓋（需明示）**：若某輪審查意見因時間或範圍未完整記錄，在 `review-notes.md` 加上 `> **Incomplete round:** [reason]`

### 未覆蓋 / 延後項目

- Phase 5 **禁止**修改任何 spec 文件（`proposal.md`、`specs/`、`design.md`、`tasks.md`）
- Spec 修改請求記錄為 Y 項目，推延到 Phase 6

---

## Phase 6：Reconcile & Archive

### 必要產出

| 產出 | 要求 |
|------|------|
| 重寫後的 `proposal.md` | 處理所有 `[REQUIREMENT]` Y 項目；clean rewrite（非增量修改） |
| 重寫後的 `specs/<capability>/spec.md` | 處理所有 `[REQUIREMENT]` Y 項目；符合 SHALL/MUST 規則 |
| 重寫後的 `design.md` | 處理所有 `[DESIGN]` Y 項目；clean rewrite |
| RECONCILIATION-CRITERIA.md 核查結果 | C1–C5 全部通過，裁決為 `verified` |

### 覆蓋定義（Phase 6 core coverage contract）

以下四個面向必須完整核查，不可跳過：

#### 1. 需求覆蓋（Requirements Coverage）
所有 `[REQUIREMENT]` Y 項目都已更新到 `proposal.md` 和/或 `specs/*/spec.md`。
**未覆蓋 / 延後**：若某 Y 項目決定不更新 spec（例如使用者判斷不必要），必須在 `review-notes.md` 附加說明 `> **Deferred:** [reason]`，不可靜默跳過。

#### 2. 任務→需求追溯（Task-to-Requirement Traceability）
`tasks.md` 中的任務可追溯到 Phase 1 的需求。
**注意**：Phase 6 不得修改 `tasks.md`（它是執行歷史）。追溯是驗證性的，不是修改性的。

#### 3. 審查意見已全部處理（Review Comments Accounted For）
`review-notes.md` 中所有 Y 項目都已對應到正確 artifact 的更新，並符合 C1 核查表的 tag↔artifact 對應規則。
**未覆蓋**：無論 Y 還是 N，每個意見都必須有明確的處置記錄。

#### 4. 未覆蓋 / 延後項目（Not-Covered / Deferred Items）
明確列出本次 reconcile 中決定延後或不處理的項目，以及原因。若無延後項目，明示「無延後項目」。

```markdown
## Phase 6 覆蓋核查摘要（嵌入對話回覆，不需存為獨立檔案）

| 覆蓋面向 | 狀態 | 說明 |
|---------|------|------|
| [REQUIREMENT] Y 項目已更新 spec | ✅ / ❌ | N 項全部處理 |
| [DESIGN] Y 項目已更新 design.md | ✅ / ❌ | N 項全部處理 |
| [CONSTITUTION] Y 項目已移至 constitution | ✅ / ❌ | N 項已處理或確認由使用者處理 |
| tasks.md 未被修改 | ✅ / ❌ | — |
| 延後 / 未覆蓋項目 | [列表或「無」] | — |
```

---

## Validator 支援

`validators/validate-openspec-workflow.cjs <change-folder-path>` 自動檢查：
- 必要檔案存在（`proposal.md`、`design.md`、`tasks.md`、`review-notes.md`）
- `specs/**/spec.md` 存在
- 每個 `### Requirement:` 區塊第一段含 SHALL 或 MUST

其他覆蓋項目（任務→需求追溯、Y 項目處理、延後項目）為 Phase 6 人工核查，記錄於 `RECONCILIATION-CRITERIA.md`。

---

## 延後項目規範

「延後」不等於遺忘。任何有意跳過的覆蓋項目必須明示：

```markdown
> **Deferred:** [描述被延後的項目] — [原因] — [預計處理時機或 N/A]
```

放置位置：
- Phase 1：`proposal.md` 的 Out-of-scope 區段
- Phase 2：`design.md` 的 Deferred Decisions 區段  
- Phase 3：`tasks.md` 的 Not-tasked 區段
- Phase 6：`review-notes.md` 的 Deferred 附注，或 RECONCILIATION-CRITERIA.md 輸出表格
