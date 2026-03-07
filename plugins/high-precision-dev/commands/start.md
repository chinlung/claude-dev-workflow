---
description: 啟動高精確度開發模式的 4 Phase 工作流程，透過 5 個 agent 將錯誤率從 p 壓縮至 p^4
argument-hint: <SPEC.md 路徑> [--phase N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, AskUserQuestion
---

# /start - 高精確度開發流程

啟動 4 Phase 高精確度開發流程。透過 5 個專業 agent（implementer-a、implementer-b、critic、adversary、verifier）的認識論分工，將單一 agent 的錯誤率 p 壓縮至 p^4。

## 參數解析

從 `$ARGUMENTS` 中解析：
- SPEC.md 路徑（第一個非 `--` 開頭的參數，若未指定則在當前目錄尋找）
- `--phase N`：指定從 Phase N 開始（預設從 Phase 1 開始）

## 前置檢查

1. 讀取 SPEC.md 路徑指向的檔案
2. 確認 SPEC.md 存在且所有欄位已填寫（不能有空的佔位符）
3. 確認 CONSENSUS.md 存在於同一目錄
4. 記錄 SPEC.md 所在目錄作為所有產出文件的統一存放路徑

如果前置檢查失敗，告知使用者先執行 `/high-precision-dev:init` 並填寫 SPEC.md。

## Phase 跳轉

如果使用者指定了 `--phase N`，檢查前置條件後跳轉：
- `--phase 2`：需確認 CONSENSUS.md Phase 1 已完成
- `--phase 3`：需確認 CONSENSUS.md Phase 2 已完成，且兩份 IMPL REPORT 存在
- `--phase 4`：需確認 CONSENSUS.md Phase 3 已完成，且 CRITIQUE.md 和 ATTACKS.md 存在

如果前置條件不滿足，告知使用者缺少哪些前置產出，建議從正確的 Phase 開始。

---

## Phase 1：規格確認

使用 Task 工具**並行**派出 4 個 agent 審查 SPEC.md：

```
Task(
  subagent_type="high-precision-dev:implementer-a",
  prompt="閱讀以下 SPEC.md，找出任何歧義、矛盾、或缺漏的邊界條件。\n\nSPEC.md 路徑：{路徑}\n\n列出你發現的具體問題（不是模糊的「感覺有問題」）。如果沒有問題，說明你確認的範圍。",
  run_in_background=true
)

// 同樣派出 implementer-b、critic、adversary
```

收集 4 個 agent 的回饋後：
- 如有問題，整理問題列表，用 AskUserQuestion 詢問使用者裁決
- 將裁決結果更新到 SPEC.md 的 Phase 1 修訂記錄和 CONSENSUS.md
- 所有問題解決後，在 CONSENSUS.md Phase 1 區段標記完成

**Gate：所有問題都已裁決才能進入 Phase 2。**

---

## Phase 2：獨立實作（並行，worktree 隔離）

**並行**派出兩個 implementer，各自在獨立 worktree 中實作：

```
Task(
  subagent_type="high-precision-dev:implementer-a",
  prompt="嚴格依照 SPEC.md 實作。\n\nSPEC.md 路徑：{路徑}\nCONSENSUS.md 路徑：{路徑}\n\n你不能查看 implementer-b 的任何輸出。\n完成後在 {產出目錄} 提交 IMPL_A_REPORT.md。",
  isolation="worktree",
  run_in_background=true
)

Task(
  subagent_type="high-precision-dev:implementer-b",
  prompt="嚴格依照 SPEC.md 實作。\n\nSPEC.md 路徑：{路徑}\nCONSENSUS.md 路徑：{路徑}\n\n你不能查看 implementer-a 的任何輸出。\n完成後在 {產出目錄} 提交 IMPL_B_REPORT.md。",
  isolation="worktree",
  run_in_background=true
)
```

等待兩個 implementer 都完成後：
- 確認兩份 IMPL REPORT 都已提交
- 在 CONSENSUS.md Phase 2 區段標記完成
- 記錄兩個 worktree 的路徑，Phase 3 需要傳給 critic 和 adversary

---

## Phase 3：對抗審查（並行）

**並行**派出 critic 和 adversary：

```
Task(
  subagent_type="high-precision-dev:critic",
  prompt="審查兩份獨立實作。\n\nSPEC.md 路徑：{路徑}\nImplementer-A worktree：{路徑}\nImplementer-B worktree：{路徑}\nIMPL_A_REPORT.md：{路徑}\nIMPL_B_REPORT.md：{路徑}\n\n輸出 CRITIQUE.md 到 {產出目錄}。",
  run_in_background=true
)

Task(
  subagent_type="high-precision-dev:adversary",
  prompt="攻擊兩份獨立實作。\n\nSPEC.md 路徑：{路徑}\nImplementer-A worktree：{路徑}\nImplementer-B worktree：{路徑}\nIMPL_A_REPORT.md：{路徑}\nIMPL_B_REPORT.md：{路徑}\n\n輸出 ATTACKS.md 到 {產出目錄}。",
  run_in_background=true
)
```

收集結果後檢查：
- 如有 severity >= 3 的問題：退回給對應 implementer 修復
  - 修復後 critic 必須重新審查該問題，**並確認修復未引入新的 severity >= 3 問題**
  - adversary 需對修復涉及的函數重新進行 Round 1 邊界攻擊
  - **修復循環上限：3 次。** 超過後用 AskUserQuestion 向使用者報告並等待裁決
- 當 critic 宣告「所有問題 severity <= 1」且 adversary 宣告「3 輪攻擊均失敗」：在 CONSENSUS.md Phase 3 區段標記完成

---

## Phase 4：整合

只有 Phase 3 完全收斂後才執行：

```
Task(
  subagent_type="high-precision-dev:verifier",
  prompt="比較兩份實作，逐條對照 SPEC.md，產生最終實作和 VERIFICATION.md。\n\nSPEC.md 路徑：{路徑}\nCONSENSUS.md 路徑：{路徑}\nImplementer-A worktree：{路徑}\nImplementer-B worktree：{路徑}\nCRITIQUE.md：{路徑}\nATTACKS.md：{路徑}\nIMPL_A_REPORT.md：{路徑}\nIMPL_B_REPORT.md：{路徑}\n\n輸出最終實作和 VERIFICATION.md 到 {產出目錄}。"
)
```

如果 verifier 回報 Type D 差異（無法合併）：
1. 評估問題是否源自 SPEC.md 歧義 → 退回 Phase 1
2. 評估問題是否源自實作品質 → 退回 Phase 2
3. 用 AskUserQuestion 向使用者報告並等待裁決

---

## 完成報告

Phase 4 完成後，向使用者彙整報告：

```markdown
# 高精確度開發完成報告

## 最終實作位置
[路徑]

## Phase 3 發現的問題（即使已修復）
[列表]

## 兩份實作的主要差異
[verifier 的選擇及理由]

## 已知的不確定性
[來自 VERIFICATION.md]

## 產出文件
- SPEC.md
- CONSENSUS.md
- IMPL_A_REPORT.md
- IMPL_B_REPORT.md
- CRITIQUE.md
- ATTACKS.md
- VERIFICATION.md
```

---

## 異常處理

**如果任務複雜度不適合此框架**：向使用者報告評估，建議降級到單一 agent 開發或使用 `/multi-agent-debate:debate` 進行方案決策。

**如果 SPEC.md 有歧義無法解決**：停止所有工作，向使用者報告具體的歧義點，等待裁決。

**如果 critic 和 adversary 的發現互相矛盾**：不要自行裁決，向使用者列出矛盾點並等待指示。
