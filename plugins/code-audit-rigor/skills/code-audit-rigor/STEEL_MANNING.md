# STEEL_MANNING.md

> **用途**：Code Audit Rigor Phase 4 Step 2 的結構化 Steel-Manning 程序。在 reference anchoring（Step 1）通過後，對每條標記 ACT 或 INVESTIGATE_FURTHER 的發現，**必須**執行此 steel-manning 程序，然後才能輸出最終報告。

---

## 什麼是 Steel-Manning

Steel-Manning 是「嘗試構造對立面最強版本的論點」。在 code audit 脈絡中，就是：**假設你的發現是誤判，然後認真找出為什麼它可能是誤判的最有力理由。**

如果你找不到有力的反駁理由，找到的才是真正的問題。
如果你找到了有力的反駁，應該降低信心分數或改變裁決。

---

## 對立面檢查清單（Opposite-Case Checks）

對每條發現，依序執行以下六項檢查。每項都需要實際查看原始碼，不得僅依記憶推斷。

### OC-1. 上游防禦（Upstream Guards）

問：**是否有呼叫鏈上游已執行相同的防禦？**

- 找出此程式碼的所有已知呼叫者
- 確認每個呼叫者是否在傳遞參數前已做過驗證或清理
- 若所有呼叫路徑都有上游防禦，發現的實際可利用性可能為零

工具建議：`grep`（查找呼叫者）；若有 codegraph，用 `codegraph_callers` 追蹤完整呼叫鏈。

### OC-2. Framework / Runtime 保障

問：**是否有 framework 或 runtime 層級的機制已自動處理此問題？**

常見保障範例（不限於此）：
- ORM 的參數化查詢（自動防 SQL injection）
- 模板引擎的自動 HTML escape（自動防 XSS）
- 型別系統的靜態保障（確保某類輸入根本無法到達此處）
- HTTP framework 的 CSRF token 自動驗證
- 語言 runtime 的邊界檢查（自動防 buffer overflow）

若 framework/runtime 保障已完整涵蓋被指控的風險，審查者必須說明具體的保障機制名稱與版本，而非泛泛聲稱「framework 會處理」。

### OC-3. 不可能的輸入（Impossible Inputs）

問：**被指控的攻擊輸入，在系統的其他約束下是否根本不可能進入此路徑？**

- 業務邏輯層是否已排除某些輸入值？（例如只有已認證使用者才能到達此處，且認證已在別處充分驗證）
- 資料庫層是否有外鍵約束或 check constraint 防止非法狀態？
- 前端是否有強制性的資料格式驗證，且後端完全信任此資料的情境是否合理？

⚠️ 注意：「前端驗證」本身通常**不是**有效的上游防禦——除非你能確認此路徑根本不允許來自前端之外的呼叫。

### OC-4. False-Positive 抑制適用性

問：**此發現是否符合當前 rule pack 的 Do NOT report 抑制清單中的任何條目？**

- 回顧 Phase 1b 中為此檔案解析的 rule pack
- 確認此發現是否落在抑制清單描述的場景中
- 若符合，**明確說明**此發現為何適用或不適用該抑制條目（不得靜默適用）

### OC-5. 不完整的呼叫路徑（Missing Call Path）

問：**此發現是否假設了一條實際上不存在或不可達的呼叫路徑？**

- 發現的可利用性是否依賴某個攻擊者能從外部直接呼叫此函數？
- 若此函數只在內部被呼叫，呼叫者是否都在信任邊界內？
- 發現的跨 module 呼叫鏈，是否在實際程式碼中真的存在（不是假設）？

### OC-6. 測試用 / 死碼（Test-Only / Dead Code）

問：**被指控的程式碼是否僅在測試環境中執行，或是永遠不會被呼叫的死碼？**

- 程式碼是否在 `test/`、`spec/`、`__tests__/` 目錄？
- 是否有 `if process.env.NODE_ENV === 'test'` 或類似的環境守衛？
- 是否有任何呼叫者（死碼分析）？

若確認為死碼，可降至低嚴重度或 DISMISS，但必須記錄此為死碼的具體依據。

---

## 信心調整規則

重新計算 EV 時使用 SKILL.md Framework 2 的公式：

