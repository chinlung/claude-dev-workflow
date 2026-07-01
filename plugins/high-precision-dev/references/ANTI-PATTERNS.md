# High-Precision Dev Anti-Patterns

**When to read this:** 所有 agent（implementer-a/b、critic、adversary、disproof-agent、verifier）和 controller 在以下情況應讀此文件：（1）任何一個 Phase 的產出看起來「太乾淨」（所有問題都 severity 1、攻擊全部失敗、差異極少）；（2）流程卡住、修復循環超過 2 次；（3）懷疑某個 agent 沒有執行其職責的核心工作。

---

## AP-1：兩份實作重複而非獨立（Duplicate Instead of Independent Implementations）

**症狀：** IMPL_A_REPORT.md 和 IMPL_B_REPORT.md 幾乎完全相同（相同的函式名稱、相同的邊界條件處理、相同的錯誤訊息）。

**為什麼失敗：** 獨立實作的核心價值是「認識論分離」——兩個 agent 從不同角度詮釋規格，差異才是有價值的資訊。如果兩份實作相同，Phase 3/4 的比對沒有意義，對抗式審查的錯誤壓縮效益消失。**注意**：a/b 的獨立性對「系統性誤讀」（同一個 base model 的共用盲點）本就有限——worktree 隔離只擋抄襲、擋不了共同盲點。這正是 implementer-a/b 被刻意賦予**不同實作路徑**（A 規格優先 / B 測試優先）的原因：讓最弱的那條獨立性腿真正去相關。

**Recovery：**
1. Controller 在 Phase 2 派出兩個 implementer 時，確認每個 agent 的 prompt 中明確包含「你不能查看另一個 implementer 的任何輸出」。
2. 若兩份實作結果相同，verifier 在步驟一應質疑是否發生了資訊洩漏，並在 VERIFICATION.md 中記錄此情況。
3. 不要因為「兩者相同代表可能是正確的」而直接通過——相同可能代表兩者都從相同的錯誤假設出發。

---

## AP-2：Critic 只審查風格（Critic Validates Style Only）

**症狀：** CRITIQUE.md 中全是 severity 1-2 的問題，且問題都是「命名不一致」、「缺少 docstring」、「可以用更簡潔的寫法」等風格問題，沒有任何 severity >= 3 的邏輯問題。

**為什麼失敗：** Critic 的職責是發現規格偏差和邏輯錯誤，不是 linter。所有發現都是 severity 1-2 通常意味著 critic 沒有真正對照 SPEC.md 逐條驗證，或者 critic 沒有構造邊界測試案例。

**Recovery：**
1. Critic 必須重新執行：針對 SPEC.md 的每一條需求，明確找到對應的實作程式碼，驗證它是否正確處理了規格中提到的**邊界條件**。
2. 若確實所有邏輯都正確，CRITIQUE.md 中應說明「已逐條核對 SPEC.md N 條需求，列出核對清單」，而不是直接說「沒有問題」。

---

## AP-3：Adversary 只測試快樂路徑（Adversary Tests Happy Path Only）

**症狀：** ATTACKS.md 中所有攻擊記錄都是「輸入合法數值，行為符合規格」，沒有任何邊界值、null 輸入、並發嘗試。

**為什麼失敗：** Happy path 測試是 implementer 自己應該做的事。Adversary 的工作是**假設存在漏洞**，用非正常輸入來找到它。只測試快樂路徑等同於沒有做 adversary 的工作。

**Recovery：**
1. Adversary 必須重新執行 Round 1，對每個函式的每個參數依序嘗試 `null`、空值、邊界值（0、-1、MAX）。
2. Round 1 結束前，ATTACKS.md 中必須有「攻擊失敗記錄」——如果 attacks 只有「以下攻擊均未嘗試」，Round 1 沒有完成。
3. 參考 `references/ATTACK-CLASSES.md` 中的三輪九類攻擊模式，確保 ATTACKS.md 覆蓋邊界、語意/業務邏輯、假設三個層次。

---

