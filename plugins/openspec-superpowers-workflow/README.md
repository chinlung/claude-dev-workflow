# OpenSpec + Superpowers Workflow Plugin

強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離的六階段功能開發工作流程，避免兩種工具的職責重疊與規格漂移。

## 前置需求

- **[OpenSpec CLI](https://github.com/Fission-AI/OpenSpec)**（`npm i -g @fission-ai/openspec`）— 規格生命週期管理
- **[Superpowers](https://github.com/anthropic-experimental/claude-code-plugins/tree/main/superpowers)** — 開發紀律 skills（`brainstorming`、`writing-plans`、`subagent-driven-development`、`test-driven-development` 等）
- 專案需先跑過 `openspec init .`（無 `--here` flag）

## 概述

這個 plugin 包含一個 skill（`openspec-superpowers-workflow`）與一個 PreToolUse hook（skip-gate，見下方專節）。當 skill 偵測到使用者在進行功能開發任務（propose / brainstorm / plan / implement / review / reconcile / archive）時會被自動觸發，引導 Claude 依六階段推進，並嚴格禁止常見的反模式（如 Phase 5 code review 期間改 spec、Phase 6 reconcile 時用 patch 而非 clean rewrite、把 cross-cutting 規則塞進 feature spec 等）。

## 六階段工作流程

| Phase | 主導工具 | 動作 | 產出 |
|-------|---------|------|------|
| 1. Spec Definition | OpenSpec | `openspec new change` + 填入 proposal / specs | `proposal.md`、`specs/<capability>/spec.md`（使用者審核） |
| 2. Design Refinement | Superpowers `brainstorming` | Socratic 問答精煉設計 | **覆寫** `design.md` |
| 3. Task Planning | Superpowers `writing-plans` | 切出 2-5 分鐘粒度任務 | **覆寫** `tasks.md` |
| 4. Implementation | Superpowers `subagent-driven-development` + TDD | RED → GREEN → REFACTOR | 程式碼 |
| 5. Review & Feedback | 人類主導 | 分類 `[REQUIREMENT\|DESIGN\|CODE\|CONSTITUTION]` + Y/N | `review-notes.md`，**spec 一律不動** |
| 6. Reconcile & Archive | OpenSpec | Clean rewrite spec（非 patch）+ `openspec archive` | 歸檔至 `openspec/changes/archive/<date>-<name>/`，合併到 `openspec/specs/` |

## 不可妥協的六條硬規則

1. **Phase 5 期間絕不修改 spec 檔**。所有審查意見必須記到 `review-notes.md`，用 `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 加 Y/N 分類——Y 只回答「Phase 6 是否必須更新某個 OpenSpec artifact」，不是「已處理」，所以 `[CODE] Y` 不存在；tag 看修改落在哪個檔案，不看問題性質。1.5.0 起 Phase 1 建檔即預填一段標頭把這套語意釘住，避免各專案自行發明「Y = 已處理」（真實歸檔資料曾出現 54 條 `[CODE] Y`）。被明確要求「現在改 spec」時必須明講拒絕並記錄，不得默默改道
2. **Superpowers 絕不新建自己的 design / plan 檔**。輸出一律覆寫 OpenSpec 的 `design.md` / `tasks.md` 原位
3. **Phase 6 reconcile 必須 clean rewrite**。目標是讓 spec 讀起來像「一開始就知道所有這些事」，而非「一份加註解的修訂史」
4. **`tasks.md` 在 reconcile 時絕不修改**。它是執行歷史，不是當前規格
5. **`[CONSTITUTION]` 項目絕不進 feature spec**。改到 `openspec/config.yaml` 的 `context:` / `rules:` 欄位
6. **Phase 4 TDD 強制**。先寫失敗測試，再寫實作，永遠如此

## Skill 結構（Progressive Disclosure）

```
skills/openspec-superpowers-workflow/
├── SKILL.md                    # 61 行：trigger 條件、SKIP 條款、phase map、六條硬規則（常駐載入）
├── PHASE-IDENTIFICATION.md     # 95 行：Phase 判定決策樹、SKIP 判定程序（Phase 不明時載入）
├── phases.md                   # 330 行：完整六階段 playbook、tag 分類細節、路徑慣例、anti-pattern（需要時才載入）
├── SUPERPOWERS-HANDOFF.md      # 140 行：Phase 2/3/4 sync-back 範本、sidecar 檔 anti-pattern
├── OUTPUT-CONTRACTS.md         # 218 行：各 Phase 產出契約、requirement 寫法正反例、deferred 項慣例
├── RECONCILIATION-CRITERIA.md  # 116 行：Phase 6 歸檔前核查清單
└── validators/
    └── validate-openspec-workflow.cjs  # change folder 寬鬆 pre-check（見下方 Validator）
```

觸發時 Claude 先讀 `SKILL.md`，確認當前 Phase 後只載入該 Phase 需要的 reference（Phase 不明讀 `PHASE-IDENTIFICATION.md`、playbook 讀 `phases.md` 對應段落、Phase 2/3/4 交接讀 `SUPERPOWERS-HANDOFF.md`、Phase 6 歸檔前讀 `RECONCILIATION-CRITERIA.md`），避免一次吃下近 900 行拖慢 context。

## 解決的問題

無此 skill 時常見的混亂：

- ❌ 跑完 Superpowers `brainstorming` 後把結果寫到 `docs/superpowers/specs/<date>-<topic>.md`（Superpowers 預設路徑），而非覆寫 OpenSpec 的 `design.md`，導致兩份「設計檔」彼此漂移
- ❌ Code review 拿到意見後直接改 spec，archive 時才發現 spec 和實作對不上
- ❌ Phase 6 reconcile 時用「加一段 Round 1 修訂」的方式 patch spec，結果半年後沒人看得懂修訂史
- ❌ 把「所有 PHP 檔都要 `declare(strict_types=1)`」這種 cross-cutting 規則塞進某個 feature 的 spec，下個 feature 又要重寫一遍

有此 skill 時：

- ✅ Claude 自動認出當前 Phase 並套用對應紀律
- ✅ 所有中間產物都落在 `openspec/changes/<name>/` 同一個資料夾，不會分散
- ✅ `review-notes.md` 作為 Phase 5/6 的唯一 feedback 通道，reconcile 時有明確的 Y 項清單
- ✅ CONSTITUTION 規則有明確的寫入目標（`openspec/config.yaml`），不會污染 feature spec

## 何時不適用

- 單一模組、驗收明確、且不觸碰任何契約面（public API / data contract / schema / migration / 向後相容 / 安全權限邊界 / 並行一致性 / 跨模組行為）的變更，例如無規格影響的小型 bug 修復 — 直接用裸 superpowers skills 以 TDD 修好，不走六階段；看契約風險，不看 LOC 或檔案數。SKIP 前必須逐項核對八項契約面並在回覆中明示結論（見下方 skip-gate hook）

SKIP 的唯一依據是上述契約面判定，沒有其他豁免類別（例如「原型探索」本身不構成豁免，仍依契約面判定）。**觸發也不以專案已有 `openspec/` 資料夾為前提**：只要是提出／新增／精煉 feature 等 trigger 條件即觸發；專案尚未初始化時，skill 會在前置檢查引導執行 `openspec init .`。

## 用法提示

你通常不需要「手動呼叫」這個 skill — 它會在你說「propose a new feature」、「brainstorm the design」、「plan the tasks」、「I got PR review feedback」、「reconcile and archive」等關鍵字時自動觸發。真要手動執行：

```
/skill openspec-superpowers-workflow
```

進入 skill 後它會先讀取當前專案狀態（`which openspec`、`ls openspec/`、`ls .claude/commands/opsx/`），依結果引導你走正確的 Phase。

## Skip-gate Hook（1.4.0+）

SKIP 判定曾在真實 session 中被「憑摘要句自由心證」繞過（變更實際觸碰跨模組行為、且落在已 spec 化能力域）。根因是 SKIP 屬「以不動作達成」的隱式決策，沒有 artifact 逼八項契約面核對真的發生。skip-gate hook 把它機器化為顯式程序：

- **觸發條件**（全部成立才攔）：專案有 `openspec/` 目錄；`openspec/changes/` 無 active change（`archive/` 不算）；本次編輯的是專案內一般檔案（`openspec/`、`.claude/` 本身豁免——寫 proposal/spec 是 workflow 動作）；本 session 尚未攔過
- **行為**：deny 該次編輯，要求在回覆中逐項核對八項契約面並明示結論後重試；同一並行批次的手足編輯會在批次窗（flag 建立後 5 秒）內一併被攔——否則首批多檔編輯只攔得住一個；窗外重試放行，一 session 只完整觸發一輪
- **界線**：hook 只逼「判斷發生且留痕」，不驗證判斷內容（契約風險是語意判斷，機器判不了）；全面 fail-open——jq 缺失、輸入異常、不明工具形狀等任何錯誤路徑都放行，絕不卡死編輯；matcher 只綁核心編輯工具（Edit/Write/MultiEdit/NotebookEdit），MCP 檔案編輯工具（serena、morphllm 等）不經這些工具名，不在覆蓋面內
- **測試**：`bash plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh`（已接 CI；deny 路徑、flag 去重、archive 排除、路徑豁免均經 mutation 驗證）
- **Live 實測**：1.4.2 已於真實 session end-to-end 驗證（2026-08-13）——首批並行雙 Edit 一併被攔、逐面聲明後重試乾淨放行、非 BSD `stat` 環境（nix devshell）無崩潰、flag 於同 session 跨 plugin reload 存續

## 版本

詳見 [CHANGELOG.md](./CHANGELOG.md)。

## Validator

OpenSpec change folders are validated by a zero-dependency Node script. Run from the repo root:

```bash
# Validate a change folder (checks required files + SHALL/MUST in spec.md requirement blocks)
node plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs openspec/changes/<name>

# Run all fixture checks
node scripts/validate-fixtures.cjs
```

> The `.cjs` validator is a fast, lenient **pre-check**: it confirms the required files exist and that each `### Requirement:` block's first paragraph contains SHALL/MUST (a bullet immediately after the heading is treated as that paragraph). It does not fully replicate `openspec validate --strict` — the strict CLI remains the authoritative gate (e.g. it rejects a SHALL that appears only inside a bullet list). Run `openspec validate --strict` before archiving.
