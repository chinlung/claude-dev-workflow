# Multi-Agent Debate Anti-Patterns

**When to read this:** 當辯論品質出現退化跡象時，orchestrator、critic、validator 應立即讀此文件。退化跡象包括：方案在多輪後幾乎沒有改變、Critic 的挑戰每輪都一樣、Validator 直接通過了一個沒有解決核心問題的方案，或使用者回報「辯論看起來在繞圈子」。

---

## AP-1：過早共識（Premature Consensus）

**症狀：** 只有 2-3 輪，各 Agent 就表示「同意」彼此的方案，但方案其實只是用詞上更相似，核心差異沒有被解決。

**為什麼失敗：** Perspective agents 可能因為「社交性同意」（避免衝突）而收斂，而不是因為真正的論點說服了彼此。表面共識掩蓋了尚未解決的技術分歧。

**Recovery：**
1. Orchestrator 或 Critic 需要識別：哪些**核心設計決策**在方案間仍有實質差異？
2. 強制 Critic 對每個「同意」陳述提出一個反例輸入：「如果你們都同意這個方案，請分別說明當 [具體邊界情況] 時，你們的方案各自如何處理？」
3. 若差異確實消失（真正收斂），在共識觀察中記錄差異消失的具體原因。

---

## AP-2：Critic 變成第四位方案作者（Critic Becomes Fourth Solution Author）

**症狀：** Critic 不再提問，開始直接說「你應該改用 X 技術」或「正確的做法是 Y」，讓 Perspective agents 的方案逐漸趨向 Critic 心中的「理想答案」。

**為什麼失敗：** 這破壞了辯論的認識論基礎——Critic 的 viewpoint 沒有被任何其他 Agent 審查過，但它的影響力卻大於三個 Perspective agents；最終產出變成「Critic 的方案」，不是「辯論產出的最優方案」。

**Recovery：**
1. Orchestrator 在下一輪 Critic 的 Task prompt 中加入指示：先讀 `CRITIQUE-METHODOLOGY.md` 的「核心職責提醒」和「好的挑戰 vs 壞的挑戰」，確認自己是在提問而非給答案。
2. 將 Critic 在本輪給出的「建議」改寫成「問題」：「你說要用 event sourcing——你的方案如何保證消費者冪等性？」
3. 若問題模式已發生多輪，orchestrator 應介入重申 Critic 的純批判者角色。

---

## AP-3：Perspective Agents 因社交同意而收斂（Social Convergence）

**症狀：** Agent 回應 Critic 時說「你說得對，我調整方案」，但回應內容非常模糊，沒有說明調整了什麼、為什麼這樣調整解決了問題。

**為什麼失敗：** 方案沒有實質改進，只是在表述上更接近其他 Agent 或 Critic 的語言。共識分數虛高，最終方案可能比第一輪的原始方案更差（因為邊界被磨去了）。

**Recovery：**
1. Critic 要求 Agent 具體說明：「你調整了什麼？請用前後對照的方式呈現，說明哪行邏輯改變了。」
2. 若 Agent 無法提供具體的前後對照，視為「未回應挑戰」，評分不提升。
3. Orchestrator 可以要求 Agent 保留原始方案，只在修正區塊說明差異（避免整個方案被社交壓力重寫）。

---

## AP-4：使用者繞過 Validator 直接採納（User Adoption Bypasses Validator）

**症狀：** 使用者在 Phase 5 選擇「採納」，但 Validator gate 尚未執行，或者 orchestrator 靜默跳過了 Validator。

**為什麼失敗：** Validator 的核心職責是確認候選方案有辯論證據支持、未解決異議已被記錄。繞過它意味著最終輸出可能包含在辯論中被 Critic 明確指出但未解決的問題。

**Recovery：**
1. 無論使用者選擇何時「採納」，Phase 5.5 Validator gate 不可跳過。
2. 若 Validator 因故無法執行，必須在最終輸出中明確標注「⚠️ Validator 未執行，原因：{具體原因}」，並列出已知的未解決異議。
3. 不得用「使用者已選擇採納」作為跳過 Validator 的理由。

---

## AP-5：舊異議被忽略（Stale Objection Ignored）

**症狀：** Critic 在第一輪提出了一個具體挑戰（例如「你的方案沒處理並發寫入」），Agent 回應了但沒有真正解決，之後的輪次 Critic 沒有再追問，最終方案仍然沒有解決這個問題。

**為什麼失敗：** 舊異議被遺忘或被後來的對話「稀釋」，評分可能因為方案在其他面向的改進而提升，掩蓋了核心問題未解決的事實。

**Recovery：**
1. Critic 每輪開始前，應先回顧「本議題的未解決挑戰清單」，確認上一輪提出的挑戰是否已充分回應。
2. 若上一輪挑戰未充分回應，此輪應繼續追問（不是重複問相同問題，而是問「你上輪說 X 但沒說 Y，請補充 Y」）。
3. Validator 需在 Phase 5.5 盤點「所有 Critic 曾提出的 severity >= 2 挑戰是否都已充分回應」，這是其驗證清單的必要項目。
