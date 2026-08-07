# RECONCILIATION-CRITERIA.md

> **用途**：Phase 6 歸檔前的獨立核查門檻。在執行 `/opsx:archive` 之前，必須依照此文件逐一核查，並取得 `verified` 裁決，才能進行歸檔。

---

## 核查清單

### C1. review-notes.md Y 項目已正確對應到正確的 artifact 類型

逐行掃描 `openspec/changes/<feature-name>/review-notes.md`，對每一條標記 **Y** 的項目確認：

| 標籤 | 應更新的 artifact | 禁止更新的 artifact |
|-----|-----------------|-------------------|
| `[REQUIREMENT]` Y | `proposal.md`、`specs/<capability>/spec.md` | `design.md`、`tasks.md`、constitution |
| `[DESIGN]` Y | `design.md` | `specs/`、`tasks.md`、constitution |
| `[CONSTITUTION]` Y | 專案 constitution（`openspec/config.yaml` 或指定位置）| feature spec 任何檔案 |
| `[CODE]` N | （無需更新 spec） | — |

**修正路徑**：若核查發現某 Y 項目的標籤與其實際修正落點不符（例如標了 `[DESIGN]` 但要改的字句在 `specs/`——「設計決策衝撞 spec 字面」是已知的誤標類型），在 `review-notes.md` 修正標籤並附註記，再依修正後的標籤處理。**不得**為遷就原標籤而跳過 spec 更新（會把 spec 與實作的分歧歸檔成永久的錯誤真相來源），也不得帶著原標籤違規更新。

**失敗條件**：任何 Y 項目未被對應到應更新的 artifact，或被對應到禁止更新的 artifact。

---

### C2. `[CONSTITUTION]` 項目未放入 feature spec 檔案

確認以下 feature spec 檔案均**不包含** `[CONSTITUTION]` review 項目所描述的跨功能規則：

- `openspec/changes/<feature-name>/proposal.md`
- `openspec/changes/<feature-name>/specs/<capability>/spec.md`
- `openspec/changes/<feature-name>/design.md`

Constitution 規則應已移至 `openspec/config.yaml` 的 `context:` 或 `rules:` 欄位，或使用者確認的其他 constitution 位置。

**失敗條件**：feature spec 中出現應屬於 constitution 的跨功能規則。

---

### C3. `tasks.md` 在 Reconcile 期間未被修改

`tasks.md` 是執行歷史，Phase 6 Reconcile 期間不得修改。

確認方式：
```bash
git diff HEAD -- openspec/changes/<feature-name>/tasks.md
```

若工作樹是乾淨的（reconcile 在 commit 後），改用 git log 或比較原始內容確認 tasks.md 未在本次 reconcile session 中變動。

**失敗條件**：tasks.md 在 reconcile 過程中有任何變動。

---

### C4. 改寫後的 spec 在每個 `### Requirement:` 區塊的第一段包含 SHALL 或 MUST

對改寫後的所有 spec 檔案（`proposal.md`、`specs/<capability>/spec.md`）：

確認每一個 `### Requirement:` 標題後的第一段（在任何子標題或條列清單之前）包含 `SHALL` 或 `MUST` 關鍵字。

可用以下 grep 輔助確認：
```bash
grep -A 2 "### Requirement:" openspec/changes/<feature-name>/specs/<capability>/spec.md
```

若有任何 Requirement 區塊的第一段缺少 SHALL/MUST，`openspec validate --strict` 將拒絕歸檔。

**失敗條件**：任何 Requirement 區塊的第一段不含 SHALL 或 MUST。

---

### C5. 改寫為連貫文件，非增量補丁

確認改寫後的 spec 檔案讀起來像「一開始就知道所有資訊而寫成的文件」，而非附有修訂記錄的文件。

具體確認：
- 文件中**不包含** "修訂：原本是 X，現在改為 Y" 等補丁語言
- 文件中**不包含**指向舊版本的對比說明
- 整體敘述連貫一致，不存在前後矛盾的段落

**失敗條件**：spec 文件含有補丁語言或前後矛盾，顯示為增量修改而非完整改寫。

---

## 裁決

完成以上五項核查後，發出裁決：

| 裁決 | 意義 | 後續動作 |
|------|------|---------|
| `verified` | 所有核查項目通過，可以歸檔 | 執行 `/opsx:archive <feature-name>` |
| `corrected` | 發現可自行修正的問題（例如遺漏某個 Y 項目的 spec 更新） | 修正後**重新執行所有核查**，不得直接升級為 verified |
| `rejected` | 發現不可自行修正的問題（例如 constitution 項目已寫入 feature spec，需使用者確認如何處理） | 不得歸檔；向使用者報告具體問題 |
| `needs_user_decision` | 核查者無法確定某項決定是否正確（例如某 Y 項目的 artifact 對應方式有歧義） | 停止歸檔流程，向使用者提出具體問題並等待裁決 |

---

## 輸出模板

在 Phase 6 中執行此核查後，輸出以下表格（可內嵌在對話回覆中，不需儲存為獨立檔案）：

```markdown
## 🗂️ Reconciliation Criteria 核查結果

| 核查項目 | 結果 | 說明 |
|---------|------|------|
| C1. Y 項目對應正確 artifact | ✅ / ❌ / ⚠️ | [說明] |
| C2. CONSTITUTION 未進入 feature spec | ✅ / ❌ / ⚠️ | [說明] |
| C3. tasks.md 未被修改 | ✅ / ❌ / ⚠️ | [說明] |
| C4. Requirement 含 SHALL/MUST | ✅ / ❌ / ⚠️ | [說明] |
| C5. 改寫為連貫文件 | ✅ / ❌ / ⚠️ | [說明] |

**裁決：`verified` / `corrected` / `rejected` / `needs_user_decision`**

[若非 verified，說明具體問題與建議處置方式]
```