```
EV = (confidence%) × points − (100 − confidence%) × 2 × points
```

- `confidence%` 以 0–1 小數代入（例如 80% = 0.8）
- `points` 使用嚴重度分數：Critical=10、High=5、Medium=3、Low=1
- EV > 0 → 值得繼續調查 / 採取行動
- EV < 0 → 可降級為 INVESTIGATE_FURTHER 或 DISMISS
- 67% 信心是 EV 損益平衡點；「低於 67%」與「EV < 0」是同一規則的兩種表達，以 EV 計算結果為準

執行完所有適用的對立面檢查後，根據找到的反駁證據調整信心分數：

| 找到的反駁強度 | 信心調整 |
|-------------|---------|
| 強烈反駁（例如 ORM 參數化查詢明確防禦、型別系統靜態排除） | -20 至 -40 分 |
| 中等反駁（例如上游防禦存在但非100%完整） | -10 至 -20 分 |
| 弱反駁（例如部分呼叫路徑有防禦，但有其他路徑未防禦） | -5 至 -10 分 |
| 無有力反駁（六項檢查均未發現可信的對立論點） | 信心不變或略升 |

調整後，重新計算 EV。若 EV 降至 0 以下，考慮降級為 INVESTIGATE_FURTHER 或 DISMISS。

---

## 裁決枚舉

完成所有對立面檢查和信心調整後，發出此發現的 steel-manning 裁決：

| 裁決 | 意義 |
|------|------|
| `verified` | Steel-manning 未找到有力反駁，發現維持確認狀態 |
| `corrected` | Steel-manning 發現描述不精確，但修正後問題仍存在 |
| `rejected` | Steel-manning 找到有力反駁，信心降至 EV < 0，改為 DISMISS |
| `needs_user_decision` | 反駁和確認的證據勢均力敵，需要業務知識或使用者判斷才能裁決 |

---

## 輸出格式

每條發現的 steel-manning 結果，以以下格式附在 Phase 4 記錄中：

```
STEEL-MANNING: [Finding ID]

opposite-case checks:
  OC-1 (upstream guards):     [已核查 / 不適用] — [結論]
  OC-2 (framework/runtime):   [已核查 / 不適用] — [結論]
  OC-3 (impossible inputs):   [已核查 / 不適用] — [結論]
  OC-4 (suppression):         [已核查 / 不適用] — [結論]
  OC-5 (call path):           [已核查 / 不適用] — [結論]
  OC-6 (test/dead code):      [已核查 / 不適用] — [結論]

evidence checked:
  [列出實際閱讀的具體檔案:行號]

confidence delta: [原始信心] → [調整後信心]（調整依據：[最強反駁論點]）

updated EV: [計算值]（severity=[X]pts, conf=[Y]%）

verdict: verified | corrected | rejected | needs_user_decision

user-decision trigger: [若 needs_user_decision，說明具體需要使用者判斷的問題]
```

---

## 未執行說明規則

若某條發現**無法**執行 steel-manning（例如缺乏足夠的程式碼存取權限），必須：

1. 在該發現的記錄中明確標注：`steel-manning: NOT_PERFORMED — [原因]`
2. 將該發現的裁決標記為 `needs_user_decision`（不得標記為 confirmed）
3. 在 Phase 5 報告中說明未執行的原因及影響

**無法執行 steel-manning = 無法確認（cannot be confirmed）。** 此規則不可迴避。

---

## 與 Phase 5 報告的整合

Phase 5 彙整報告中，每條 CONFIRMED 發現必須附上其 steel-manning verdict；每條 DISMISSED 發現若來自 steel-manning 降級，也必須說明哪條對立面檢查是主要決定因素。

在 Phase 5 報告的 CONFIRMED FINDINGS 區段，每條發現格式為：
```
[severity, conf XX, EV +Y.Y] BUG-NNN: ...
  steel-manning: verified (OC-1/OC-2/... all checked, no strong counter-evidence)
```

在 DISMISSED FINDINGS 區段：
```
[severity, conf XX, EV -Y.Y] BUG-DNN: dismissed — [主要 OC 檢查結論]
  steel-manning: rejected (OC-2: ORM parameterized query covers this; EV dropped to -3.2)
```
