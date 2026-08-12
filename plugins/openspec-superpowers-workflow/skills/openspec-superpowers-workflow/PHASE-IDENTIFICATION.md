# Phase Identification Reference

**When to read this:** 初次進入 OpenSpec + Superpowers 工作、使用者請求可能跨越多個 Phase、存在 `openspec/changes/<name>/` 但目前狀態不明，或你對 Phase 判斷不確定時讀此文件。若同一 session 已明確處於某 Phase，可直接讀 `phases.md` 的對應章節。

---

## 決策樹：使用者意圖 → Phase

```
使用者說的是什麼？
│
├─ "新功能"、"加功能"、"提議"、/opsx:propose、openspec new change
│   └─ → Phase 1（Spec Definition）
│
├─ "腦力激盪"、"設計思考"、"refinement"、"refine design"
│   ├─ 有 openspec/changes/<name>/ 資料夾存在？
│   │   ├─ Yes → Phase 2（Design Refinement）
│   │   └─ No → 先確認是否需要 Phase 1 建立 spec，再進入 Phase 2
│   └─
│
├─ "拆解任務"、"規劃實作"、"plan tasks"、"break down work"
│   └─ → Phase 3（Task Planning）（需要 design.md 存在）
│
├─ "實作"、"開始寫程式"、"execute"、"implement"
│   ├─ 有 openspec/changes/<name>/tasks.md 存在？
│   │   ├─ Yes → Phase 4（Implementation）
│   │   └─ No → 先完成 Phase 3
│   └─
│
├─ "code review"、"PR review"、"review feedback"、提到某個 PR comment
│   └─ → Phase 5（Review & Fix）
│
├─ "reconcile"、"archive"、"歸檔"
│   └─ → Phase 6（Reconcile & Archive）
│
└─ 不明確（見下方「模糊提示處理」）
```

---

## 常見模糊提示與正確 Phase 判斷

### Case 1：「幫我看一下這個設計」
- **有 openspec/changes/<name>/** → 可能是 Phase 2（refinement）或 Phase 5（review feedback）
- **區分方法**：問「你是想改進設計（Phase 2）還是 review 一個已實作的 PR（Phase 5）？」
- **Phase 5 紅線**：若確認是 Phase 5，**不能修改** proposal.md、specs/、design.md

### Case 2：「幫我寫這個功能」
- **有 tasks.md** → Phase 4，依照 tasks.md 實作
- **沒有 tasks.md** → 不要直接開始寫程式。先完成 Phase 1-3，再進入 Phase 4
- **常見錯誤**：直接跳到 Phase 4 寫程式，略過了 spec review 和 design 階段

### Case 3：「把這個 bug 修掉」
- **有 spec impact（行為變更）** → openspec new change <bugfix-name>，走 Phase 1-4
- **只是程式錯誤（no spec impact）** → 直接 TDD 修復，跳過 OpenSpec 流程
- **判斷標準**：修復後是否需要更新任何 SHALL/MUST 需求？是 → spec impact；契約面訊號（public API / data contract / schema / migration / 向後相容 / 安全權限邊界 / 並行一致性 / 跨模組行為）命中任一通常即有 spec impact，以 LOC / 檔案數判斷是錯誤代理指標
- **SKIP 判定程序**：決定跳過 OpenSpec 流程前，必須在回覆中逐項列出八項契約面的核對結論（不可整體宣稱「無契約面」）；先 `ls openspec/specs/` 對照——行為變更落在已涵蓋能力域 → 幾乎必有 spec impact（這是可查證的環境事實，優先於自由心證）。plugin 的 skip-gate hook 會在無 active change 的首次程式碼編輯 deny 一次，強制此程序留痕

### Case 4：「繼續上次的工作」
- 先執行 `ls openspec/changes/` 查看存在哪些 change 資料夾
- 檢查 tasks.md 的完成狀態，判斷目前在哪個 Phase
- 不要假設「上次」是在哪個 Phase——用狀態判斷

---

## openspec/changes/<name>/ 存在時的必要檢查

當對話中出現 `openspec/changes/<name>/` 資料夾時：

1. **確認 Phase 狀態**：
   - 只有 `proposal.md` + `specs/` → Phase 1 完成，待 Phase 2
   - `design.md` 已有實質內容（不是 placeholder）→ Phase 2 完成，待 Phase 3
   - `tasks.md` 已有任務清單 → Phase 3 完成，待 Phase 4
   - 有 `review-notes.md` 且有內容 → Phase 5 進行中

2. **不要假設**：不要根據資料夾名稱推測應該做什麼；根據**資料夾內容**的完成狀態決定下一步。

---

## 絕對禁止事項

- ❌ **Phase 5 期間修改任何 spec 檔案**（proposal.md、specs/、design.md）
  - 症狀：看到 review comment 後直接去修 spec，沒有先記錄在 review-notes.md
  - 後果：specs 在 reconcile 前就被污染，Phase 6 無法做乾淨的 clean rewrite
  
- ❌ **Phase 4 期間跳過 TDD**
  - 症狀：直接寫實作程式碼，說「之後再補測試」
  - 後果：違反 Phase 4 的強制 TDD 規則

- ❌ **未逐項核對八項契約面就 SKIP 本 workflow**
  - 症狀：憑「感覺是小改動」或某份摘要句（如使用者全域 CLAUDE.md 的一行選路 rubric）就直接開始編輯程式碼
  - 後果：契約面變更（如跨模組行為）繞過 spec 流程落地，事後才被抓回重走；skip-gate hook 會在首次編輯攔一次，但明示核對的責任在你

- ❌ **沒有看 phases.md 就直接開始執行**
  - 每個 Phase 的完整 playbook（包含 sync-back 規則）在 phases.md 中，SKILL.md 只是概覽