## AP-4：Disproof Agent 橡皮圖章式通過（Disproof Agent Rubber-stamps）

**症狀：** DISPROOF.md 中所有 severity >= 3 的發現都裁決為 `verified`，且每條裁決的理由都很簡短（「已確認，程式碼如 critic 描述」），沒有提供原始碼引用或反例構造。

**為什麼失敗：** Disproof Agent 的核心職責是**獨立核對**，而不是確認 critic/adversary 的說法。若每條都 verified，可能代表 disproof agent 沒有真正閱讀原始碼，只是接受了 CRITIQUE.md 的描述。

**Recovery：**
1. 對每條 `verified` 裁決，DISPROOF.md 中必須包含：（a）原始碼位置（`file:line`）；（b）反例構造結果（「我嘗試構造 X 輸入，結果 Y，確認問題存在」）。
2. 若 disproof agent 無法閱讀原始碼，裁決應為 `needs_user_decision`，不是 `verified`。
3. 至少應有一條發現被認真評估為 `rejected` 或 `needs_user_decision` 的可能性——所有發現都 verified 是一個警示訊號。

---

## AP-5：Verifier 未追溯需求就選擇實作（Verifier Chooses Without Requirement Trace）

**症狀：** VERIFICATION.md 中的「每個選擇的理由」只說「A 的實作更清晰」或「B 的寫法更簡潔」，沒有說明是哪條 SPEC.md 需求讓 A 優於 B。

**為什麼失敗：** Verifier 的選擇必須可追溯到規格，而不是風格偏好。「更清晰」是主觀評估，不能作為 Phase 4 整合決策的依據。

**Recovery：**
1. 每個選擇理由必須引用具體的 SPEC.md 需求：「選擇 A 因為 SPEC 需求 3.2 要求在 X 情況下返回 Y，A 的實作正確處理了此情況而 B 沒有」。
2. 若兩者在需求面完全等價（Type A 差異），可以用「可維護性/可讀性」作為次要依據，但必須先確認等價性。

---

## AP-6：修復循環失控（Unbounded Fix Loop）

**症狀：** Phase 3.5 的修復循環已進行了 3 次，每次 critic 重新審查後都發現新的 severity >= 3 問題，流程卡在 Phase 3-3.5 無法進入 Phase 4。

**為什麼失敗：** 修復循環上限是 3 次，設計上假設問題是可以收斂的。如果 3 次後仍有新問題，可能代表：（a）SPEC.md 本身有歧義；（b）implementer 的能力不足以解決此類問題；（c）critic 的標準太嚴格或方向有誤。

**Recovery：**
1. 達到 3 次修復循環上限後，必須用 `AskUserQuestion` 向使用者報告，提供以下資訊：
   - 每次修復解決的問題
   - 每次新出現的問題
   - 你對「為什麼沒有收斂」的評估
2. 不要靜默地進入第 4 次修復循環——這是設計上的 hard stop。
3. 考慮是否應退回 Phase 1 重新澄清 SPEC.md。

---

## AP-7：Phase 3.5 被靜默跳過（Phase 3.5 Silently Skipped）

**症狀：** CONSENSUS.md 中 Phase 3 標記了完成，但沒有 Phase 3.5 的記錄，且 ATTACKS.md 中有 severity >= 3 的成功攻擊。

**為什麼失敗：** Phase 3.5 的存在目的是在修復循環前獨立驗證發現的真實性，避免「修了 critic 誤判的問題」這個浪費。靜默跳過 Phase 3.5 等同於讓 adversary/critic 成為唯一的裁判，破壞了工作流程的認識論設計。

**Recovery：**
1. Phase 3.5 只有在 Phase 3 發現全部 severity <= 2 時才可跳過。
2. 若 Phase 3.5 因故無法執行（agent 不可用），必須在 CONSENSUS.md 記錄跳過原因，並用 `AskUserQuestion` 取得使用者確認。
3. Controller 應在進入修復循環前檢查 DISPROOF.md 是否存在——若不存在且應存在，停止並回報。
